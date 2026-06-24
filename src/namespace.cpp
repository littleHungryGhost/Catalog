/*-------------------------------------------------------------------------
 *
 * namespace.cpp
 *    Iceberg namespace SQL function implementations.
 *
 * META operations are marked as TODO, pending the underlying modules
 * to be wired up. Currently returns a minimal response.
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"
#include "executor/spi.h"
#include "utils/builtins.h"
#include "utils/jsonb.h"
#include "lib/stringinfo.h"

#include <string.h>

#include "errors.h"
#include "iceberg_catalog.h"
#include "json_util.h"
#include "metadata.h"
#include "namespace.h"


/* ------------------------------------------------------------------ */
/*  DDL helpers (schema create / drop for FDW foreign tables)          */
/* ------------------------------------------------------------------ */

/*
 * Create the openGauss schema that will host FDW foreign tables for
 * the given Iceberg namespace.
 *
 * Runs in its own SPI context; the surrounding transaction ensures
 * the schema is rolled back if the META INSERT fails later.
 */
static void
ddl_create_schema(const char *namespace_name)
{
    StringInfoData sql;
    int rc;

    initStringInfo(&sql);
    appendStringInfo(&sql, "CREATE SCHEMA %s",
                     quote_identifier(namespace_name));

    connect_spi();

    rc = SPI_execute(sql.data, false, 0);
    if (rc != SPI_OK_UTILITY)
        ereport(ERROR,
                (errcode(ERRCODE_INTERNAL_ERROR),
                 errmsg("failed to create schema \"%s\"", namespace_name)));

    finish_spi();
    pfree(sql.data);
}

/*
 * Drop the openGauss schema that hosted FDW foreign tables for the
 * given Iceberg namespace.
 */
static void
ddl_drop_schema(const char *namespace_name)
{
    StringInfoData sql;
    int rc;

    initStringInfo(&sql);
    appendStringInfo(&sql, "DROP SCHEMA %s CASCADE",
                     quote_identifier(namespace_name));

    connect_spi();

    rc = SPI_execute(sql.data, false, 0);
    if (rc != SPI_OK_UTILITY)
        ereport(ERROR,
                (errcode(ERRCODE_INTERNAL_ERROR),
                 errmsg("failed to drop schema \"%s\"", namespace_name)));

    finish_spi();
    pfree(sql.data);
}


/* ---- create_namespace ---- */
PG_FUNCTION_INFO_V1(iceberg_create_namespace);

Datum
iceberg_create_namespace(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_namespace   TEXT    (required)
     *   2. p_properties  JSONB   (optional, default NULL)
     *
     * Returns: JSONB (CreateNamespaceResponse)
     *   {"namespace": ["<namespace>"], "properties": {<key>: <value>, ...}}
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters from PG_FUNCTION_ARGS */
    if (PG_NARGS() < 1)
        elog(ERROR, "iceberg_create_namespace: expected at least 1 argument, got %d", PG_NARGS());

    /* p_namespace (required) */
    char *p_namespace = NULL;
    if (!PG_ARGISNULL(0))
        p_namespace = text_to_cstring(PG_GETARG_TEXT_P(0));

    /* p_properties (optional, default NULL -> treat as empty object {}) */
    Jsonb *p_properties = NULL;
    if (PG_NARGS() > 1 && !PG_ARGISNULL(1))
        p_properties = DatumGetJsonb(PG_GETARG_DATUM(1));

    /* 2. Validate p_namespace */
    if (p_namespace == NULL || strlen(p_namespace) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("namespace must not be empty")));

    /* 3. Validate p_properties (if provided, must be a JSONB object) */
    if (p_properties != NULL)
    {
        if (!iceberg_jsonb_is_type(p_properties, "object"))
            ereport(ERROR,
                    (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                     errmsg("p_properties must be a JSONB object")));
    }

    /* 4. Serialize properties for InsertNamespace and response */
    char *props_str;
    if (p_properties != NULL)
        props_str = iceberg_jsonb_to_cstring(p_properties);
    else
        props_str = pstrdup("{}");

    /* 5. Create FDW schema for this namespace */
    PG_TRY();
    {
        ddl_create_schema(p_namespace);
    }
    PG_CATCH();
    {
        ErrorData *edata = CopyErrorData();
        iceberg_err_rethrow_metadata(edata, "create namespace schema");
    }
    PG_END_TRY();

    /* 6. META InsertNamespace */
    PG_TRY();
    {
        iceberg_meta_create_namespace(p_namespace, props_str);
    }
    PG_CATCH();
    {
        ErrorData *edata = CopyErrorData();
        iceberg_err_rethrow_metadata(edata, "create namespace metadata");
    }
    PG_END_TRY();

    /* 7. Construct and return response */
    StringInfoData buf;

    initStringInfo(&buf);
    appendStringInfo(&buf,
        "{\"namespace\":[\"%s\"],\"properties\":%s}",
        p_namespace, props_str);
    PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
        CStringGetDatum(buf.data)));
}


/* ---- update_namespace_properties ---- */
PG_FUNCTION_INFO_V1(iceberg_update_namespace_properties);

Datum
iceberg_update_namespace_properties(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_namespace  TEXT    (required)
     *   2. p_removals   JSONB   (optional, default NULL — keys to remove)
     *   3. p_updates    JSONB   (optional, default NULL — keys to set/update)
     *
     * Returns: JSONB (UpdateNamespacePropertiesResponse)
     *   Updated properties as JSONB object, e.g. {"owner": "new", "region": "us"}
     *
     * Errors:
     *   P0001 — p_namespace is NULL/empty, or both p_removals & p_updates NULL,
     *           or p_removals not an array, or p_updates not an object
     *   P0006 — removals ∩ updates ≠ ∅ (overlapping keys)
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters from PG_FUNCTION_ARGS */
    if (PG_NARGS() < 1)
        elog(ERROR, "iceberg_update_namespace_properties: expected at least 1 argument, got %d", PG_NARGS());

    /* p_namespace (required) */
    char *p_namespace = NULL;
    if (!PG_ARGISNULL(0))
        p_namespace = text_to_cstring(PG_GETARG_TEXT_P(0));

    /* p_removals (optional, default NULL) */
    Jsonb *p_removals = NULL;
    if (PG_NARGS() > 1 && !PG_ARGISNULL(1))
        p_removals = DatumGetJsonb(PG_GETARG_DATUM(1));

    /* p_updates (optional, default NULL) */
    Jsonb *p_updates = NULL;
    if (PG_NARGS() > 2 && !PG_ARGISNULL(2))
        p_updates = DatumGetJsonb(PG_GETARG_DATUM(2));

    /* 2. Validate p_namespace */
    if (p_namespace == NULL || strlen(p_namespace) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("namespace must not be empty")));

    /* 3. Validate: p_removals and p_updates cannot both be NULL */
    if (p_removals == NULL && p_updates == NULL)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_removals and p_updates cannot both be NULL")));

    /* 4. Validate: p_removals (if non-NULL) must be a JSONB array */
    if (p_removals != NULL)
    {
        if (!iceberg_jsonb_is_type(p_removals, "array"))
            ereport(ERROR,
                    (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                     errmsg("p_removals must be a JSONB array")));
    }

    /* 5. Validate: p_updates (if non-NULL) must be a JSONB object */
    if (p_updates != NULL)
    {
        if (!iceberg_jsonb_is_type(p_updates, "object"))
            ereport(ERROR,
                    (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                     errmsg("p_updates must be a JSONB object")));
    }

    /* 6. Validate removals ∩ updates = ∅ */
    if (p_removals != NULL && p_updates != NULL)
    {
        JsonbSuperHeader rem_header = (JsonbSuperHeader) VARDATA(p_removals);
        JsonbSuperHeader upd_header = (JsonbSuperHeader) VARDATA(p_updates);
        JsonbIterator *it;
        JsonbValue v;
        int tok;

        it = JsonbIteratorInit(rem_header);
        while ((tok = JsonbIteratorNext(&it, &v, true)) != WJB_DONE)
        {
            if (tok == WJB_ELEM)
            {
                JsonbValue *found = FindJsonbValueFromUnsortedObjects(upd_header, &v);
                if (found != NULL)
                    ereport(ERROR,
                            (errcode(ERRCODE_ICEBERG_CONSTRAINT_VIOL),
                             errmsg("removals and updates must not contain overlapping keys")));
            }
        }
    }

    /* 7. TODO: META UpdateNamespaceProperties
     *
     * char *removals_str = (p_removals != NULL)
     *     ? jsonb_to_cstring(p_removals)
     *     : "[]";
     * char *updates_str = (p_updates != NULL)
     *     ? jsonb_to_cstring(p_updates)
     *     : "{}";
     * char *result = iceberg_meta_update_namespace_properties(
     *     p_namespace, removals_str, updates_str);
     * PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in, CStringGetDatum(result)));
     */

    /* 8. Stub: return empty object.
     * TODO: Replace with META.UpdateNamespaceProperties() result once META module is available. */
    PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
        CStringGetDatum("{}")));
}


/* ---- is_namespace_existed ---- */
PG_FUNCTION_INFO_V1(iceberg_is_namespace_existed);

Datum
iceberg_is_namespace_existed(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_namespace  TEXT  (required)
     *
     * Returns: JSONB
     *   {"exists": true}   — namespace exists
     *   {"exists": false}  — namespace does not exist (no exception thrown)
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters from PG_FUNCTION_ARGS */
    if (PG_NARGS() < 1)
        elog(ERROR, "iceberg_is_namespace_existed: expected 1 argument, got %d", PG_NARGS());

    /* p_namespace (required) */
    char *p_namespace = NULL;
    if (!PG_ARGISNULL(0))
        p_namespace = text_to_cstring(PG_GETARG_TEXT_P(0));

    /* 2. Validate required parameters */
    if (p_namespace == NULL || strlen(p_namespace) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("namespace must not be empty")));

    /* 3. Check namespace existence via META */
    bool exists = false;

    PG_TRY();
    {
        exists = iceberg_meta_namespace_exists(p_namespace);
    }
    PG_CATCH();
    {
        ErrorData *edata = CopyErrorData();
        iceberg_err_rethrow_metadata(edata, "check namespace existence");
    }
    PG_END_TRY();

    /* 4. Return result */
    PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
        CStringGetDatum(exists ? "{\"exists\": true}" : "{\"exists\": false}")));
}


/* ---- drop_namespace ---- */
PG_FUNCTION_INFO_V1(iceberg_drop_namespace);

Datum
iceberg_drop_namespace(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_namespace  TEXT  (required)
     *
     * Returns: JSONB
     *   {"success": true}
     *
     * Errors:
     *   P0001 — p_namespace is NULL or empty
     *   P0004 — namespace does not exist
     *   P0005 — namespace still contains tables (foreign key constraint)
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters from PG_FUNCTION_ARGS */
    if (PG_NARGS() < 1)
        elog(ERROR, "iceberg_drop_namespace: expected 1 argument, got %d", PG_NARGS());

    /* p_namespace (required) */
    char *p_namespace = NULL;
    if (!PG_ARGISNULL(0))
        p_namespace = text_to_cstring(PG_GETARG_TEXT_P(0));

    /* 2. Validate p_namespace */
    if (p_namespace == NULL || strlen(p_namespace) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("namespace must not be empty")));

    /* 3. Check namespace exists */
    bool ns_exists = false;

    PG_TRY();
    {
        ns_exists = iceberg_meta_namespace_exists(p_namespace);
    }
    PG_CATCH();
    {
        ErrorData *edata = CopyErrorData();
        iceberg_err_rethrow_metadata(edata, "drop namespace existence check");
    }
    PG_END_TRY();

    if (!ns_exists)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_NOT_FOUND),
                 errmsg("The given namespace does not exist")));

    /* 4. TODO: META Check namespace has no tables
     *
     * if (iceberg_meta_namespace_has_tables(p_namespace))
     *     ereport(ERROR,
     *             (errcode(ERRCODE_ICEBERG_CONFLICT),
     *              errmsg("Cannot drop namespace: tables still exist")));
     */

    /* 5. TODO: META DeleteNamespace
     *
     * iceberg_meta_delete_namespace(p_namespace);
     */

    /* 6. Drop FDW schema for this namespace */
    PG_TRY();
    {
        ddl_drop_schema(p_namespace);
    }
    PG_CATCH();
    {
        ErrorData *edata = CopyErrorData();
        iceberg_err_rethrow_metadata(edata, "drop namespace schema");
    }
    PG_END_TRY();

    /* 7. Stub: return success.
     * TODO: Replace with META steps above once META module is available. */
    PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
        CStringGetDatum("{\"success\": true}")));
}


/* ---- load_namespace ---- */
PG_FUNCTION_INFO_V1(iceberg_load_namespace);

Datum
iceberg_load_namespace(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_namespace  TEXT  (required)
     *
     * Returns: JSONB (GetNamespaceResponse)
     *   {"namespace": ["<namespace>"], "properties": {<key>: <value>, ...}}
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters from PG_FUNCTION_ARGS */
    if (PG_NARGS() < 1)
        elog(ERROR, "iceberg_load_namespace: expected 1 argument, got %d", PG_NARGS());

    /* p_namespace (required) */
    char *p_namespace = NULL;
    if (!PG_ARGISNULL(0))
        p_namespace = text_to_cstring(PG_GETARG_TEXT_P(0));

    /* 2. Validate p_namespace */
    if (p_namespace == NULL || strlen(p_namespace) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("namespace must not be empty")));

    /* 3. TODO: META GetNamespace
     *
     * NamespaceInfo meta_info = iceberg_meta_get_namespace(p_namespace);
     * if (meta_info == NULL)
     *     ereport(ERROR,
     *             (errcode(ERRCODE_ICEBERG_NOT_FOUND),
     *              errmsg("The given namespace does not exist")));
     * StringInfo buf = makeStringInfo();
     * appendStringInfo(buf,
     *     "{\"namespace\":[\"%s\"],\"properties\":%s}",
     *     meta_info.namespace_name,
     *     meta_info.properties);
     * PG_RETURN_JSONB_P(jsonb_parse(buf->data));
     */

    /* 4. Stub: return minimal response.
     * TODO: Replace with META.GetNamespace() result once META module is available. */
    PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
        CStringGetDatum("{\"namespace\":[\"TODO\"],\"properties\":{}}")));
}


/* ---- list_namespaces ---- */
PG_FUNCTION_INFO_V1(iceberg_list_namespaces);

Datum
iceberg_list_namespaces(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_parent      TEXT     (optional, default NULL)
     *   2. p_page_size   INTEGER  (optional, default 1000)
     *   3. p_page_token  TEXT     (optional, default NULL)
     *
     * Returns: JSONB (ListNamespacesResponse)
     *   {"namespaces": [["ns1"], ...], "next-page-token": "<token>"}
     *   Last page: {"namespaces": [...], "next-page-token": null}
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters from PG_FUNCTION_ARGS */
    /* p_parent (optional, default NULL) */
    char *p_parent = NULL;
    if (PG_NARGS() > 0 && !PG_ARGISNULL(0))
        p_parent = text_to_cstring(PG_GETARG_TEXT_P(0));

    /* p_page_size (optional, default 1000) */
    int p_page_size = 1000;
    if (PG_NARGS() > 1 && !PG_ARGISNULL(1))
        p_page_size = PG_GETARG_INT32(1);

    /* p_page_token (optional, default NULL) */
    char *p_page_token = NULL;
    if (PG_NARGS() > 2 && !PG_ARGISNULL(2))
        p_page_token = text_to_cstring(PG_GETARG_TEXT_P(2));

    /* 2. Validate p_page_size */
    if (p_page_size < 1)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("pageSize must be >= 1")));

    /* 3. Validate p_parent exists (if non-NULL and non-empty) */
    if (p_parent != NULL && strlen(p_parent) > 0)
    {
        bool parent_exists = false;

        PG_TRY();
        {
            parent_exists = iceberg_meta_namespace_exists(p_parent);
        }
        PG_CATCH();
        {
            ErrorData *edata = CopyErrorData();
            iceberg_err_rethrow_metadata(edata, "list namespaces parent check");
        }
        PG_END_TRY();

        if (!parent_exists)
            ereport(ERROR,
                    (errcode(ERRCODE_ICEBERG_NOT_FOUND),
                     errmsg("The given namespace does not exist")));
    }

    /* 4. TODO: META ListNamespaces */
    /* TODO:
     * char *result = iceberg_meta_list_namespaces(p_parent, p_page_size, p_page_token);
     * PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in, CStringGetDatum(result)));
     */

    /* 5. Stub: return empty list with null next-page-token.
     * TODO: Replace with META.ListNamespaces() result once META module is available. */
    PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
        CStringGetDatum("{\"namespaces\": [], \"next-page-token\": null}")));
}

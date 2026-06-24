/*-------------------------------------------------------------------------
 *
 * table.cpp
 *    Iceberg table SQL function implementations.
 *
 * Stub implementation: all openGauss catalog metadata-table operations
 * and Iceberg SDK calls are marked as TODO, pending the underlying
 * modules to be wired up. Currently returns a minimal response.
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "utils/builtins.h"
#include "utils/json.h"
#include "utils/jsonb.h"

#include <stdlib.h>
#include <string.h>

#include "fdw_util.h"
#include "errors.h"
#include "iceberg_catalog.h"
#include "iceberg_catalog_hook.h"
#include "json_util.h"
#include "metadata.h"
#include "table.h"


static int
temporary_last_column_id(const char *schema_json)
{
    const char *cursor = schema_json;
    int max_id = 0;

    /*
     * Temporary bridge until SDK schema parsing is wired in.  The metadata
     * layer still validates the full schema JSON before writing cache rows.
     */
    while ((cursor = strstr(cursor, "\"id\"")) != NULL) {
        const char *colon = strchr(cursor, ':');
        long value;

        if (colon == NULL)
            break;
        colon++;
        while (*colon == ' ' || *colon == '\t')
            colon++;
        value = strtol(colon, NULL, 10);
        if (value > max_id)
            max_id = (int) value;
        cursor = colon;
    }

    return max_id;
}

static Datum
load_table_result_jsonb(const char *metadata_location)
{
    StringInfo buf = makeStringInfo();

    appendStringInfoString(buf, "{\"metadata-location\":");
    escape_json(buf, metadata_location);
    appendStringInfoString(buf, ",\"metadata\":{},\"config\":{}}");

    return DirectFunctionCall1(jsonb_in, CStringGetDatum(buf->data));
}


/* ---- create_table ---- */

PG_FUNCTION_INFO_V1(iceberg_create_table);

Datum
iceberg_create_table(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_namespace       TEXT     (required)
     *   2. p_table_name      TEXT     (required)
     *   3. p_schema          JSONB    (required)
     *   4. p_location        TEXT     (optional, default NULL)
     *   5. p_partition_spec  JSONB    (optional, default NULL)
     *   6. p_write_order     JSONB    (optional, default NULL)
     *   7. p_stage_create    BOOLEAN  (optional, default FALSE)
     *   8. p_properties      JSONB    (optional, default NULL)
     *
     * Returns: JSONB (LoadTableResult)
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters from PG_FUNCTION_ARGS */

    if (PG_NARGS() < 3)
        elog(ERROR, "iceberg_create_table: expected at least 3 arguments, got %d", PG_NARGS());

    /* p_namespace (required) */
    char *p_namespace = NULL;
    if (!PG_ARGISNULL(0))
        p_namespace = text_to_cstring(PG_GETARG_TEXT_P(0));

    /* p_table_name (required) */
    char *p_table_name = NULL;
    if (!PG_ARGISNULL(1))
        p_table_name = text_to_cstring(PG_GETARG_TEXT_P(1));

    /* p_schema (required) */
    Jsonb *p_schema = NULL;
    if (!PG_ARGISNULL(2))
        p_schema = DatumGetJsonb(PG_GETARG_DATUM(2));

    /* p_location (optional, default NULL) */
    char *p_location = NULL;
    if (PG_NARGS() > 3 && !PG_ARGISNULL(3))
        p_location = text_to_cstring(PG_GETARG_TEXT_P(3));

    /* p_partition_spec (optional, default NULL) */
    Jsonb *p_partition_spec = NULL;
    if (PG_NARGS() > 4 && !PG_ARGISNULL(4))
        p_partition_spec = DatumGetJsonb(PG_GETARG_DATUM(4));

    /* p_write_order (optional, default NULL) */
    Jsonb *p_write_order = NULL;
    if (PG_NARGS() > 5 && !PG_ARGISNULL(5))
        p_write_order = DatumGetJsonb(PG_GETARG_DATUM(5));

    /* p_stage_create (optional, default FALSE) */
    bool p_stage_create = false;
    if (PG_NARGS() > 6 && !PG_ARGISNULL(6))
        p_stage_create = PG_GETARG_BOOL(6);

    /* p_properties (optional, default NULL) */
    Jsonb *p_properties = NULL;
    if (PG_NARGS() > 7 && !PG_ARGISNULL(7))
        p_properties = DatumGetJsonb(PG_GETARG_DATUM(7));

    /* 2. Validate required parameters */

    if (p_namespace == NULL || strlen(p_namespace) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_namespace is required and must not be empty")));

    if (p_table_name == NULL || strlen(p_table_name) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_table_name is required and must not be empty")));

    if (p_schema == NULL)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_schema is required and must not be NULL")));

    /* 3. TODO: Validate p_schema type == "struct", ValidateType for each field */

    /* TODO: Validate p_schema type is "struct" */
    /* TODO: For each field in p_schema.fields[], call catalog->ValidateType(field.type) */

    /* 4. Check namespace exists */

    PG_TRY();
    {
        if (!iceberg_meta_namespace_exists(p_namespace))
            ereport(ERROR,
                    (errcode(ERRCODE_ICEBERG_NOT_FOUND),
                     errmsg("namespace not found")));
    }
    PG_CATCH();
    {
        ErrorData *edata = CopyErrorData();
        iceberg_err_rethrow_metadata(edata, "create table namespace check");
    }
    PG_END_TRY();

    /* 5. Check table does not already exist */

    PG_TRY();
    {
        if (iceberg_meta_table_exists(p_namespace, p_table_name))
            ereport(ERROR,
                    (errcode(ERRCODE_ICEBERG_CONFLICT),
                     errmsg("table already exists")));
    }
    PG_CATCH();
    {
        ErrorData *edata = CopyErrorData();
        iceberg_err_rethrow_metadata(edata, "create table existence check");
    }
    PG_END_TRY();

    /* 6. SDK CreateTable */
    {
        IcebergBridgeStorage *storage = open_iceberg_storage();
        IcebergBridgeError   *error   = NULL;
        IcebergBridgeStatus   status;

        char *schema_json = iceberg_jsonb_to_cstring(p_schema);

        /* 6.1 Determine table location.
         * TODO: explicit p_location > namespace LOCATION > ICEBERG_WAREHOUSE */
        const char *warehouse = getenv("ICEBERG_WAREHOUSE");
        if (!warehouse)
            ereport(ERROR,
                    (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
                     errmsg("ICEBERG_WAREHOUSE is not set")));
        char *table_location_str = p_location
            ? p_location
            : psprintf("%s/%s/%s", warehouse, p_namespace, p_table_name);

        /* 6.2 Create table via bridge SDK (handles namespace implicitly). */
        StringInfoData creation_buf;
        initStringInfo(&creation_buf);
        appendStringInfo(&creation_buf,
            "{\"name\":\"%s\","
            "\"schema\":%s,"
            "\"location\":\"%s\","
            "\"namespace\":[\"%s\"]}",
            p_table_name, schema_json, table_location_str, p_namespace);

        IcebergBridgeTable *table = NULL;
        status = iceberg_bridge_table_create(
            storage, creation_buf.data, &table, &error);

        if (status != ICEBERG_BRIDGE_OK) {
            const char *msg = error ? pstrdup(iceberg_bridge_error_message(error)) : "create table failed";
            iceberg_bridge_error_free(error);
            iceberg_bridge_storage_release(storage);
            ereport(ERROR,
                    (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
                     errmsg("iceberg_create_table: %s", msg)));
        }

        /* storage no longer needed after table creation. */
        iceberg_bridge_storage_release(storage);

        /* 7. DDL CreateStorage */

        /* ft_relid is set by section 7.2; section 8 uses it as the real relid. */
        Oid ft_relid = InvalidOid;

        /* 7.1 Optional delta-table creation hook (plugin B).
         *
         * Another extension can register a hook by calling the exported
         * function register_iceberg_create_delta_table_hook().  If a hook
         * is registered, we invoke it here so it can create an internal
         * openGauss table with the same schema.  Errors from the hook are
         * wrapped with a clear "Create delta table failed" message.
         */
        {
            if (create_delta_table_hook != NULL) {
                PG_TRY();
                {
                    create_delta_table_hook(p_namespace, p_table_name, schema_json);
                }
                PG_CATCH();
                {
                    ErrorData *edata = CopyErrorData();
                    char *original_message = edata->message == NULL
                                                 ? pstrdup("unknown error")
                                                 : pstrdup(edata->message);
                    FreeErrorData(edata);
                    FlushErrorState();

                    iceberg_bridge_table_free(table);

                    ereport(ERROR,
                            (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
                             errmsg("Create delta table failed: %s", original_message)));
                }
                PG_END_TRY();
            }
        }

        /* 7.2 Create Foreign Table via bridge.
         *
         * Executes CREATE FOREIGN TABLE through SPI.  iceberg_fdw's
         * ProcessUtility hook intercepts the statement and handles both the
         * DDL and the catalog metadata writes.
         */
        {
            PG_TRY();
            {
                ft_relid = iceberg_fdw_create_foreign_table(
                    p_namespace, p_table_name, p_schema);
            }
            PG_CATCH();
            {
                ErrorData *edata = CopyErrorData();
                char *original_message = edata->message == NULL
                                             ? pstrdup("unknown error")
                                             : pstrdup(edata->message);
                FreeErrorData(edata);
                FlushErrorState();

                iceberg_bridge_table_free(table);

                ereport(ERROR,
                        (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
                         errmsg("Create foreign table failed: %s", original_message)));
            }
            PG_END_TRY();
        }

        /* 8. META InsertTable + Return JSON — single source of truth for
         * catalog metadata.  UUID and metadata_location come from the SDK
         * CreateTable result.  The OID comes from the foreign table created
         * in section 7.2. */
        {
            /* Extract table metadata from SDK result. */
            IcebergBridgeString *uuid_json        = NULL;
            IcebergBridgeString *meta_json        = NULL;
            IcebergBridgeString *loc_json         = NULL;

            iceberg_bridge_table_uuid(table, &uuid_json, &error);
            iceberg_bridge_table_metadata_json(table, &meta_json, &error);
            iceberg_bridge_table_location(table, &loc_json, &error);

            const char *table_uuid_str = iceberg_bridge_string_data(uuid_json);
            const char *meta_str       = iceberg_bridge_string_data(meta_json);
            const char *loc_str        = iceberg_bridge_string_data(loc_json);
            char       *md_location    = psprintf("%s/metadata/00000-%s.metadata.json",
                                                  loc_str, table_uuid_str);

            if (!OidIsValid(ft_relid))
                ereport(ERROR,
                        (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
                         errmsg("create table: foreign table creation failed, no valid relid")));

            char *partition_fields_json = p_partition_spec == NULL
                ? NULL : iceberg_jsonb_to_cstring(p_partition_spec);
            MetaRegisterTableInput meta_input;

            memset(&meta_input, 0, sizeof(meta_input));
            meta_input.table_info.relid = ft_relid;
            meta_input.table_info.namespace_name = p_namespace;
            meta_input.table_info.table_name = p_table_name;
            meta_input.table_info.table_uuid = pstrdup(table_uuid_str);
            meta_input.table_info.metadata_location = md_location;
            meta_input.table_info.previous_metadata_location = NULL;
            meta_input.table_info.table_location = table_location_str;
            meta_input.table_info.last_column_id = temporary_last_column_id(schema_json);
            meta_input.table_info.current_schema_id = 0;
            meta_input.table_info.has_current_schema_id = true;
            meta_input.table_info.has_current_snapshot_id = false;
            meta_input.table_info.default_spec_id = 0;
            meta_input.table_info.has_default_spec_id = true;
            meta_input.schema_json = schema_json;
            meta_input.partition_fields_json = partition_fields_json;
            meta_input.schema_id = 0;
            meta_input.spec_id = 0;

            PG_TRY();
            {
                iceberg_meta_register_table(p_namespace, p_table_name, &meta_input);
            }
            PG_CATCH();
            {
                ErrorData *edata = CopyErrorData();
                iceberg_bridge_string_free(uuid_json);
                iceberg_bridge_string_free(meta_json);
                iceberg_bridge_string_free(loc_json);
                iceberg_bridge_table_free(table);
                iceberg_err_rethrow_metadata(edata, "create table metadata registration");
            }
            PG_END_TRY();

            /* 9. Return LoadTableResult JSON */
            StringInfoData resp_buf;
            initStringInfo(&resp_buf);
            appendStringInfo(&resp_buf,
                "{\"metadata-location\":\"%s\",\"metadata\":%s,\"config\":{}}",
                md_location, meta_str);

            iceberg_bridge_string_free(uuid_json);
            iceberg_bridge_string_free(meta_json);
            iceberg_bridge_string_free(loc_json);
            iceberg_bridge_table_free(table);

            PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
                CStringGetDatum(resp_buf.data)));
        }
    }
}


/* ---- is_table_existed ---- */

PG_FUNCTION_INFO_V1(iceberg_is_table_existed);

Datum
iceberg_is_table_existed(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_namespace    TEXT     (required)
     *   2. p_table        TEXT     (required)
     *
     * Returns: JSONB ({"exists": true} or {"exists": false})
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters */

    if (PG_NARGS() < 2)
        elog(ERROR, "iceberg_is_table_existed: expected 2 arguments, got %d", PG_NARGS());

    char *p_namespace = NULL;
    if (!PG_ARGISNULL(0))
        p_namespace = text_to_cstring(PG_GETARG_TEXT_P(0));

    char *p_table = NULL;
    if (!PG_ARGISNULL(1))
        p_table = text_to_cstring(PG_GETARG_TEXT_P(1));

    /* 2. Validate required parameters */

    if (p_namespace == NULL || strlen(p_namespace) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_namespace is required and must not be empty")));

    if (p_table == NULL || strlen(p_table) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_table is required and must not be empty")));

    /* 3. Check table existence via META */

    bool exists = false;

    PG_TRY();
    {
        exists = iceberg_meta_table_exists(p_namespace, p_table);
    }
    PG_CATCH();
    {
        ErrorData *edata = CopyErrorData();
        iceberg_err_rethrow_metadata(edata, "table existence check");
    }
    PG_END_TRY();

    if (exists)
        PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
            CStringGetDatum("{\"exists\": true}")));
    else
        PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
            CStringGetDatum("{\"exists\": false}")));
}


/* ---- load_table ---- */

PG_FUNCTION_INFO_V1(iceberg_load_table);

Datum
iceberg_load_table(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_namespace    TEXT     (required)
     *   2. p_table        TEXT     (required)
     *
     * Returns: JSONB (LoadTableResult)
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters */

    if (PG_NARGS() < 2)
        elog(ERROR, "iceberg_load_table: expected 2 arguments, got %d", PG_NARGS());

    char *p_namespace = NULL;
    if (!PG_ARGISNULL(0))
        p_namespace = text_to_cstring(PG_GETARG_TEXT_P(0));

    char *p_table = NULL;
    if (!PG_ARGISNULL(1))
        p_table = text_to_cstring(PG_GETARG_TEXT_P(1));

    /* 2. Validate required parameters */

    if (p_namespace == NULL || strlen(p_namespace) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_namespace is required and must not be empty")));

    if (p_table == NULL || strlen(p_table) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_table is required and must not be empty")));

    /* 3. Get table metadata via META */

    MetaTableInfo *info = NULL;

    PG_TRY();
    {
        info = iceberg_meta_get_table(p_namespace, p_table);
    }
    PG_CATCH();
    {
        ErrorData *edata = CopyErrorData();
        iceberg_err_rethrow_metadata(edata, "load table metadata lookup");
    }
    PG_END_TRY();

    if (info == NULL)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_NOT_FOUND),
                 errmsg("The given table does not exist")));

    /* 4. TODO: Load table via SDK */

    /* TODO:
     * char *error_msg = NULL;
     * IcebergTable *table = catalog->LoadTable(p_namespace, p_table,
     *     info->metadata_location, &error_msg);
     * if (error_msg != NULL)
     *     ereport(ERROR,
     *             (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
     *              errmsg("%s", error_msg)));
     */

    /* 5. TODO: Construct and return LoadTableResult JSONB */

    /* TODO:
     * const char *metadata_json = table->GetMetadataJson();
     * StringInfo buf = makeStringInfo();
     * appendStringInfo(buf,
     *     "{\"metadata-location\":\"%s\",\"metadata\":%s,\"config\":{}}",
     *     info->metadata_location, metadata_json);
     * delete table;
     * PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
     *     CStringGetDatum(buf->data)));
     */

    /* 6. Return META-backed LoadTableResult shell until SDK loading is wired. */

    {
        Datum result = load_table_result_jsonb(info->metadata_location);

        iceberg_meta_free_table_info(info);
        PG_RETURN_DATUM(result);
    }
}


/* ---- rename_table ---- */

PG_FUNCTION_INFO_V1(iceberg_rename_table);

Datum
iceberg_rename_table(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_src_ns       TEXT     (required)
     *   2. p_src_table    TEXT     (required)
     *   3. p_dst_ns       TEXT     (required)
     *   4. p_dst_table    TEXT     (required)
     *
     * Returns: JSONB ({"success": true})
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters */

    if (PG_NARGS() < 4)
        elog(ERROR, "iceberg_rename_table: expected 4 arguments, got %d", PG_NARGS());

    char *p_src_ns = NULL;
    if (!PG_ARGISNULL(0))
        p_src_ns = text_to_cstring(PG_GETARG_TEXT_P(0));

    char *p_src_table = NULL;
    if (!PG_ARGISNULL(1))
        p_src_table = text_to_cstring(PG_GETARG_TEXT_P(1));

    char *p_dst_ns = NULL;
    if (!PG_ARGISNULL(2))
        p_dst_ns = text_to_cstring(PG_GETARG_TEXT_P(2));

    char *p_dst_table = NULL;
    if (!PG_ARGISNULL(3))
        p_dst_table = text_to_cstring(PG_GETARG_TEXT_P(3));

    /* 2. Validate required parameters */

    if (p_src_ns == NULL || strlen(p_src_ns) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_src_ns is required and must not be empty")));

    if (p_src_table == NULL || strlen(p_src_table) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_src_table is required and must not be empty")));

    if (p_dst_ns == NULL || strlen(p_dst_ns) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_dst_ns is required and must not be empty")));

    if (p_dst_table == NULL || strlen(p_dst_table) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_dst_table is required and must not be empty")));

    /* 3. META RenameTable */

    PG_TRY();
    {
        iceberg_meta_rename_table_record(p_src_ns, p_src_table, p_dst_ns, p_dst_table);
    }
    PG_CATCH();
    {
        ErrorData *edata = CopyErrorData();
        iceberg_err_rethrow_metadata(edata, "rename table metadata");
    }
    PG_END_TRY();

    /* 4.1 Rename Foreign Table */
    {
        PG_TRY();
        {
            iceberg_fdw_rename_foreign_table(p_src_ns, p_src_table, p_dst_ns, p_dst_table);
        }
        PG_CATCH();
        {
            ErrorData *edata = CopyErrorData();
            char *msg = edata->message ? pstrdup(edata->message) : pstrdup("unknown error");
            FreeErrorData(edata); FlushErrorState();
            ereport(ERROR, (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
                    errmsg("Rename foreign table failed: %s", msg)));
        }
        PG_END_TRY();
    }

    /* 4. NOTE: SDK RenameTable is not needed.
     *
     * The design doc reserves catalog->RenameTable() for implementations that
     * migrate S3 paths on rename. In standard Iceberg, rename only updates the
     * (namespace, table_name) → metadata_location mapping — S3 metadata.json (keyed
     * by table-uuid) and data files are untouched. Since this mapping is managed
     * entirely by META (iceberg_meta_rename_table_record), calling SDK would
     * duplicate the operation and introduce an atomicity gap between META and SDK.
     *
     * No SDK call required. META is the single source of truth for rename.
     */

    /* 5. Return success */

    PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
        CStringGetDatum("{\"success\": true}")));
}


/* ---- drop_table ---- */

PG_FUNCTION_INFO_V1(iceberg_drop_table);

Datum
iceberg_drop_table(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_namespace    TEXT     (required)
     *   2. p_table        TEXT     (required)
     *   3. p_purge        BOOLEAN  (optional, default FALSE)
     *      TRUE  — also delete underlying S3 data files (not yet supported)
     *      FALSE — remove catalog registration and metadata only
     *
     * Returns: JSONB ({"success": true})
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters */

    if (PG_NARGS() < 2)
        elog(ERROR, "iceberg_drop_table: expected at least 2 arguments, got %d", PG_NARGS());

    char *p_namespace = NULL;
    if (!PG_ARGISNULL(0))
        p_namespace = text_to_cstring(PG_GETARG_TEXT_P(0));

    char *p_table = NULL;
    if (!PG_ARGISNULL(1))
        p_table = text_to_cstring(PG_GETARG_TEXT_P(1));

    bool p_purge = false;
    if (PG_NARGS() > 2 && !PG_ARGISNULL(2))
        p_purge = PG_GETARG_BOOL(2);

    /* 2. Validate required parameters */

    if (p_namespace == NULL || strlen(p_namespace) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_namespace is required and must not be empty")));

    if (p_table == NULL || strlen(p_table) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_table is required and must not be empty")));

    /* 3. TODO: Check p_purge not yet supported */

    if (p_purge)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_NOT_SUPPORTED),
                 errmsg("p_purge is not yet supported")));

    /* 4. DDL DropStorage */

    /* 4.1 Optional delta-table drop hook (plugin B).
     *
     * Another extension can register a hook by calling the exported
     * function register_iceberg_drop_delta_table_hook().  If a hook is
     * registered, we invoke it here so it can drop the internal openGauss
     * table that was created alongside this Iceberg table.  Errors from the
     * hook are wrapped with a clear "Drop delta table failed" message.
     */
    {
        if (drop_delta_table_hook != NULL) {
            PG_TRY();
            {
                drop_delta_table_hook(p_namespace, p_table, p_purge);
            }
            PG_CATCH();
            {
                ErrorData *edata = CopyErrorData();
                char *original_message = edata->message == NULL
                                             ? pstrdup("unknown error")
                                             : pstrdup(edata->message);
                FreeErrorData(edata);
                FlushErrorState();

                ereport(ERROR,
                        (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
                         errmsg("Drop delta table failed: %s", original_message)));
            }
            PG_END_TRY();
        }
    }

    /* 4.2 Drop Foreign Table */
    {
        PG_TRY();
        {
            iceberg_fdw_drop_foreign_table(p_namespace, p_table);
        }
        PG_CATCH();
        {
            ErrorData *edata = CopyErrorData();
            char *msg = edata->message ? pstrdup(edata->message) : pstrdup("unknown error");
            FreeErrorData(edata); FlushErrorState();
            ereport(ERROR, (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
                    errmsg("Drop foreign table failed: %s", msg)));
        }
        PG_END_TRY();
    }

    /* 5. META DeleteTable (cascade handles related rows) */

    PG_TRY();
    {
        iceberg_meta_drop_table_record(p_namespace, p_table);
    }
    PG_CATCH();
    {
        ErrorData *edata = CopyErrorData();
        iceberg_err_rethrow_metadata(edata, "drop table metadata delete");
    }
    PG_END_TRY();

    /* 6. TODO: SDK DropTable is reserved (best-effort metadata cleanup).
     *
     * Data file deletion (p_purge=TRUE) is a separate concern, not part of
     * this SDK call. The SDK method itself is unaffected by the purge flag.
     */

    /* TODO:
     * catalog->DropTable(p_namespace, p_table);
     */

    /* 7. Return success */

    PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
        CStringGetDatum("{\"success\": true}")));
}


/* ---- commit_table ---- */

PG_FUNCTION_INFO_V1(iceberg_commit_table);

Datum
iceberg_commit_table(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_namespace    TEXT   (required)
     *   2. p_table        TEXT   (required)
     *   3. p_requirements JSONB  (required)
     *   4. p_updates      JSONB  (required)
     *
     * Returns: JSONB
     *   {"metadata-location": "<path>", "metadata": {...}}
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters from PG_FUNCTION_ARGS */

    if (PG_NARGS() < 4)
        elog(ERROR, "iceberg_commit_table: expected at least 4 arguments, got %d", PG_NARGS());

    /* p_namespace (required) */
    char *p_namespace = NULL;
    if (!PG_ARGISNULL(0))
        p_namespace = text_to_cstring(PG_GETARG_TEXT_P(0));

    /* p_table (required) */
    char *p_table = NULL;
    if (!PG_ARGISNULL(1))
        p_table = text_to_cstring(PG_GETARG_TEXT_P(1));

    /* p_requirements (required) */
    Jsonb *p_requirements = NULL;
    if (!PG_ARGISNULL(2))
        p_requirements = DatumGetJsonb(PG_GETARG_DATUM(2));

    /* p_updates (required) */
    Jsonb *p_updates = NULL;
    if (!PG_ARGISNULL(3))
        p_updates = DatumGetJsonb(PG_GETARG_DATUM(3));

    /* 2. Validate required parameters */

    if (p_namespace == NULL || strlen(p_namespace) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_namespace is required and must not be empty")));

    if (p_table == NULL || strlen(p_table) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_table is required and must not be empty")));

    if (p_requirements == NULL)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_requirements is required and must not be NULL")));

    if (p_updates == NULL)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_updates is required and must not be NULL")));

    /* 3. TODO: Validate p_updates elements have action = "add-snapshot" */

    /* TODO: Validate each element in p_updates has "action" = "add-snapshot" */

    /* 4. TODO: META GetTableForUpdate */

    /* TODO:
     * info = META.GetTableForUpdate(p_namespace, p_table);
     * if (info == NULL)
     *     ereport(ERROR, (errcode(ERRCODE_ICEBERG_NOT_FOUND),
     *                     errmsg("table not found")));
     */

    /* 5. TODO: SDK LoadTable */

    /* TODO:
     * error_msg = NULL;
     * table = catalog->LoadTable(p_namespace, p_table, info->metadata_location, &error_msg);
     * if (error_msg != NULL)
     *     ereport(ERROR, (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
     *                     errmsg("{\"type\":\"ServiceUnavailable\",\"message\":\"%s\",\"stack\":[]}", error_msg)));
     */

    /* 6. TODO: SDK CommitTable (apply requirements + updates + write S3) */

    /* TODO:
     * newMdlLocation = table->CommitTable(jsonb_to_cstring(p_requirements),
     *                                      jsonb_to_cstring(p_updates), &error_msg);
     * if (error_msg != NULL)
     *     ereport(ERROR, (errcode(ERRCODE_ICEBERG_CONFLICT),
     *                     errmsg("{\"type\":\"CommitFailedException\",\"message\":\"%s\",\"stack\":[]}", error_msg)));
     */

    /* 7. META commit_table (update table pointer + insert snapshot row) */

    /*
     * TODO: Replace these temporary values with the SDK CommitTable result
     * once the SDK modules are wired up.
     */
    {
        MetaTableInfo *info = NULL;
        static int64_t next_snapshot_id = 1;

        PG_TRY();
        {
            info = iceberg_meta_lock_table(p_namespace, p_table);
        }
        PG_CATCH();
        {
            ErrorData *edata = CopyErrorData();
            iceberg_err_rethrow_metadata(edata, "commit table metadata lock");
        }
        PG_END_TRY();

        MetaCommitTableInput meta_input;

        memset(&meta_input, 0, sizeof(meta_input));
        meta_input.namespace_name = p_namespace;
        meta_input.table_name = p_table;
        meta_input.table_uuid = info->table_uuid;
        meta_input.old_metadata_location = info->metadata_location;
        meta_input.new_metadata_location = psprintf("file:///tmp/iceberg_catalog/%s/%s/metadata/v2.metadata.json",
                                                     p_namespace, p_table);
        meta_input.new_snapshot_id = next_snapshot_id++;
        meta_input.snapshot_schema_id = info->current_schema_id;
        meta_input.has_snapshot_schema_id = info->has_current_schema_id;
        meta_input.snapshot_timestamp_ms = 0;
        meta_input.manifest_list = NULL;
        meta_input.total_records = 0;
        meta_input.has_total_records = false;

        PG_TRY();
        {
            iceberg_meta_commit_table(&meta_input);
        }
        PG_CATCH();
        {
            iceberg_meta_free_table_info(info);
            ErrorData *edata = CopyErrorData();
            iceberg_err_rethrow_metadata(edata, "commit table metadata commit");
        }
        PG_END_TRY();

        iceberg_meta_free_table_info(info);

        /* 8. Return response with the new metadata location */

        PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
            CStringGetDatum(psprintf("{\"metadata-location\": \"%s\", \"metadata\": {}}",
                                     meta_input.new_metadata_location))));
    }
}


/* ---- add_column ---- */

PG_FUNCTION_INFO_V1(iceberg_add_column);

Datum
iceberg_add_column(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_namespace   TEXT    (required)
     *   2. p_table       TEXT    (required)
     *   3. p_column_name TEXT    (required)
     *   4. p_column_type TEXT    (required)
     *   5. p_column_doc  TEXT    (optional, default NULL)
     *
     * Returns: JSONB
     *   {"metadata-location": "<path>", "metadata": {...}}
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters from PG_FUNCTION_ARGS */

    if (PG_NARGS() < 4)
        elog(ERROR, "iceberg_add_column: expected at least 4 arguments, got %d", PG_NARGS());

    /* p_namespace (required) */
    char *p_namespace = NULL;
    if (!PG_ARGISNULL(0))
        p_namespace = text_to_cstring(PG_GETARG_TEXT_P(0));

    /* p_table (required) */
    char *p_table = NULL;
    if (!PG_ARGISNULL(1))
        p_table = text_to_cstring(PG_GETARG_TEXT_P(1));

    /* p_column_name (required) */
    char *p_column_name = NULL;
    if (!PG_ARGISNULL(2))
        p_column_name = text_to_cstring(PG_GETARG_TEXT_P(2));

    /* p_column_type (required) */
    char *p_column_type = NULL;
    if (!PG_ARGISNULL(3))
        p_column_type = text_to_cstring(PG_GETARG_TEXT_P(3));

    /* p_column_doc (optional, default NULL) */
    char *p_column_doc = NULL;
    if (PG_NARGS() > 4 && !PG_ARGISNULL(4))
        p_column_doc = text_to_cstring(PG_GETARG_TEXT_P(4));

    /* 2. Validate required parameters */

    if (p_namespace == NULL || strlen(p_namespace) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_namespace is required and must not be empty")));

    if (p_table == NULL || strlen(p_table) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_table is required and must not be empty")));

    if (p_column_name == NULL || strlen(p_column_name) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_column_name is required and must not be empty")));

    if (p_column_type == NULL || strlen(p_column_type) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_column_type is required and must not be empty")));

    /* 3. TODO: Validate p_column_type via SDK */

    /* TODO:
     * if (!catalog->ValidateType(p_column_type, &err))
     *     ereport(ERROR, (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
     *                     errmsg("invalid column type: %s", err)));
     */

    /* 4. TODO: SDK LoadTable */

    /* TODO:
     * error_msg = NULL;
     * table = catalog->LoadTable(p_namespace, p_table, info->metadata_location, &error_msg);
     * if (error_msg != NULL)
     *     ereport(ERROR, (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
     *                     errmsg("{\"type\":\"ServiceUnavailable\",\"message\":\"%s\",\"stack\":[]}", error_msg)));
     */

    /* 5. TODO: Check column name conflict against current schema */

    /* TODO:
     * currentSchema = table->GetCurrentSchema();
     * if currentSchema has field named p_column_name → ereport(P0001, "column already exists")
     */

    /* 6. TODO: SDK AddColumn → new schema + new field ID */

    /* TODO:
     * newFieldId = 0;
     * newSchema = table->AddColumn(p_column_name, p_column_type, p_column_doc, &newFieldId);
     * newSchemaId = table->GetCurrentSchemaId() + 1;
     */

    /* 7. META commit_schema_change (update table pointer + insert schema row) */

    /*
     * TODO: Replace these temporary values with the SDK AddColumn/CommitTable
     * result once the SDK modules are wired up.
     */
    {
        MetaTableInfo *info = NULL;

        PG_TRY();
        {
            info = iceberg_meta_lock_table(p_namespace, p_table);
        }
        PG_CATCH();
        {
            ErrorData *edata = CopyErrorData();
            iceberg_err_rethrow_metadata(edata, "add column metadata lock");
        }
        PG_END_TRY();

        int new_last_column_id = info->last_column_id + 1;
        int new_schema_id = info->current_schema_id + 1;

        /*
         * TODO: Replace this temporary schema JSON with the real schema from
         * the SDK AddColumn result once wired up.
         */
        char *new_schema_json;
        if (p_column_doc != NULL)
            new_schema_json = psprintf(
                "{\"type\":\"struct\",\"fields\":["
                "{\"id\":%d,\"name\":\"%s\",\"required\":false,\"type\":\"%s\","
                "\"doc\":\"%s\"}]}",
                new_last_column_id, p_column_name, p_column_type, p_column_doc);
        else
            new_schema_json = psprintf(
                "{\"type\":\"struct\",\"fields\":["
                "{\"id\":%d,\"name\":\"%s\",\"required\":false,\"type\":\"%s\"}]}",
                new_last_column_id, p_column_name, p_column_type);

        MetaCommitSchemaChangeInput meta_input;

        memset(&meta_input, 0, sizeof(meta_input));
        meta_input.namespace_name = p_namespace;
        meta_input.table_name = p_table;
        meta_input.table_uuid = info->table_uuid;
        meta_input.old_metadata_location = info->metadata_location;
        meta_input.new_metadata_location = psprintf("file:///tmp/iceberg_catalog/%s/%s/metadata/v2.metadata.json",
                                                     p_namespace, p_table);
        meta_input.new_schema_id = new_schema_id;
        meta_input.schema_json = new_schema_json;
        meta_input.new_last_column_id = new_last_column_id;

        PG_TRY();
        {
            iceberg_meta_commit_schema_change(&meta_input);
        }
        PG_CATCH();
        {
            iceberg_meta_free_table_info(info);
            ErrorData *edata = CopyErrorData();
            iceberg_err_rethrow_metadata(edata, "add column metadata commit");
        }
        PG_END_TRY();

        /* 7.1 Add column to foreign table */
        {
            PG_TRY();
            {
                iceberg_fdw_add_column(p_namespace, p_table, p_column_name, p_column_type);
            }
            PG_CATCH();
            {
                ErrorData *edata = CopyErrorData();
                char *msg = edata->message ? pstrdup(edata->message) : pstrdup("unknown error");
                FreeErrorData(edata); FlushErrorState();
                ereport(ERROR, (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
                        errmsg("Add column foreign table failed: %s", msg)));
            }
            PG_END_TRY();
        }

        iceberg_meta_free_table_info(info);

        /* 8. Return response with the new metadata location */

        PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
            CStringGetDatum(psprintf("{\"metadata-location\": \"%s\", \"metadata\": {}}",
                                     meta_input.new_metadata_location))));
    }
}

/* ---- list_tables ---- */

PG_FUNCTION_INFO_V1(iceberg_list_tables);

Datum
iceberg_list_tables(PG_FUNCTION_ARGS)
{
    /*-------------------------------------------------------------------------
     * Parameters:
     *   1. p_namespace    TEXT     (required)
     *   2. p_page_size    INTEGER  (optional, default 1000)
     *   3. p_page_token   TEXT     (optional, default NULL)
     *
     * Returns: JSONB (ListTablesResponse)
     *-------------------------------------------------------------------------
     */

    /* 1. Extract parameters */

    if (PG_NARGS() < 1)
        elog(ERROR, "iceberg_list_tables: expected at least 1 argument, got %d", PG_NARGS());

    char *p_namespace = NULL;
    if (!PG_ARGISNULL(0))
        p_namespace = text_to_cstring(PG_GETARG_TEXT_P(0));

    int p_page_size = 1000;
    if (PG_NARGS() > 1 && !PG_ARGISNULL(1))
        p_page_size = PG_GETARG_INT32(1);

    char *p_page_token = NULL;
    if (PG_NARGS() > 2 && !PG_ARGISNULL(2))
        p_page_token = text_to_cstring(PG_GETARG_TEXT_P(2));

    /* 2. Validate parameters */

    if (p_namespace == NULL || strlen(p_namespace) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_namespace is required and must not be empty")));

    if (p_page_size < 1)
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("p_page_size must be >= 1")));

    /* 3. List tables via META (namespace existence check is internal) */

    {
        char *json_result = NULL;

        PG_TRY();
        {
            json_result = iceberg_meta_list_tables(p_namespace, p_page_size, p_page_token);
        }
        PG_CATCH();
        {
            ErrorData *edata = CopyErrorData();
            iceberg_err_rethrow_metadata(edata, "list tables");
        }
        PG_END_TRY();

        PG_RETURN_DATUM(DirectFunctionCall1(jsonb_in,
            CStringGetDatum(json_result)));
        pfree(json_result);
    }
}

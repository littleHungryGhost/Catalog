/*-------------------------------------------------------------------------
 *
 * iceberg_catalog.cpp
 *    Minimal shared library entrypoint for the iceberg_catalog extension.
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"

#include "iceberg_catalog.h"
#include "iceberg_catalog_hook.h"
#include "namespace.h"

#include <stdio.h>

PG_MODULE_MAGIC;

/* Internal storage for delta-table hooks registered by another extension. */
extern "C" {
iceberg_create_delta_table_hook_type create_delta_table_hook = NULL;
iceberg_drop_delta_table_hook_type   drop_delta_table_hook   = NULL;
}

/*
 * _PG_init
 *
 * Shared library entry point.  Publish the addresses of our hook pointers
 * via the rendezvous variable mechanism so that other extensions (e.g.
 * iceberg_delta) can write their callbacks directly.
 */
extern "C" void
_PG_init(void)
{
    /* Publish the addresses of our hook pointers so that another extension
     * loaded as a separate pg_plugin instance can write callbacks directly
     * into this backend's current catalog instance. */
    void **create_slot = find_rendezvous_variable(ICEBERG_CREATE_DELTA_TABLE_HOOK_SLOT);
    *create_slot = (void *) &create_delta_table_hook;

    void **drop_slot = find_rendezvous_variable(ICEBERG_DROP_DELTA_TABLE_HOOK_SLOT);
    *drop_slot = (void *) &drop_delta_table_hook;

    /* If the peer extension loaded first, it published its callbacks in the
     * CB rendezvous slots; adopt them now. */
    void **create_cb = find_rendezvous_variable(ICEBERG_CREATE_DELTA_TABLE_HOOK_CB);
    if (create_cb != NULL && *create_cb != NULL)
        create_delta_table_hook = (iceberg_create_delta_table_hook_type) *create_cb;

    void **drop_cb = find_rendezvous_variable(ICEBERG_DROP_DELTA_TABLE_HOOK_CB);
    if (drop_cb != NULL && *drop_cb != NULL)
        drop_delta_table_hook = (iceberg_drop_delta_table_hook_type) *drop_cb;
}

#define REQUIRE_ENV(name) \
    do { \
        if (!getenv(name)) \
            ereport(ERROR, \
                    (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR), \
                     errmsg("environment variable %s is not set", name))); \
    } while (0)

IcebergBridgeStorage *
open_iceberg_storage(void)
{
    REQUIRE_ENV("ICEBERG_WAREHOUSE");

    const char *warehouse = getenv("ICEBERG_WAREHOUSE");

    char *props = NULL;

    if (strncmp(warehouse, "file://", 7) == 0)
    {
        props = psprintf(
            "{\"warehouse\":\"%s\","
            "\"storage_scheme\":\"fs\"}",
            warehouse);
    }
    else if (strncmp(warehouse, "s3://", 5) == 0)
    {
        REQUIRE_ENV("ICEBERG_S3_ENDPOINT");
        REQUIRE_ENV("ICEBERG_S3_ACCESS_KEY");
        REQUIRE_ENV("ICEBERG_S3_SECRET_KEY");
        REQUIRE_ENV("ICEBERG_S3_REGION");

        const char *endpoint   = getenv("ICEBERG_S3_ENDPOINT");
        const char *access_key = getenv("ICEBERG_S3_ACCESS_KEY");
        const char *secret_key = getenv("ICEBERG_S3_SECRET_KEY");
        const char *region     = getenv("ICEBERG_S3_REGION");

        props = psprintf(
            "{\"warehouse\":\"%s\","
            "\"s3.endpoint\":\"%s\","
            "\"s3.access-key-id\":\"%s\","
            "\"s3.secret-access-key\":\"%s\","
            "\"s3.region\":\"%s\","
            "\"s3.path-style-access\":\"true\"}",
            warehouse, endpoint, access_key, secret_key, region);
    }
    else
    {
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INVALID_PARAM),
                 errmsg("ICEBERG_WAREHOUSE must start with file:// or s3://")));
    }

    IcebergBridgeStorage *storage = NULL;
    IcebergBridgeError   *error   = NULL;
    IcebergBridgeStatus   status;

    status = iceberg_bridge_storage_open(props, &storage, &error);

    pfree(props);

    if (status != ICEBERG_BRIDGE_OK) {
        const char *msg = error ? pstrdup(iceberg_bridge_error_message(error)) : "storage open failed";
        iceberg_bridge_error_free(error);
        ereport(ERROR,
                (errcode(ERRCODE_ICEBERG_INTERNAL_ERROR),
                 errmsg("open_iceberg_storage: %s", msg)));
    }

    return storage;
}

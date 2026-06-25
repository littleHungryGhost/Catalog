/*-------------------------------------------------------------------------
 *
 * iceberg_catalog_hook.h
 *    Public hook interface for the iceberg_catalog extension.
 *
 * Other extensions can register callbacks by writing through the
 * rendezvous variable slots declared below.  iceberg_catalog publishes
 * the addresses of its hook pointers in _PG_init(); delta (or any other
 * extension) reads them back via find_rendezvous_variable() and writes
 * its callbacks directly.
 *
 * This avoids the dlopen/dlsym approach which fails under openGauss
 * single-node because the catalog .so is copied to a unique path before
 * dlopen, so static symbols are not shared between the two library
 * instances.
 *-------------------------------------------------------------------------
 */

#ifndef ICEBERG_CATALOG_HOOK_H
#define ICEBERG_CATALOG_HOOK_H

#ifdef __cplusplus
extern "C" {
#endif

/* Rendezvous variable slot names used to publish hook pointer addresses. */
#define ICEBERG_CREATE_DELTA_TABLE_HOOK_SLOT "iceberg_create_delta_table_hook_slot"
#define ICEBERG_DROP_DELTA_TABLE_HOOK_SLOT   "iceberg_drop_delta_table_hook_slot"

/* Rendezvous variable slot names used by another extension to publish its
 * callback addresses.  iceberg_catalog reads these back in _PG_init() so that
 * repeated library reloads do not lose the registered callback. */
#define ICEBERG_CREATE_DELTA_TABLE_HOOK_CB   "iceberg_create_delta_table_hook_cb"
#define ICEBERG_DROP_DELTA_TABLE_HOOK_CB     "iceberg_drop_delta_table_hook_cb"

/*
 * Hook called during iceberg_catalog.create_table() after validation and
 * existence checks, inside the DDL CreateStorage step.  Another extension
 * can use this hook to create an internal openGauss table with the same
 * schema.
 *
 * Parameters:
 *   namespace_name - target namespace
 *   table_name     - target table name
 *   schema_json    - Iceberg schema as a JSON string
 *
 * The hook has no return value.  On error it should use ereport(ERROR, ...);
 * the error will be propagated by iceberg_catalog.
 */
typedef void (*iceberg_create_delta_table_hook_type)(
    const char *namespace_name,
    const char *table_name,
    const char *schema_json
);

/*
 * Hook called during iceberg_catalog.drop_table() after validation and the
 * purge check, before the META DeleteTable step.  Another extension can use
 * this hook to drop the internal openGauss table that was created alongside
 * the Iceberg table.
 *
 * Parameters:
 *   namespace_name - target namespace
 *   table_name     - target table name
 *   purge          - whether the caller requested purge
 *
 * The hook has no return value.  On error it should use ereport(ERROR, ...);
 * the error will be propagated by iceberg_catalog.
 */
typedef void (*iceberg_drop_delta_table_hook_type)(
    const char *namespace_name,
    const char *table_name,
    bool        purge
);

/*
 * Internal callback storage, defined in iceberg_catalog.cpp and referenced
 * from table.cpp.  External code should not touch these directly; use the
 * rendezvous variable mechanism instead.
 */
extern iceberg_create_delta_table_hook_type create_delta_table_hook;
extern iceberg_drop_delta_table_hook_type   drop_delta_table_hook;

#ifdef __cplusplus
}
#endif

#endif /* ICEBERG_CATALOG_HOOK_H */

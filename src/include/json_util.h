/*-------------------------------------------------------------------------
 *
 * json_util.h
 *    Small helpers for converting between openGauss Jsonb values and
 *    C strings, and for inspecting a Jsonb value's JSON type.
 *
 * The openGauss Jsonb API exposes these operations as SQL-facing function
 * pointers (jsonb_out, jsonb_typeof, ...) which require DirectFunctionCall*
 * boilerplate at every call site.  These wrappers collapse that boilerplate
 * into a single call so callers stay readable.
 *
 *-------------------------------------------------------------------------
 */

#ifndef ICEBERG_CATALOG_JSON_UTIL_H
#define ICEBERG_CATALOG_JSON_UTIL_H

#include "postgres.h"
#include "utils/jsonb.h"

/*
 * Serialize a Jsonb value to a palloc'd C string (JSON text form).
 * The result belongs to the caller and must be pfree'd or released with
 * its memory context.  Returns NULL if value is NULL.
 */
extern char *iceberg_jsonb_to_cstring(Jsonb *value);

/*
 * Return the JSON type name of a Jsonb value as a palloc'd C string
 * ("object", "array", "string", "number", "boolean", "null").
 * Returns NULL if value is NULL.
 */
extern char *iceberg_jsonb_typeof(Jsonb *value);

/*
 * Convenience wrapper: true if the Jsonb value's JSON type matches the
 * given type name (compared with strcmp).  Returns false for NULL input.
 */
extern bool iceberg_jsonb_is_type(Jsonb *value, const char *type_name);

#endif /* ICEBERG_CATALOG_JSON_UTIL_H */

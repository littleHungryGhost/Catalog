/*-------------------------------------------------------------------------
 *
 * json_util.cpp
 *    Jsonb <-> C string conversion and JSON type inspection helpers.
 *
 * See json_util.h for the rationale.
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "utils/builtins.h"
#include "utils/jsonb.h"

#include "json_util.h"

char *
iceberg_jsonb_to_cstring(Jsonb *value)
{
    if (value == NULL)
        return NULL;

    return DatumGetCString(DirectFunctionCall1(jsonb_out,
                                                PointerGetDatum(value)));
}

char *
iceberg_jsonb_typeof(Jsonb *value)
{
    Datum type_datum;

    if (value == NULL)
        return NULL;

    type_datum = DirectFunctionCall1(jsonb_typeof, JsonbGetDatum(value));
    return text_to_cstring(DatumGetTextP(type_datum));
}

bool
iceberg_jsonb_is_type(Jsonb *value, const char *type_name)
{
    char   *type_str;
    bool    result;

    type_str = iceberg_jsonb_typeof(value);
    if (type_str == NULL)
        return false;

    result = strcmp(type_str, type_name) == 0;
    pfree(type_str);
    return result;
}

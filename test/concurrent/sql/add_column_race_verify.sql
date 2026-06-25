-- Both columns exist in the catalog schema
SELECT count(*) = 1 AS col_a_in_meta
FROM iceberg_catalog.table_schemas s
JOIN iceberg_catalog.tables_internal t ON s.table_uuid = t.table_uuid
WHERE t.namespace = 'addcol_ns' AND t.table_name = 'addcol_tbl' AND s.field_name = 'col_a';

SELECT count(*) = 1 AS col_b_in_meta
FROM iceberg_catalog.table_schemas s
JOIN iceberg_catalog.tables_internal t ON s.table_uuid = t.table_uuid
WHERE t.namespace = 'addcol_ns' AND t.table_name = 'addcol_tbl' AND s.field_name = 'col_b';

-- Both columns exist in the FDW foreign table
SELECT count(*) = 1 AS col_a_in_pg
FROM pg_attribute a
JOIN pg_class c ON a.attrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'addcol_ns' AND c.relname = 'addcol_tbl'
  AND a.attname = 'col_a' AND a.attnum > 0 AND NOT a.attisdropped;

SELECT count(*) = 1 AS col_b_in_pg
FROM pg_attribute a
JOIN pg_class c ON a.attrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'addcol_ns' AND c.relname = 'addcol_tbl'
  AND a.attname = 'col_b' AND a.attnum > 0 AND NOT a.attisdropped;

-- Schema evolved twice
SELECT current_schema_id = 2 AS schema_id_ok
FROM iceberg_catalog.tables_internal
WHERE namespace = 'addcol_ns' AND table_name = 'addcol_tbl';

-- Highest assigned column id is 3 (id=1, col_a=2, col_b=3)
SELECT last_column_id = 3 AS last_col_ok
FROM iceberg_catalog.tables_internal
WHERE namespace = 'addcol_ns' AND table_name = 'addcol_tbl';

-- No duplicate table metadata
SELECT count(*) = 1 AS table_count_ok
FROM iceberg_catalog.tables_internal
WHERE namespace = 'addcol_ns' AND table_name = 'addcol_tbl';

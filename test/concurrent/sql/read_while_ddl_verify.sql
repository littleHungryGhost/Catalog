-- The DDL column ended up in the catalog schema
SELECT count(*) = 1 AS new_col_in_meta
FROM iceberg_catalog.table_schemas s
JOIN iceberg_catalog.tables_internal t ON s.table_uuid = t.table_uuid
WHERE t.namespace = 'read_ns' AND t.table_name = 'read_tbl' AND s.field_name = 'new_col';

-- The DDL column ended up in the foreign table
SELECT count(*) = 1 AS new_col_in_pg
FROM pg_attribute a
JOIN pg_class c ON a.attrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'read_ns' AND c.relname = 'read_tbl'
  AND a.attname = 'new_col' AND a.attnum > 0 AND NOT a.attisdropped;

-- No duplicate table metadata
SELECT count(*) = 1 AS table_count_ok
FROM iceberg_catalog.tables_internal
WHERE namespace = 'read_ns' AND table_name = 'read_tbl';

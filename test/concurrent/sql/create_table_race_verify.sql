-- Exactly one metadata row for the table
SELECT count(*) = 1 AS table_count_ok
FROM iceberg_catalog.tables_internal
WHERE namespace = 'race_ns' AND table_name = 'race_tbl';

-- Exactly one foreign table in pg_class
SELECT count(*) = 1 AS fdw_count_ok
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'race_ns'
  AND c.relname = 'race_tbl'
  AND c.relkind = 'f';

-- Exactly one schema row
SELECT count(*) = 1 AS schema_count_ok
FROM iceberg_catalog.table_schemas s
JOIN iceberg_catalog.tables_internal t ON s.table_uuid = t.table_uuid
WHERE t.namespace = 'race_ns' AND t.table_name = 'race_tbl';

-- Exactly one partition spec row
SELECT count(*) = 1 AS spec_count_ok
FROM iceberg_catalog.partition_specs p
JOIN iceberg_catalog.tables_internal t ON p.table_uuid = t.table_uuid
WHERE t.namespace = 'race_ns' AND t.table_name = 'race_tbl';

-- Namespace still exists
SELECT count(*) = 1 AS ns_count_ok
FROM iceberg_catalog.namespaces
WHERE namespace = 'race_ns';

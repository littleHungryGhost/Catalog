SELECT count(*) = 1 AS ns_count_ok
FROM iceberg_catalog.namespaces
WHERE namespace = 'race_ns';

SELECT count(*) = 1 AS schema_count_ok
FROM pg_namespace
WHERE nspname = 'race_ns';

-- No duplicate namespaces in metadata
SELECT NOT EXISTS (
    SELECT 1 FROM iceberg_catalog.namespaces
    WHERE namespace = 'dropcreate_ns'
    GROUP BY namespace HAVING count(*) > 1
) AS no_dup_ns;

-- No duplicate tables in metadata
SELECT NOT EXISTS (
    SELECT 1 FROM iceberg_catalog.tables_internal
    WHERE namespace = 'dropcreate_ns'
    GROUP BY namespace, table_name HAVING count(*) > 1
) AS no_dup_tbl;

-- No orphaned foreign tables (every pg_class 'f' table has a metadata row)
SELECT NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relkind = 'f'
      AND n.nspname = 'dropcreate_ns'
      AND NOT EXISTS (
          SELECT 1 FROM iceberg_catalog.tables_internal t
          WHERE t.namespace = n.nspname AND t.table_name = c.relname
      )
) AS no_orphan_fdw;

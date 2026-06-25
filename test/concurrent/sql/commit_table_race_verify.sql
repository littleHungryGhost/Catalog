-- At least one snapshot was committed
SELECT count(*) >= 1 AS has_snapshots
FROM iceberg_catalog.snapshots s
JOIN iceberg_catalog.tables_internal t ON s.table_uuid = t.table_uuid
WHERE t.namespace = 'commit_ns' AND t.table_name = 'commit_tbl';

-- No duplicate snapshot ids for this table
SELECT NOT EXISTS (
    SELECT 1 FROM iceberg_catalog.snapshots s
    JOIN iceberg_catalog.tables_internal t ON s.table_uuid = t.table_uuid
    WHERE t.namespace = 'commit_ns' AND t.table_name = 'commit_tbl'
    GROUP BY s.snapshot_id HAVING count(*) > 1
) AS no_dup_snapshots;

-- Metadata location is still valid
SELECT metadata_location IS NOT NULL AND metadata_location <> '' AS metadata_location_ok
FROM iceberg_catalog.tables_internal
WHERE namespace = 'commit_ns' AND table_name = 'commit_tbl';

-- No duplicate table metadata
SELECT count(*) = 1 AS table_count_ok
FROM iceberg_catalog.tables_internal
WHERE namespace = 'commit_ns' AND table_name = 'commit_tbl';

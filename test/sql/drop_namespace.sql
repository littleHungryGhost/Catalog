-- ============================================================================
-- iceberg_catalog.drop_namespace tests
-- ============================================================================

BEGIN;

-- 1. Returns JSONB object
SELECT iceberg_catalog.create_namespace('some_ns');
SELECT jsonb_typeof(iceberg_catalog.drop_namespace('some_ns')) AS result_type;

-- 2. Response contains success=true
SELECT iceberg_catalog.create_namespace('ns_success_key');
SELECT iceberg_catalog.drop_namespace('ns_success_key') ? 'success' AS has_success;

SELECT iceberg_catalog.create_namespace('ns_success_val');
SELECT (iceberg_catalog.drop_namespace('ns_success_val') ->> 'success')::BOOLEAN AS success_value;

-- 3. Drops metadata row
SELECT iceberg_catalog.create_namespace('temp_ns', '{"owner": "test"}'::JSONB);
SELECT iceberg_catalog.drop_namespace('temp_ns');
SELECT count(*) = 0 AS is_deleted
FROM iceberg_catalog.namespaces
WHERE catalog_name = current_database()
  AND namespace = 'temp_ns';

-- 4. Empty namespace argument errors
SAVEPOINT sp4;
SELECT iceberg_catalog.drop_namespace('');
ROLLBACK TO SAVEPOINT sp4;

-- 5. NULL namespace argument errors
SAVEPOINT sp5;
SELECT iceberg_catalog.drop_namespace(NULL::TEXT);
ROLLBACK TO SAVEPOINT sp5;

-- 6. Missing namespace errors
SAVEPOINT sp6;
SELECT iceberg_catalog.drop_namespace('non_existent_namespace');
ROLLBACK TO SAVEPOINT sp6;

-- 7. Drops the corresponding openGauss schema
SAVEPOINT sp7;
SELECT iceberg_catalog.create_namespace('ns_schema_check');

SELECT count(*) = 1 AS schema_exists_before
FROM pg_namespace
WHERE nspname = 'ns_schema_check';

SELECT iceberg_catalog.drop_namespace('ns_schema_check');

SELECT count(*) = 0 AS schema_gone_after
FROM pg_namespace
WHERE nspname = 'ns_schema_check';
ROLLBACK TO SAVEPOINT sp7;

-- 8. Namespace with internal tables errors
SAVEPOINT sp8;
SELECT iceberg_catalog.create_namespace('ns_with_tables');
INSERT INTO iceberg_catalog.tables_internal(
    relid, namespace, table_name, table_uuid,
    metadata_location, previous_metadata_location, table_location,
    last_column_id, current_schema_id, current_snapshot_id, default_spec_id
) VALUES (
    'pg_class'::regclass, 'ns_with_tables', 'some_table',
    '11111111-1111-1111-1111-111111111111'::uuid,
    'file:///tmp/metadata.json', NULL, 'file:///tmp/table',
    1, 0, NULL, 0
);
SELECT iceberg_catalog.drop_namespace('ns_with_tables');
ROLLBACK TO SAVEPOINT sp8;

ROLLBACK;

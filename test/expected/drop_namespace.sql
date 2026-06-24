-- ============================================================================
-- iceberg_catalog.drop_namespace tests
-- ============================================================================
BEGIN;
BEGIN
-- 1. Returns JSONB object
SELECT iceberg_catalog.create_namespace('some_ns');
               create_namespace               
----------------------------------------------
 {"namespace": ["some_ns"], "properties": {}}
(1 row)
SELECT jsonb_typeof(iceberg_catalog.drop_namespace('some_ns')) AS result_type;
 result_type 
-------------
 object
(1 row)
-- 2. Response contains success=true
SELECT iceberg_catalog.create_namespace('ns_success_key');
                  create_namespace                   
-----------------------------------------------------
 {"namespace": ["ns_success_key"], "properties": {}}
(1 row)
SELECT iceberg_catalog.drop_namespace('ns_success_key') ? 'success' AS has_success;
 has_success 
-------------
 t
(1 row)
SELECT iceberg_catalog.create_namespace('ns_success_val');
                  create_namespace                   
-----------------------------------------------------
 {"namespace": ["ns_success_val"], "properties": {}}
(1 row)
SELECT (iceberg_catalog.drop_namespace('ns_success_val') ->> 'success')::BOOLEAN AS success_value;
 success_value 
---------------
 t
(1 row)
-- 3. Drops metadata row
SELECT iceberg_catalog.create_namespace('temp_ns', '{"owner": "test"}'::JSONB);
                   create_namespace                    
-------------------------------------------------------
 {"namespace": ["temp_ns"], "properties": {"owner": "test"}}
(1 row)
SELECT iceberg_catalog.drop_namespace('temp_ns');
  drop_namespace   
-------------------
 {"success": true}
(1 row)
SELECT count(*) = 0 AS is_deleted
FROM iceberg_catalog.namespaces
WHERE catalog_name = current_database()
  AND namespace = 'temp_ns';
 is_deleted 
------------
 t
(1 row)
-- 4. Empty namespace argument errors
SAVEPOINT sp4;
SAVEPOINT
SELECT iceberg_catalog.drop_namespace('');
gsql:test/sql/drop_namespace.sql:28: ERROR:  namespace must not be empty
CONTEXT:  referenced column: drop_namespace
ROLLBACK TO SAVEPOINT sp4;
ROLLBACK
-- 5. NULL namespace argument errors
SAVEPOINT sp5;
SAVEPOINT
SELECT iceberg_catalog.drop_namespace(NULL::TEXT);
gsql:test/sql/drop_namespace.sql:33: ERROR:  namespace must not be empty
CONTEXT:  referenced column: drop_namespace
ROLLBACK TO SAVEPOINT sp5;
ROLLBACK
-- 6. Missing namespace errors
SAVEPOINT sp6;
SAVEPOINT
SELECT iceberg_catalog.drop_namespace('non_existent_namespace');
gsql:test/sql/drop_namespace.sql:38: ERROR:  drop namespace metadata: namespace "non_existent_namespace" does not exist
CONTEXT:  referenced column: drop_namespace
ROLLBACK TO SAVEPOINT sp6;
ROLLBACK
-- 7. Drops the corresponding openGauss schema
SAVEPOINT sp7;
SAVEPOINT
SELECT iceberg_catalog.create_namespace('ns_schema_check');
                   create_namespace                   
------------------------------------------------------
 {"namespace": ["ns_schema_check"], "properties": {}}
(1 row)
SELECT count(*) = 1 AS schema_exists_before
FROM pg_namespace
WHERE nspname = 'ns_schema_check';
 schema_exists_before 
----------------------
 t
(1 row)
SELECT iceberg_catalog.drop_namespace('ns_schema_check');
  drop_namespace   
-------------------
 {"success": true}
(1 row)
SELECT count(*) = 0 AS schema_gone_after
FROM pg_namespace
WHERE nspname = 'ns_schema_check';
 schema_gone_after 
-------------------
 t
(1 row)
ROLLBACK TO SAVEPOINT sp7;
ROLLBACK
-- 8. Namespace with internal tables errors
SAVEPOINT sp8;
SAVEPOINT
SELECT iceberg_catalog.create_namespace('ns_with_tables');
                  create_namespace                   
-----------------------------------------------------
 {"namespace": ["ns_with_tables"], "properties": {}}
(1 row)
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
INSERT 0 1
SELECT iceberg_catalog.drop_namespace('ns_with_tables');
gsql:test/sql/drop_namespace.sql:69: ERROR:  drop namespace metadata: namespace is not empty
CONTEXT:  referenced column: drop_namespace
ROLLBACK TO SAVEPOINT sp8;
ROLLBACK
ROLLBACK;
ROLLBACK

-- ============================================================================
-- commit_table / add_column — metadata 层正确性验证
-- ============================================================================
BEGIN;
BEGIN
-- ### Setup: use SQL functions to create namespace and table ###
SELECT iceberg_catalog.create_namespace('cmt_test', '{}'::jsonb);
               create_namespace                
-----------------------------------------------
 {"namespace": ["cmt_test"], "properties": {}}
(1 row)
SELECT iceberg_catalog.create_table(
    'cmt_test', 't1',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true},{"id":2,"name":"data","type":"string","required":false}]}'::jsonb
) AS create_result;
                                                                                                                                                                                                                                                                                                                                                                                           create_result                                                                                                                                                                                                                                                                                                                                                                                           
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {"refs": {}, "schemas": [{"type": "struct", "fields": [{"id": 1, "name": "id", "type": "long", "required": true}, {"id": 2, "name": "data", "type": "string", "required": false}], "schema-id": 0}], "location": "file:///tmp/iceberg_warehouse/cmt_test/t1", "table-uuid": "<uuid>", "sort-orders": [{"fields": [], "order-id": 0}], "format-version": 2, "last-column-id": 2, "default-spec-id": 0, "last-updated-ms": <ts>, "partition-specs": [{"fields": [], "spec-id": 0}], "current-schema-id": 0, "last-partition-id": 999, "last-sequence-number": 0, "default-sort-order-id": 0}, "metadata-location": "file:///tmp/iceberg_warehouse/cmt_test/t1/metadata/00000-<uuid>.metadata.json"}
(1 row)
-- Capture the generated table_uuid for later assertions
CREATE TEMP TABLE _t1_uuid AS
SELECT table_uuid, metadata_location, last_column_id, current_schema_id
FROM iceberg_catalog.tables_internal
WHERE namespace = 'cmt_test' AND table_name = 't1';
INSERT 0 1
-- ============================================================================
-- T1: commit_table → metadata_location 轮转 + snapshot 写入
-- ============================================================================
-- 初始: snapshots 空
SELECT count(*) = 0 AS t1_snap_empty
FROM iceberg_catalog.snapshots s, _t1_uuid u
WHERE s.table_uuid = u.table_uuid;
 t1_snap_empty 
---------------
 t
(1 row)
-- 执行 commit_table
SELECT iceberg_catalog.commit_table('cmt_test', 't1',
    '[]'::jsonb,
    '[{"action":"add-snapshot","snapshot":{"snapshot-id":100,"timestamp-ms":4782185701401,"manifest-list":"s3://m","summary":{"operation":"append"},"schema-id":0}}]'::jsonb
) AS cmt_result;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          cmt_result                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {"refs": {}, "schemas": [{"type": "struct", "fields": [{"id": 1, "name": "id", "type": "long", "required": true}, {"id": 2, "name": "data", "type": "string", "required": false}], "schema-id": 0}], "location": "file:///tmp/iceberg_warehouse/cmt_test/t1", "snapshots": [{"summary": {"operation": "append"}, "schema-id": 0, "snapshot-id": 100, "timestamp-ms": <ts>, "manifest-list": "s3://m", "sequence-number": 0}], "table-uuid": "<uuid>", "sort-orders": [{"fields": [], "order-id": 0}], "metadata-log": [{"timestamp-ms": <ts>, "metadata-file": "file:///tmp/iceberg_warehouse/cmt_test/t1/metadata/00000-<uuid>.metadata.json"}], "format-version": 2, "last-column-id": 2, "default-spec-id": 0, "last-updated-ms": <ts>, "partition-specs": [{"fields": [], "spec-id": 0}], "current-schema-id": 0, "last-partition-id": 999, "last-sequence-number": 0, "default-sort-order-id": 0}, "metadata-location": "file:///tmp/iceberg_warehouse/cmt_test/t1/metadata/00001-<uuid>.metadata.json"}
(1 row)
-- 验证: metadata_location 已更新, previous 自动轮转
SELECT t.metadata_location != u.metadata_location  AS t1_meta_updated,
       t.previous_metadata_location = u.metadata_location AS t1_prev_rolled
FROM iceberg_catalog.tables_internal t, _t1_uuid u
WHERE t.namespace = 'cmt_test' AND t.table_name = 't1';
 t1_meta_updated | t1_prev_rolled 
-----------------+----------------
 t               | t
(1 row)
-- 验证: snapshot 已写入
SELECT count(*) = 1 AS t1_snap_inserted
FROM iceberg_catalog.snapshots s, _t1_uuid u
WHERE s.table_uuid = u.table_uuid;
 t1_snap_inserted 
------------------
 t
(1 row)
-- ============================================================================
-- T2: add_column → schema 展开写入 + 状态字段更新
-- ============================================================================
-- 初始: 2 fields
SELECT count(*) = 2 AS t2_schema_before
FROM iceberg_catalog.table_schemas s, _t1_uuid u
WHERE s.table_uuid = u.table_uuid;
 t2_schema_before 
------------------
 t
(1 row)
SELECT last_column_id = 2 AND current_schema_id = 0 AS t2_state_before
FROM iceberg_catalog.tables_internal
WHERE namespace = 'cmt_test' AND table_name = 't1';
 t2_state_before 
-----------------
 t
(1 row)
-- 执行 add_column
SELECT iceberg_catalog.add_column('cmt_test', 't1', 'col3', 'string', 'third column') AS add_result;
                                                                             add_result                                                                             
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {}, "metadata-location": "file:///tmp/iceberg_warehouse/cmt_test/t1/metadata/00002-<uuid>.metadata.json"}
(1 row)
-- 验证: schema 字段增加到 3 个
SELECT count(*) = 3 AS t2_schema_after
FROM iceberg_catalog.table_schemas s, _t1_uuid u
WHERE s.table_uuid = u.table_uuid;
 t2_schema_after 
-----------------
 t
(1 row)
-- 验证: last_column_id 和 current_schema_id 已更新
SELECT last_column_id > 2 AND current_schema_id > 0 AS t2_state_updated
FROM iceberg_catalog.tables_internal
WHERE namespace = 'cmt_test' AND table_name = 't1';
 t2_state_updated 
------------------
 t
(1 row)
-- ============================================================================
-- T3: 参数校验
-- ============================================================================
SAVEPOINT sp1;
SAVEPOINT
SELECT iceberg_catalog.commit_table('', 't', '[]'::jsonb, '[]'::jsonb);
gsql:test/sql/commit_table_add_column.sql:78: ERROR:  p_namespace is required and must not be empty
CONTEXT:  referenced column: commit_table
ROLLBACK TO SAVEPOINT sp1;
ROLLBACK
SAVEPOINT sp2;
SAVEPOINT
SELECT iceberg_catalog.commit_table('n', '', '[]'::jsonb, '[]'::jsonb);
gsql:test/sql/commit_table_add_column.sql:82: ERROR:  p_table is required and must not be empty
CONTEXT:  referenced column: commit_table
ROLLBACK TO SAVEPOINT sp2;
ROLLBACK
SAVEPOINT sp3;
SAVEPOINT
SELECT iceberg_catalog.add_column('', 't', 'c', 'string');
gsql:test/sql/commit_table_add_column.sql:86: ERROR:  p_namespace is required and must not be empty
CONTEXT:  referenced column: add_column
ROLLBACK TO SAVEPOINT sp3;
ROLLBACK
SAVEPOINT sp4;
SAVEPOINT
SELECT iceberg_catalog.add_column('n', 't', '', 'string');
gsql:test/sql/commit_table_add_column.sql:90: ERROR:  p_column_name is required and must not be empty
CONTEXT:  referenced column: add_column
ROLLBACK TO SAVEPOINT sp4;
ROLLBACK
-- ============================================================================
-- T4: 表不存在
-- ============================================================================
SAVEPOINT sp5;
SAVEPOINT
SELECT iceberg_catalog.commit_table('cmt_test', 'no_such_table', '[]'::jsonb, '[]'::jsonb);
gsql:test/sql/commit_table_add_column.sql:98: ERROR:  commit table metadata lock: table "cmt_test.no_such_table" not found
CONTEXT:  referenced column: commit_table
ROLLBACK TO SAVEPOINT sp5;
ROLLBACK
SAVEPOINT sp6;
SAVEPOINT
SELECT iceberg_catalog.add_column('cmt_test', 'no_such_table', 'col', 'string');
gsql:test/sql/commit_table_add_column.sql:102: ERROR:  add column metadata lock: table "cmt_test.no_such_table" not found
CONTEXT:  referenced column: add_column
ROLLBACK TO SAVEPOINT sp6;
ROLLBACK
-- ============================================================================
-- T5: drop_table 级联删除
-- ============================================================================
SELECT iceberg_catalog.drop_table('cmt_test', 't1', false) AS drop_result;
    drop_result    
-------------------
 {"success": true}
(1 row)
SELECT count(*) = 0 AS t5_snaps_cleaned
FROM iceberg_catalog.snapshots s, _t1_uuid u
WHERE s.table_uuid = u.table_uuid;
 t5_snaps_cleaned 
------------------
 t
(1 row)
SELECT count(*) = 0 AS t5_schemas_cleaned
FROM iceberg_catalog.table_schemas s, _t1_uuid u
WHERE s.table_uuid = u.table_uuid;
 t5_schemas_cleaned 
--------------------
 t
(1 row)
SELECT count(*) = 0 AS t5_specs_cleaned
FROM iceberg_catalog.partition_specs p, _t1_uuid u
WHERE p.table_uuid = u.table_uuid;
 t5_specs_cleaned 
------------------
 t
(1 row)
DROP TABLE _t1_uuid;
DROP TABLE
ROLLBACK;
ROLLBACK

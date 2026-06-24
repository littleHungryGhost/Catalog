-- ============================================================================
-- iceberg_catalog.list_tables 测试用例
-- ============================================================================
BEGIN;
BEGIN
-- ### Setup: create namespaces and tables for metadata verification ###
SELECT iceberg_catalog.create_namespace('lt_ns', '{}'::jsonb);
              create_namespace              
--------------------------------------------
 {"namespace": ["lt_ns"], "properties": {}}
(1 row)
SELECT iceberg_catalog.create_namespace('lt_empty_ns', '{}'::jsonb);
                 create_namespace                 
--------------------------------------------------
 {"namespace": ["lt_empty_ns"], "properties": {}}
(1 row)
SELECT iceberg_catalog.create_namespace('lt_page_ns', '{}'::jsonb);
                create_namespace                 
-------------------------------------------------
 {"namespace": ["lt_page_ns"], "properties": {}}
(1 row)
-- Create 3 tables in lt_ns
SELECT iceberg_catalog.create_table(
    'lt_ns', 'tbl_a',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::jsonb
) AS create_a;
                                                                                                                                                                                                                                                                                                                                                             create_a                                                                                                                                                                                                                                                                                                                                                              
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {"refs": {}, "schemas": [{"type": "struct", "fields": [{"id": 1, "name": "id", "type": "long", "required": true}], "schema-id": 0}], "location": "file:///tmp/iceberg_warehouse/lt_ns/tbl_a", "table-uuid": "<uuid>", "sort-orders": [{"fields": [], "order-id": 0}], "format-version": 2, "last-column-id": 1, "default-spec-id": 0, "last-updated-ms": <ts>, "partition-specs": [{"fields": [], "spec-id": 0}], "current-schema-id": 0, "last-partition-id": 999, "last-sequence-number": 0, "default-sort-order-id": 0}, "metadata-location": "file:///tmp/iceberg_warehouse/lt_ns/tbl_a/metadata/00000-<uuid>.metadata.json"}
(1 row)
SELECT iceberg_catalog.create_table(
    'lt_ns', 'tbl_b',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::jsonb
) AS create_b;
                                                                                                                                                                                                                                                                                                                                                             create_b                                                                                                                                                                                                                                                                                                                                                              
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {"refs": {}, "schemas": [{"type": "struct", "fields": [{"id": 1, "name": "id", "type": "long", "required": true}], "schema-id": 0}], "location": "file:///tmp/iceberg_warehouse/lt_ns/tbl_b", "table-uuid": "<uuid>", "sort-orders": [{"fields": [], "order-id": 0}], "format-version": 2, "last-column-id": 1, "default-spec-id": 0, "last-updated-ms": <ts>, "partition-specs": [{"fields": [], "spec-id": 0}], "current-schema-id": 0, "last-partition-id": 999, "last-sequence-number": 0, "default-sort-order-id": 0}, "metadata-location": "file:///tmp/iceberg_warehouse/lt_ns/tbl_b/metadata/00000-<uuid>.metadata.json"}
(1 row)
SELECT iceberg_catalog.create_table(
    'lt_ns', 'tbl_c',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::jsonb
) AS create_c;
                                                                                                                                                                                                                                                                                                                                                             create_c                                                                                                                                                                                                                                                                                                                                                              
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {"refs": {}, "schemas": [{"type": "struct", "fields": [{"id": 1, "name": "id", "type": "long", "required": true}], "schema-id": 0}], "location": "file:///tmp/iceberg_warehouse/lt_ns/tbl_c", "table-uuid": "<uuid>", "sort-orders": [{"fields": [], "order-id": 0}], "format-version": 2, "last-column-id": 1, "default-spec-id": 0, "last-updated-ms": <ts>, "partition-specs": [{"fields": [], "spec-id": 0}], "current-schema-id": 0, "last-partition-id": 999, "last-sequence-number": 0, "default-sort-order-id": 0}, "metadata-location": "file:///tmp/iceberg_warehouse/lt_ns/tbl_c/metadata/00000-<uuid>.metadata.json"}
(1 row)
-- Create 7 tables in lt_page_ns for pagination tests
-- Names with length % 3 != 0 produce base64 page tokens with '=' padding,
-- which triggered a b64_decode buffer overflow (fixed in metadata.cpp).
SELECT iceberg_catalog.create_table(
    'lt_page_ns', 'p01',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::jsonb
);
                                                                                                                                                                                                                                                                                                                                                              create_table                                                                                                                                                                                                                                                                                                                                                               
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {"refs": {}, "schemas": [{"type": "struct", "fields": [{"id": 1, "name": "id", "type": "long", "required": true}], "schema-id": 0}], "location": "file:///tmp/iceberg_warehouse/lt_page_ns/p01", "table-uuid": "<uuid>", "sort-orders": [{"fields": [], "order-id": 0}], "format-version": 2, "last-column-id": 1, "default-spec-id": 0, "last-updated-ms": <ts>, "partition-specs": [{"fields": [], "spec-id": 0}], "current-schema-id": 0, "last-partition-id": 999, "last-sequence-number": 0, "default-sort-order-id": 0}, "metadata-location": "file:///tmp/iceberg_warehouse/lt_page_ns/p01/metadata/00000-<uuid>.metadata.json"}
(1 row)
SELECT iceberg_catalog.create_table(
    'lt_page_ns', 'p02',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::jsonb
);
                                                                                                                                                                                                                                                                                                                                                              create_table                                                                                                                                                                                                                                                                                                                                                               
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {"refs": {}, "schemas": [{"type": "struct", "fields": [{"id": 1, "name": "id", "type": "long", "required": true}], "schema-id": 0}], "location": "file:///tmp/iceberg_warehouse/lt_page_ns/p02", "table-uuid": "<uuid>", "sort-orders": [{"fields": [], "order-id": 0}], "format-version": 2, "last-column-id": 1, "default-spec-id": 0, "last-updated-ms": <ts>, "partition-specs": [{"fields": [], "spec-id": 0}], "current-schema-id": 0, "last-partition-id": 999, "last-sequence-number": 0, "default-sort-order-id": 0}, "metadata-location": "file:///tmp/iceberg_warehouse/lt_page_ns/p02/metadata/00000-<uuid>.metadata.json"}
(1 row)
SELECT iceberg_catalog.create_table(
    'lt_page_ns', 'p03',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::jsonb
);
                                                                                                                                                                                                                                                                                                                                                              create_table                                                                                                                                                                                                                                                                                                                                                               
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {"refs": {}, "schemas": [{"type": "struct", "fields": [{"id": 1, "name": "id", "type": "long", "required": true}], "schema-id": 0}], "location": "file:///tmp/iceberg_warehouse/lt_page_ns/p03", "table-uuid": "<uuid>", "sort-orders": [{"fields": [], "order-id": 0}], "format-version": 2, "last-column-id": 1, "default-spec-id": 0, "last-updated-ms": <ts>, "partition-specs": [{"fields": [], "spec-id": 0}], "current-schema-id": 0, "last-partition-id": 999, "last-sequence-number": 0, "default-sort-order-id": 0}, "metadata-location": "file:///tmp/iceberg_warehouse/lt_page_ns/p03/metadata/00000-<uuid>.metadata.json"}
(1 row)
SELECT iceberg_catalog.create_table(
    'lt_page_ns', 'p04',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::jsonb
);
                                                                                                                                                                                                                                                                                                                                                              create_table                                                                                                                                                                                                                                                                                                                                                               
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {"refs": {}, "schemas": [{"type": "struct", "fields": [{"id": 1, "name": "id", "type": "long", "required": true}], "schema-id": 0}], "location": "file:///tmp/iceberg_warehouse/lt_page_ns/p04", "table-uuid": "<uuid>", "sort-orders": [{"fields": [], "order-id": 0}], "format-version": 2, "last-column-id": 1, "default-spec-id": 0, "last-updated-ms": <ts>, "partition-specs": [{"fields": [], "spec-id": 0}], "current-schema-id": 0, "last-partition-id": 999, "last-sequence-number": 0, "default-sort-order-id": 0}, "metadata-location": "file:///tmp/iceberg_warehouse/lt_page_ns/p04/metadata/00000-<uuid>.metadata.json"}
(1 row)
SELECT iceberg_catalog.create_table(
    'lt_page_ns', 'p05',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::jsonb
);
                                                                                                                                                                                                                                                                                                                                                              create_table                                                                                                                                                                                                                                                                                                                                                               
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {"refs": {}, "schemas": [{"type": "struct", "fields": [{"id": 1, "name": "id", "type": "long", "required": true}], "schema-id": 0}], "location": "file:///tmp/iceberg_warehouse/lt_page_ns/p05", "table-uuid": "<uuid>", "sort-orders": [{"fields": [], "order-id": 0}], "format-version": 2, "last-column-id": 1, "default-spec-id": 0, "last-updated-ms": <ts>, "partition-specs": [{"fields": [], "spec-id": 0}], "current-schema-id": 0, "last-partition-id": 999, "last-sequence-number": 0, "default-sort-order-id": 0}, "metadata-location": "file:///tmp/iceberg_warehouse/lt_page_ns/p05/metadata/00000-<uuid>.metadata.json"}
(1 row)
SELECT iceberg_catalog.create_table(
    'lt_page_ns', 'p006',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::jsonb
);
                                                                                                                                                                                                                                                                                                                                                               create_table                                                                                                                                                                                                                                                                                                                                                                
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {"refs": {}, "schemas": [{"type": "struct", "fields": [{"id": 1, "name": "id", "type": "long", "required": true}], "schema-id": 0}], "location": "file:///tmp/iceberg_warehouse/lt_page_ns/p006", "table-uuid": "<uuid>", "sort-orders": [{"fields": [], "order-id": 0}], "format-version": 2, "last-column-id": 1, "default-spec-id": 0, "last-updated-ms": <ts>, "partition-specs": [{"fields": [], "spec-id": 0}], "current-schema-id": 0, "last-partition-id": 999, "last-sequence-number": 0, "default-sort-order-id": 0}, "metadata-location": "file:///tmp/iceberg_warehouse/lt_page_ns/p006/metadata/00000-<uuid>.metadata.json"}
(1 row)
SELECT iceberg_catalog.create_table(
    'lt_page_ns', 'p007',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::jsonb
);
                                                                                                                                                                                                                                                                                                                                                               create_table                                                                                                                                                                                                                                                                                                                                                                
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"config": {}, "metadata": {"refs": {}, "schemas": [{"type": "struct", "fields": [{"id": 1, "name": "id", "type": "long", "required": true}], "schema-id": 0}], "location": "file:///tmp/iceberg_warehouse/lt_page_ns/p007", "table-uuid": "<uuid>", "sort-orders": [{"fields": [], "order-id": 0}], "format-version": 2, "last-column-id": 1, "default-spec-id": 0, "last-updated-ms": <ts>, "partition-specs": [{"fields": [], "spec-id": 0}], "current-schema-id": 0, "last-partition-id": 999, "last-sequence-number": 0, "default-sort-order-id": 0}, "metadata-location": "file:///tmp/iceberg_warehouse/lt_page_ns/p007/metadata/00000-<uuid>.metadata.json"}
(1 row)
-- ============================================================================
-- T1: 基础调用 — 返回 JSONB object，包含顶层 key
-- ============================================================================
SELECT jsonb_typeof(iceberg_catalog.list_tables('lt_ns')) AS t1_result_type;
 t1_result_type 
----------------
 object
(1 row)
SELECT
    iceberg_catalog.list_tables('lt_ns') ? 'identifiers'     AS t1_has_identifiers,
    iceberg_catalog.list_tables('lt_ns') ? 'next-page-token' AS t1_has_next_page_token;
 t1_has_identifiers | t1_has_next_page_token 
--------------------+------------------------
 t                  | t
(1 row)
-- ============================================================================
-- T2: 验证 list_tables 返回创建的表（元信息验证）
-- ============================================================================
-- 验证 identifiers 数组包含 3 个元素
SELECT jsonb_array_length(
    (iceberg_catalog.list_tables('lt_ns'))->'identifiers'
) = 3 AS t2_total_count;
 t2_total_count 
----------------
 t
(1 row)
-- 验证每行有 namespace 和 name 字段
SELECT
    bool_and(elem ? 'namespace') AS t2_has_namespace,
    bool_and(elem ? 'name')      AS t2_has_name
FROM jsonb_array_elements(
    (iceberg_catalog.list_tables('lt_ns'))->'identifiers'
) AS elem;
 t2_has_namespace | t2_has_name 
------------------+-------------
 t                | t
(1 row)
-- 验证 namespace 数组格式：["lt_ns"]
SELECT bool_and(elem->'namespace' = '["lt_ns"]'::jsonb) AS t2_namespace_format
FROM jsonb_array_elements(
    (iceberg_catalog.list_tables('lt_ns'))->'identifiers'
) AS elem;
 t2_namespace_format 
---------------------
 t
(1 row)
-- ============================================================================
-- T3: 验证返回的表名与 tables_internal 一致
-- ============================================================================
SELECT
    count(*) = 3 AS t3_list_count,
    bool_or(table_name = 'tbl_a') AS t3_has_tbl_a,
    bool_or(table_name = 'tbl_b') AS t3_has_tbl_b,
    bool_or(table_name = 'tbl_c') AS t3_has_tbl_c
FROM iceberg_catalog.tables_internal
WHERE namespace = 'lt_ns';
 t3_list_count | t3_has_tbl_a | t3_has_tbl_b | t3_has_tbl_c 
---------------+--------------+--------------+--------------
 t             | t            | t            | t
(1 row)
-- ============================================================================
-- T4: 空 namespace 返回空列表
-- ============================================================================
SELECT jsonb_array_length(
    (iceberg_catalog.list_tables('lt_empty_ns'))->'identifiers'
) = 0 AS t4_empty_identifiers;
 t4_empty_identifiers 
----------------------
 t
(1 row)
SELECT ((iceberg_catalog.list_tables('lt_empty_ns'))->>'next-page-token') IS NULL
    AS t4_null_next_token;
 t4_null_next_token 
--------------------
 t
(1 row)
-- ============================================================================
-- T5: 分页 — page_size = 2，总共有 5 个表，第一页应有 next-page-token
-- ============================================================================
SELECT jsonb_array_length(
    (iceberg_catalog.list_tables('lt_page_ns', 2))->'identifiers'
) = 2 AS t5_page1_count;
 t5_page1_count 
----------------
 t
(1 row)
SELECT ((iceberg_catalog.list_tables('lt_page_ns', 2))->>'next-page-token') IS NOT NULL
    AS t5_page1_has_token;
 t5_page1_has_token 
--------------------
 t
(1 row)
-- ============================================================================
-- T6: 分页 — 第二页使用 first-page token 继续
-- ============================================================================
CREATE TEMP TABLE _lt_page_token AS
SELECT (iceberg_catalog.list_tables('lt_page_ns', 2))->>'next-page-token' AS token;
INSERT 0 1
-- Page 2: should return 2 more tables
SELECT jsonb_array_length(
    (iceberg_catalog.list_tables('lt_page_ns', 2,
        (SELECT token FROM _lt_page_token)))->'identifiers'
) = 2 AS t6_page2_count;
 t6_page2_count 
----------------
 t
(1 row)
-- ============================================================================
-- T7: 分页 — page_size 足够大时不返回 next-page-token
-- ============================================================================
SELECT
    jsonb_array_length(
        (iceberg_catalog.list_tables('lt_page_ns', 100))->'identifiers'
    ) = 7 AS t7_all_count,
    ((iceberg_catalog.list_tables('lt_page_ns', 100))->>'next-page-token') IS NULL
    AS t7_no_next_token;
 t7_all_count | t7_no_next_token 
--------------+------------------
 t            | t
(1 row)
-- ============================================================================
-- T8: 参数校验
-- ============================================================================
-- p_page_size = 1（边界值）
SELECT iceberg_catalog.list_tables('lt_ns', 1);
                                                                           list_tables                                                                           
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"identifiers": [{"name": "tbl_a", "namespace": ["lt_ns"]}], "next-page-token": "eyJ2IjoxLCJ0eXBlIjoidGFibGUiLCJuYW1lc3BhY2UiOiJsdF9ucyIsImxhc3QiOiJ0YmxfYSJ9"}
(1 row)
-- p_page_size = 0 → 报错
SAVEPOINT sp_size0;
SAVEPOINT
SELECT iceberg_catalog.list_tables('lt_ns', 0);
gsql:test/sql/list_tables.sql:159: ERROR:  p_page_size must be >= 1
CONTEXT:  referenced column: list_tables
ROLLBACK TO SAVEPOINT sp_size0;
ROLLBACK
-- p_namespace 为空串 → 报错
SAVEPOINT sp_empty_ns;
SAVEPOINT
SELECT iceberg_catalog.list_tables('');
gsql:test/sql/list_tables.sql:164: ERROR:  p_namespace is required and must not be empty
CONTEXT:  referenced column: list_tables
ROLLBACK TO SAVEPOINT sp_empty_ns;
ROLLBACK
-- p_namespace 为 NULL → 报错
SAVEPOINT sp_null_ns;
SAVEPOINT
SELECT iceberg_catalog.list_tables(NULL);
gsql:test/sql/list_tables.sql:169: ERROR:  p_namespace is required and must not be empty
CONTEXT:  referenced column: list_tables
ROLLBACK TO SAVEPOINT sp_null_ns;
ROLLBACK
-- ============================================================================
-- T9: namespace 不存在 → 报错
-- ============================================================================
SAVEPOINT sp_missing_ns;
SAVEPOINT
SELECT iceberg_catalog.list_tables('nonexistent_ns');
gsql:test/sql/list_tables.sql:177: ERROR:  list tables: namespace "nonexistent_ns" does not exist
CONTEXT:  referenced column: list_tables
ROLLBACK TO SAVEPOINT sp_missing_ns;
ROLLBACK
-- ============================================================================
-- T10: 无效 page_token → 报错
-- ============================================================================
SAVEPOINT sp_bad_token;
SAVEPOINT
SELECT iceberg_catalog.list_tables('lt_ns', 10, 'not-a-valid-base64-token!!!');
gsql:test/sql/list_tables.sql:185: ERROR:  list tables: page_token is not a valid base64-encoded string
CONTEXT:  referenced column: list_tables
ROLLBACK TO SAVEPOINT sp_bad_token;
ROLLBACK
-- ============================================================================
-- T11: 验证带 '=' 填充的 page_token (b64_decode buffer overflow fix)
-- p006/p007 的 name 长度为 4 字节 → "last" 为 4 字节 → base64 有 '=' 填充
-- 之前触发 PANIC: detected write past chunk end in ExprContext
-- ============================================================================
SELECT (iceberg_catalog.list_tables('lt_page_ns', 2)->>'next-page-token') LIKE '%=' AS t11_token_has_padding;
 t11_token_has_padding 
-----------------------
 t
(1 row)
-- Cleanup
DROP TABLE IF EXISTS _lt_page_token;
DROP TABLE
ROLLBACK;
ROLLBACK

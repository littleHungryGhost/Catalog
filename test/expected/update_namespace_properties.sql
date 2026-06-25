-- ============================================================================
-- iceberg_catalog.update_namespace_properties 测试用例
--
-- 前置条件：iceberg_catalog 扩展已安装
-- ============================================================================
BEGIN;
BEGIN
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'test_ns', '{}'::JSONB);
INSERT 0 1
-- ============================================================================
-- 第一部分：正常场景 — 返回类型与结构校验
-- ============================================================================
-- 1. 仅使用 p_updates，返回合法 JSONB
SELECT jsonb_typeof(iceberg_catalog.update_namespace_properties(
    'test_ns',
    p_updates => '{"owner": "alice"}'::JSONB
)) AS result_type;
 result_type 
-------------
 object
(1 row)
UPDATE iceberg_catalog.namespaces
SET properties = '{"deprecated_key": "old"}'::JSONB
WHERE catalog_name = current_database()
  AND namespace = 'test_ns';
UPDATE 1
-- 2. 仅使用 p_removals，返回合法 JSONB
SELECT jsonb_typeof(iceberg_catalog.update_namespace_properties(
    'test_ns',
    p_removals => '["deprecated_key"]'::JSONB
)) AS result_type;
 result_type 
-------------
 object
(1 row)
-- ============================================================================
-- 第二部分：正常操作 — 更新已有 Namespace 属性
-- ============================================================================
-- 3. 创建 namespace 后更新属性
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'updatable_ns', '{"owner": "bob", "region": "us"}'::JSONB);
INSERT 0 1
SELECT iceberg_catalog.update_namespace_properties(
    'updatable_ns',
    p_updates => '{"owner": "carol", "env": "prod"}'::JSONB
) = '{"updated":["env","owner"],"removed":[],"missing":[]}'::JSONB AS update_response_ok;
 update_response_ok 
--------------------
 t
(1 row)
SELECT properties = '{"owner": "carol", "region": "us", "env": "prod"}'::JSONB AS properties_updated
FROM iceberg_catalog.namespaces
WHERE catalog_name = current_database()
  AND namespace = 'updatable_ns';
 properties_updated 
--------------------
 t
(1 row)
-- 4. 删除属性
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'removable_ns', '{"owner": "dave", "temp": "x", "region": "eu"}'::JSONB);
INSERT 0 1
SELECT iceberg_catalog.update_namespace_properties(
    'removable_ns',
    p_removals => '["temp"]'::JSONB
) = '{"updated":[],"removed":["temp"],"missing":[]}'::JSONB AS removal_response_ok;
 removal_response_ok 
---------------------
 t
(1 row)
SELECT properties = '{"owner": "dave", "region": "eu"}'::JSONB AS properties_removed
FROM iceberg_catalog.namespaces
WHERE catalog_name = current_database()
  AND namespace = 'removable_ns';
 properties_removed 
--------------------
 t
(1 row)
-- 5. 同时更新和删除
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'combined_ns', '{"a": "1", "b": "2", "c": "3"}'::JSONB);
INSERT 0 1
SELECT iceberg_catalog.update_namespace_properties(
    'combined_ns',
    p_removals => '["a"]'::JSONB,
    p_updates  => '{"b": "updated", "d": "new"}'::JSONB
) = '{"updated":["b","d"],"removed":["a"],"missing":[]}'::JSONB AS combined_response_ok;
 combined_response_ok 
----------------------
 t
(1 row)
SELECT properties = '{"b": "updated", "c": "3", "d": "new"}'::JSONB AS properties_combined
FROM iceberg_catalog.namespaces
WHERE catalog_name = current_database()
  AND namespace = 'combined_ns';
 properties_combined 
---------------------
 t
(1 row)
-- ============================================================================
-- 第三部分：参数校验 — 报错场景
-- ============================================================================
-- 6. p_namespace 为空字符串 → 报错 (P0001)
SAVEPOINT sp6;
SAVEPOINT
SELECT iceberg_catalog.update_namespace_properties(
    '',
    p_updates => '{"key": "val"}'::JSONB
);
gsql:test/sql/update_namespace_properties.sql:89: ERROR:  namespace must not be empty
CONTEXT:  referenced column: update_namespace_properties
ROLLBACK TO SAVEPOINT sp6;
ROLLBACK
-- 7. p_namespace 为 NULL → 报错 (P0001)
SAVEPOINT sp7;
SAVEPOINT
SELECT iceberg_catalog.update_namespace_properties(
    NULL::TEXT,
    p_updates => '{"key": "val"}'::JSONB
);
gsql:test/sql/update_namespace_properties.sql:97: ERROR:  namespace must not be empty
CONTEXT:  referenced column: update_namespace_properties
ROLLBACK TO SAVEPOINT sp7;
ROLLBACK
-- 8. p_removals 和 p_updates 同时为 NULL → 报错 (P0001)
SAVEPOINT sp8;
SAVEPOINT
SELECT iceberg_catalog.update_namespace_properties('ns');
gsql:test/sql/update_namespace_properties.sql:102: ERROR:  p_removals and p_updates cannot both be NULL
CONTEXT:  referenced column: update_namespace_properties
ROLLBACK TO SAVEPOINT sp8;
ROLLBACK
-- ============================================================================
-- 第四部分：参数校验 — 报错场景
-- ============================================================================
-- 9. p_removals 不是 JSONB 数组 → 报错 (P0001)
SAVEPOINT sp9;
SAVEPOINT
SELECT iceberg_catalog.update_namespace_properties(
    'ns',
    p_removals => '"not_an_array"'::JSONB
);
gsql:test/sql/update_namespace_properties.sql:114: ERROR:  p_removals must be a JSONB array
CONTEXT:  referenced column: update_namespace_properties
ROLLBACK TO SAVEPOINT sp9;
ROLLBACK
-- 10. p_updates 不是 JSONB object → 报错 (P0001)
SAVEPOINT sp10;
SAVEPOINT
SELECT iceberg_catalog.update_namespace_properties(
    'ns',
    p_updates => '"not_an_object"'::JSONB
);
gsql:test/sql/update_namespace_properties.sql:122: ERROR:  p_updates must be a JSONB object
CONTEXT:  referenced column: update_namespace_properties
ROLLBACK TO SAVEPOINT sp10;
ROLLBACK
-- 11. removals ∩ updates ≠ ∅ → 报错 (P0006)
SAVEPOINT sp11;
SAVEPOINT
SELECT iceberg_catalog.update_namespace_properties(
    'ns',
    p_removals => '["same_key"]'::JSONB,
    p_updates  => '{"same_key": "val"}'::JSONB
);
gsql:test/sql/update_namespace_properties.sql:131: ERROR:  removals and updates must not contain overlapping keys
CONTEXT:  referenced column: update_namespace_properties
ROLLBACK TO SAVEPOINT sp11;
ROLLBACK
-- ============================================================================
-- 第五部分：边界场景
-- ============================================================================
-- 12. p_removals 为空数组（合法，无可删除的 key）
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'ns', '{}'::JSONB);
INSERT 0 1
SELECT iceberg_catalog.update_namespace_properties(
    'ns',
    p_removals => '[]'::JSONB
) = '{"updated":[],"removed":[],"missing":[]}'::JSONB AS empty_removals_ok;
 empty_removals_ok 
-------------------
 t
(1 row)
-- 13. p_updates 为空对象（合法，无更新的 key）
SELECT iceberg_catalog.update_namespace_properties(
    'ns',
    p_updates => '{}'::JSONB
) = '{"updated":[],"removed":[],"missing":[]}'::JSONB AS empty_updates_ok;
 empty_updates_ok 
------------------
 t
(1 row)
-- 14. 使用位置参数
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'positional_ns', '{"x": "old"}'::JSONB);
INSERT 0 1
SELECT iceberg_catalog.update_namespace_properties(
    'positional_ns',
    '["x"]'::JSONB,
    '{"y": "z"}'::JSONB
) = '{"updated":["y"],"removed":["x"],"missing":[]}'::JSONB AS positional_args_ok;
 positional_args_ok 
--------------------
 t
(1 row)
ROLLBACK;
ROLLBACK

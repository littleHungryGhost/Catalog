-- ============================================================================
-- iceberg_catalog.update_namespace_properties 测试用例
--
-- 前置条件：iceberg_catalog 扩展已安装
-- ============================================================================

BEGIN;

INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'test_ns', '{}'::JSONB),
       (current_database(), 'ns', '{}'::JSONB);

-- ============================================================================
-- 第一部分：参数校验 — 报错场景（先于 META 调用，不依赖 jsonb_agg）
-- ============================================================================

-- 1. p_namespace 为空字符串 → P0001
SAVEPOINT sp1;
SELECT iceberg_catalog.update_namespace_properties('', p_updates => '{"key":"val"}'::JSONB);
ROLLBACK TO SAVEPOINT sp1;

-- 2. p_namespace 为 NULL → P0001
SAVEPOINT sp2;
SELECT iceberg_catalog.update_namespace_properties(NULL::TEXT, p_updates => '{"key":"val"}'::JSONB);
ROLLBACK TO SAVEPOINT sp2;

-- 3. p_removals 和 p_updates 同时为 NULL → P0001
SAVEPOINT sp3;
SELECT iceberg_catalog.update_namespace_properties('ns');
ROLLBACK TO SAVEPOINT sp3;

-- 4. p_removals 不是 JSONB 数组 → P0001
SAVEPOINT sp4;
SELECT iceberg_catalog.update_namespace_properties('ns', p_removals => '"not_an_array"'::JSONB);
ROLLBACK TO SAVEPOINT sp4;

-- 5. p_removals 数组含非字符串元素 → P0001
SAVEPOINT sp5;
SELECT iceberg_catalog.update_namespace_properties('ns', p_removals => '[123, true]'::JSONB);
ROLLBACK TO SAVEPOINT sp5;

-- 6. p_updates 不是 JSONB object → P0001
SAVEPOINT sp6;
SELECT iceberg_catalog.update_namespace_properties('ns', p_updates => '"not_an_object"'::JSONB);
ROLLBACK TO SAVEPOINT sp6;

-- 7. removals ∩ updates ≠ ∅ → P0006
SAVEPOINT sp7;
SELECT iceberg_catalog.update_namespace_properties('ns', p_removals => '["same_key"]'::JSONB, p_updates => '{"same_key":"val"}'::JSONB);
ROLLBACK TO SAVEPOINT sp7;

-- ============================================================================
-- 第二部分：正常场景 — 返回类型与结构校验
-- ============================================================================

-- 8. 仅使用 p_updates，返回合法 JSONB
SELECT jsonb_typeof(iceberg_catalog.update_namespace_properties(
    'test_ns',
    p_updates => '{"owner": "alice"}'::JSONB
)) AS result_type;

UPDATE iceberg_catalog.namespaces
SET properties = '{"deprecated_key": "old"}'::JSONB
WHERE catalog_name = current_database()
  AND namespace = 'test_ns';

-- 2. 仅使用 p_removals，返回合法 JSONB
SELECT jsonb_typeof(iceberg_catalog.update_namespace_properties(
    'test_ns',
    p_removals => '["deprecated_key"]'::JSONB
)) AS result_type;

-- ============================================================================
-- 第二部分：正常操作 — 更新已有 Namespace 属性
-- ============================================================================

-- 3. 创建 namespace 后更新属性
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'updatable_ns', '{"owner": "bob", "region": "us"}'::JSONB);

SELECT iceberg_catalog.update_namespace_properties(
    'updatable_ns',
    p_updates => '{"owner": "carol", "env": "prod"}'::JSONB
) = '{"updated":["env","owner"],"removed":[],"missing":[]}'::JSONB AS update_response_ok;

SELECT properties = '{"owner": "carol", "region": "us", "env": "prod"}'::JSONB AS properties_updated
FROM iceberg_catalog.namespaces
WHERE catalog_name = current_database()
  AND namespace = 'updatable_ns';

-- 4. 删除属性
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'removable_ns', '{"owner": "dave", "temp": "x", "region": "eu"}'::JSONB);

SELECT iceberg_catalog.update_namespace_properties(
    'removable_ns',
    p_removals => '["temp"]'::JSONB
) = '{"updated":[],"removed":["temp"],"missing":[]}'::JSONB AS removal_response_ok;

SELECT properties = '{"owner": "dave", "region": "eu"}'::JSONB AS properties_removed
FROM iceberg_catalog.namespaces
WHERE catalog_name = current_database()
  AND namespace = 'removable_ns';

-- 5. 同时更新和删除
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'combined_ns', '{"a": "1", "b": "2", "c": "3"}'::JSONB);

SELECT iceberg_catalog.update_namespace_properties(
    'combined_ns',
    p_removals => '["a"]'::JSONB,
    p_updates  => '{"b": "updated", "d": "new"}'::JSONB
) = '{"updated":["b","d"],"removed":["a"],"missing":[]}'::JSONB AS combined_response_ok;

SELECT properties = '{"b": "updated", "c": "3", "d": "new"}'::JSONB AS properties_combined
FROM iceberg_catalog.namespaces
WHERE catalog_name = current_database()
  AND namespace = 'combined_ns';

-- ============================================================================
-- 第三部分：参数校验 — 报错场景
-- ============================================================================

-- 6. p_namespace 为空字符串 → 报错 (P0001)
SAVEPOINT sp6;
SELECT iceberg_catalog.update_namespace_properties(
    '',
    p_updates => '{"key": "val"}'::JSONB
);
ROLLBACK TO SAVEPOINT sp6;

-- 7. p_namespace 为 NULL → 报错 (P0001)
SAVEPOINT sp7;
SELECT iceberg_catalog.update_namespace_properties(
    NULL::TEXT,
    p_updates => '{"key": "val"}'::JSONB
);
ROLLBACK TO SAVEPOINT sp7;

-- 8. p_removals 和 p_updates 同时为 NULL → 报错 (P0001)
SAVEPOINT sp8;
SELECT iceberg_catalog.update_namespace_properties('ns');
ROLLBACK TO SAVEPOINT sp8;

-- ============================================================================
-- 第四部分：参数校验 — 报错场景
-- ============================================================================

-- 9. p_removals 不是 JSONB 数组 → 报错 (P0001)
SAVEPOINT sp9;
SELECT iceberg_catalog.update_namespace_properties(
    'ns',
    p_removals => '"not_an_array"'::JSONB
);
ROLLBACK TO SAVEPOINT sp9;

-- 10. p_updates 不是 JSONB object → 报错 (P0001)
SAVEPOINT sp10;
SELECT iceberg_catalog.update_namespace_properties(
    'ns',
    p_updates => '"not_an_object"'::JSONB
);
ROLLBACK TO SAVEPOINT sp10;

-- 11. removals ∩ updates ≠ ∅ → 报错 (P0006)
SAVEPOINT sp11;
SELECT iceberg_catalog.update_namespace_properties(
    'ns',
    p_removals => '["same_key"]'::JSONB,
    p_updates  => '{"same_key": "val"}'::JSONB
);
ROLLBACK TO SAVEPOINT sp11;

-- ============================================================================
-- 第五部分：边界场景
-- ============================================================================

-- 12. p_removals 为空数组（合法，无可删除的 key）
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'ns', '{}'::JSONB);

SELECT iceberg_catalog.update_namespace_properties(
    'ns',
    p_removals => '[]'::JSONB
) = '{"updated":[],"removed":[],"missing":[]}'::JSONB AS empty_removals_ok;

-- 13. p_updates 为空对象（合法，无更新的 key）
SELECT iceberg_catalog.update_namespace_properties(
    'ns',
    p_updates => '{}'::JSONB
) = '{"updated":[],"removed":[],"missing":[]}'::JSONB AS empty_updates_ok;

-- 14. 使用位置参数
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'positional_ns', '{"x": "old"}'::JSONB);

SELECT iceberg_catalog.update_namespace_properties(
    'positional_ns',
    '["x"]'::JSONB,
    '{"y": "z"}'::JSONB
) = '{"updated":["y"],"removed":["x"],"missing":[]}'::JSONB AS positional_args_ok;

ROLLBACK;

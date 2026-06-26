-- ============================================================================
-- iceberg_catalog.create_table 测试用例
--
-- 前置条件：iceberg_catalog 扩展已安装
-- ============================================================================

BEGIN;

-- Setup: create namespaces via create_namespace (also creates openGauss schemas
-- needed by iceberg_fdw for foreign table creation).
SELECT iceberg_catalog.create_namespace('test_ns', '{}'::jsonb);
SELECT iceberg_catalog.create_namespace('ns_full', '{}'::jsonb);
SELECT iceberg_catalog.create_namespace('ns_stage', '{}'::jsonb);
SELECT iceberg_catalog.create_namespace('ns_props', '{}'::jsonb);
SELECT iceberg_catalog.create_namespace('ns_binary', '{}'::jsonb);
SELECT iceberg_catalog.create_namespace('ns_fixed', '{}'::jsonb);

-- 1. 基础调用：仅填 3 个必填参数，返回合法 JSONB
SELECT jsonb_typeof(iceberg_catalog.create_table(
    'test_ns',
    'test_tbl_basic',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true},{"id":2,"name":"data","type":"string","required":false}]}'::JSONB
)) AS result_type;

-- 1.1 验证外表已创建
SELECT count(*) = 1 AS foreign_table_created
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'test_ns' AND c.relname = 'test_tbl_basic' AND c.relkind = 'f';

-- 2. 返回结构包含三个顶层 key
WITH result AS (
    SELECT iceberg_catalog.create_table(
        'test_ns',
        'test_tbl_keys',
        '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::JSONB
    ) AS value
)
SELECT value ? 'metadata-location' AS has_metadata_location,
       value ? 'metadata'          AS has_metadata,
       value ? 'config'            AS has_config
FROM result;

-- 3. 传入全部 8 个参数
SELECT iceberg_catalog.create_table(
    'ns_full',
    'tbl_full',
    '{"type":"struct","fields":[{"id":1,"name":"col1","type":"string","required":false}]}'::JSONB,
    'file:///tmp/custom-location/ns_full/tbl_full'::TEXT,
    '{"spec-id":0,"fields":[]}'::JSONB,
    '{"order-id":0,"fields":[]}'::JSONB,
    FALSE,
    '{"owner":"test"}'::JSONB
) AS create_result;

-- 4. 检查 create_table 写入的元信息表数据
SELECT count(*) = 1 AS has_table_head,
       bool_and(metadata_location IS NOT NULL AND length(metadata_location) > 0) AS has_metadata_location,
       bool_and(previous_metadata_location IS NULL) AS previous_metadata_location_is_null,
       bool_and(table_location = 'file:///tmp/custom-location/ns_full/tbl_full') AS table_location_matches,
       bool_and(last_column_id = 1) AS last_column_id_matches,
       bool_and(current_schema_id = 0) AS current_schema_id_matches,
       bool_and(default_spec_id = 0) AS default_spec_id_matches
FROM iceberg_catalog.tables_internal
WHERE namespace = 'ns_full'
  AND table_name = 'tbl_full';

SELECT count(*) = 1 AS has_schema_field,
       bool_and(field_position = 0) AS schema_position_matches,
       bool_and(field_id = 1) AS schema_field_id_matches,
       bool_and(field_name = 'col1') AS schema_field_name_matches,
       bool_and(field_required = FALSE) AS schema_required_matches,
       bool_and(field_type = 'string') AS schema_type_matches
FROM iceberg_catalog.table_schemas s
JOIN iceberg_catalog.tables_internal t
  ON s.table_uuid = t.table_uuid
WHERE t.namespace = 'ns_full'
  AND t.table_name = 'tbl_full';

SELECT count(*) = 1 AS has_partition_spec,
       bool_and(field_position = -1) AS partition_position_matches,
       bool_and(field_id IS NULL) AS partition_field_id_is_null,
       bool_and(source_id IS NULL) AS partition_source_id_is_null,
       bool_and(field_name IS NULL) AS partition_field_name_is_null,
       bool_and(transform IS NULL) AS partition_transform_is_null
FROM iceberg_catalog.partition_specs p
JOIN iceberg_catalog.tables_internal t
  ON p.table_uuid = t.table_uuid
WHERE t.namespace = 'ns_full'
  AND t.table_name = 'tbl_full';

-- 4. p_stage_create = TRUE（暂存创建）
SELECT iceberg_catalog.create_table(
    'ns_stage',
    'tbl_stage',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::JSONB,
    p_stage_create => TRUE
);

-- 5. p_namespace 为空串 → 报错
SAVEPOINT sp5;
SELECT iceberg_catalog.create_table('', 'tbl', '{"type":"struct","fields":[]}'::JSONB);
ROLLBACK TO SAVEPOINT sp5;

-- 6. p_table_name 为空串 → 报错
SAVEPOINT sp6;
SELECT iceberg_catalog.create_table('test_ns', '', '{"type":"struct","fields":[]}'::JSONB);
ROLLBACK TO SAVEPOINT sp6;

-- 7. p_schema 为 NULL → 报错
SAVEPOINT sp7;
SELECT iceberg_catalog.create_table('test_ns', 'tbl_null_schema', NULL::JSONB);
ROLLBACK TO SAVEPOINT sp7;

-- 8. p_properties 传入空对象
SELECT iceberg_catalog.create_table(
    'ns_props',
    'tbl_props',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::JSONB,
    p_properties => '{}'::JSONB
);

-- 9. binary 类型字段
SELECT iceberg_catalog.create_table(
    'ns_binary',
    'bin_tbl',
    '{"type":"struct","fields":[
        {"id":1,"name":"id","type":"long","required":true},
        {"id":2,"name":"blob","type":"binary","required":false}
    ]}'::JSONB
);

-- 10. fixed 类型字段
SELECT iceberg_catalog.create_table(
    'ns_fixed',
    'fix_tbl',
    '{"type":"struct","fields":[
        {"id":1,"name":"id","type":"long","required":true},
        {"id":2,"name":"hash","type":"fixed[16]","required":false}
    ]}'::JSONB
);

-- 11. 验证最后一个外表也存在
SELECT count(*) = 1 AS foreign_table_exists
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'ns_props' AND c.relname = 'tbl_props' AND c.relkind = 'f';

ROLLBACK;

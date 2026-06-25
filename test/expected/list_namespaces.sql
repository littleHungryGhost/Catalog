-- ============================================================================
-- iceberg_catalog.list_namespaces 测试用例
--
-- 前置条件：iceberg_catalog 扩展已安装
-- ============================================================================
BEGIN;
BEGIN
-- ============================================================================
-- 第一部分：正常场景 — 返回类型与结构校验
-- ============================================================================
-- 1. 默认参数调用，返回合法 JSONB
SELECT jsonb_typeof(iceberg_catalog.list_namespaces()) AS result_type;
 result_type 
-------------
 object
(1 row)
-- 2. 返回结构包含 "namespaces" 和 "next-page-token" 两个顶层 key
SELECT
    iceberg_catalog.list_namespaces() ? 'namespaces'       AS has_namespaces,
    iceberg_catalog.list_namespaces() ? 'next-page-token'  AS has_next_page_token;
 has_namespaces | has_next_page_token 
----------------+---------------------
 t              | t
(1 row)
-- 3. "namespaces" 字段应为数组
SELECT jsonb_typeof(iceberg_catalog.list_namespaces() -> 'namespaces') AS namespaces_type;
 namespaces_type 
-----------------
 array
(1 row)
-- 4. 首页 next-page-token 存在（空 catalog 返回 null）
SELECT iceberg_catalog.list_namespaces() -> 'next-page-token' AS next_token;
 next_token 
------------
 null
(1 row)
-- ============================================================================
-- 第二部分：参数组合
-- ============================================================================
-- 5. 指定 p_parent = NULL（列出顶层 namespace，默认行为）
SELECT iceberg_catalog.list_namespaces(p_parent => NULL);
               list_namespaces               
---------------------------------------------
 {"namespaces": [], "next-page-token": null}
(1 row)
-- 6. 指定 p_page_size
SELECT iceberg_catalog.list_namespaces(p_page_size => 50);
               list_namespaces               
---------------------------------------------
 {"namespaces": [], "next-page-token": null}
(1 row)
-- 7. 使用位置参数
SELECT iceberg_catalog.list_namespaces(NULL, 100, NULL);
               list_namespaces               
---------------------------------------------
 {"namespaces": [], "next-page-token": null}
(1 row)
-- 8. 指定 p_page_token（分页）
SELECT iceberg_catalog.list_namespaces(
    p_page_token => 'eyJ2IjoxLCJ0eXBlIjoibmFtZXNwYWNlIiwibGFzdCI6ImFjY291bnRpbmcifQ=='
);
               list_namespaces               
---------------------------------------------
 {"namespaces": [], "next-page-token": null}
(1 row)
-- 9. 全部参数使用命名传参
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'accounting', '{}'::JSONB);
INSERT 0 1
SELECT iceberg_catalog.list_namespaces(
    p_parent     => 'accounting',
    p_page_size  => 20,
    p_page_token => NULL
);
               list_namespaces               
---------------------------------------------
 {"namespaces": [], "next-page-token": null}
(1 row)
-- ============================================================================
-- 第三部分：参数校验 — 报错场景
-- ============================================================================
-- 10. p_page_size = 0 → 报错 (P0001)
SAVEPOINT sp10;
SAVEPOINT
SELECT iceberg_catalog.list_namespaces(p_page_size => 0);
gsql:test/sql/list_namespaces.sql:61: ERROR:  pageSize must be >= 1
CONTEXT:  referenced column: list_namespaces
ROLLBACK TO SAVEPOINT sp10;
ROLLBACK
-- 11. p_page_size = -1 → 报错 (P0001)
SAVEPOINT sp11;
SAVEPOINT
SELECT iceberg_catalog.list_namespaces(p_page_size => -1);
gsql:test/sql/list_namespaces.sql:66: ERROR:  pageSize must be >= 1
CONTEXT:  referenced column: list_namespaces
ROLLBACK TO SAVEPOINT sp11;
ROLLBACK
-- ============================================================================
-- 第四部分：Parent namespace 不存在 — 报错场景
-- ============================================================================
-- 12. p_parent 指定的父级 Namespace 不存在 → 报错 (P0004)
SAVEPOINT sp12;
SAVEPOINT
SELECT iceberg_catalog.list_namespaces(p_parent => 'non_existent_parent');
gsql:test/sql/list_namespaces.sql:75: ERROR:  The given namespace does not exist
CONTEXT:  referenced column: list_namespaces
ROLLBACK TO SAVEPOINT sp12;
ROLLBACK
-- ============================================================================
-- 第五部分：边界场景
-- ============================================================================
-- 13. p_page_size 为大值
SELECT iceberg_catalog.list_namespaces(p_page_size => 1000000) @>
       '{"namespaces":[["accounting"]]}'::JSONB AS contains_accounting;
 contains_accounting 
---------------------
 t
(1 row)
-- 14. p_page_size = 1（最小值合法）
SELECT iceberg_catalog.list_namespaces(p_page_size => 1) -> 'namespaces' =
       '[["accounting"]]'::JSONB AS first_page_is_accounting;
 first_page_is_accounting 
--------------------------
 t
(1 row)
-- 15. 插入 namespace 后调用 list，应包含已插入的 namespace
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'dept_a', '{}'::JSONB);
INSERT 0 1
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'dept_b', '{"owner": "alice"}'::JSONB);
INSERT 0 1
SELECT iceberg_catalog.list_namespaces() @>
       '{"namespaces":[["accounting"],["dept_a"],["dept_b"]]}'::JSONB AS contains_inserted_namespaces;
 contains_inserted_namespaces 
------------------------------
 t
(1 row)
WITH first_page AS (
    SELECT iceberg_catalog.list_namespaces(NULL, 2, NULL) AS result
)
SELECT
    jsonb_array_length(result -> 'namespaces') AS namespace_count,
    jsonb_typeof(result -> 'next-page-token') AS next_token_type
FROM first_page;
 namespace_count | next_token_type 
-----------------+-----------------
               2 | string
(1 row)
WITH first_page AS (
    SELECT iceberg_catalog.list_namespaces(NULL, 2, NULL) AS result
)
SELECT iceberg_catalog.list_namespaces(
    NULL,
    2,
    result ->> 'next-page-token'
) @> '{"namespaces":[["dept_b"]]}'::JSONB AS second_page_contains_dept_b
FROM first_page;
 second_page_contains_dept_b 
-----------------------------
 t
(1 row)
ROLLBACK;
ROLLBACK

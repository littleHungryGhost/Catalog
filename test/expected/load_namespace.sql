-- ============================================================================
-- iceberg_catalog.load_namespace tests
-- ============================================================================
BEGIN;
BEGIN
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'test_ns', '{}'::JSONB);
INSERT 0 1
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'sales', '{}'::JSONB);
INSERT 0 1
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'ns-with-dash', '{}'::JSONB);
INSERT 0 1
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'ns_with_underscore', '{}'::JSONB);
INSERT 0 1
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'NS123MixedCase', '{}'::JSONB);
INSERT 0 1
-- 1. Returns JSONB object
SELECT jsonb_typeof(iceberg_catalog.load_namespace('test_ns')) AS result_type;
 result_type 
-------------
 object
(1 row)
-- 2. Response contains namespace and properties keys
SELECT
    iceberg_catalog.load_namespace('test_ns') ? 'namespace'  AS has_namespace,
    iceberg_catalog.load_namespace('test_ns') ? 'properties' AS has_properties;
 has_namespace | has_properties 
---------------+----------------
 t             | t
(1 row)
-- 3. Namespace field is an array containing the requested namespace
SELECT
    jsonb_typeof(iceberg_catalog.load_namespace('sales') -> 'namespace') AS namespace_type,
    (iceberg_catalog.load_namespace('sales') -> 'namespace' -> 0)        AS first_element;
 namespace_type | first_element 
----------------+---------------
 array          | "sales"
(1 row)
-- 4. Existing namespace returns stored properties
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'accounting', '{"owner": "Ralph", "created_at": "1452120468"}'::JSONB);
INSERT 0 1
SELECT iceberg_catalog.load_namespace('accounting') =
       '{"namespace":["accounting"],"properties":{"owner":"Ralph","created_at":"1452120468"}}'::JSONB
       AS accounting_matches;
 accounting_matches 
--------------------
 t
(1 row)
-- 5. Existing namespace with empty properties
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'empty_props_ns', '{}'::JSONB);
INSERT 0 1
SELECT iceberg_catalog.load_namespace('empty_props_ns') =
       '{"namespace":["empty_props_ns"],"properties":{}}'::JSONB
       AS empty_props_matches;
 empty_props_matches 
---------------------
 t
(1 row)
-- 6. Empty namespace argument errors
SAVEPOINT sp6;
SAVEPOINT
SELECT iceberg_catalog.load_namespace('');
gsql:test/sql/load_namespace.sql:49: ERROR:  namespace must not be empty
CONTEXT:  referenced column: load_namespace
ROLLBACK TO SAVEPOINT sp6;
ROLLBACK
-- 7. NULL namespace argument errors
SAVEPOINT sp7;
SAVEPOINT
SELECT iceberg_catalog.load_namespace(NULL::TEXT);
gsql:test/sql/load_namespace.sql:54: ERROR:  namespace must not be empty
CONTEXT:  referenced column: load_namespace
ROLLBACK TO SAVEPOINT sp7;
ROLLBACK
-- 8. Missing namespace errors
SAVEPOINT sp8;
SAVEPOINT
SELECT iceberg_catalog.load_namespace('non_existent_namespace');
gsql:test/sql/load_namespace.sql:59: ERROR:  The given namespace does not exist
CONTEXT:  referenced column: load_namespace
ROLLBACK TO SAVEPOINT sp8;
ROLLBACK
-- 9. Names with dash, underscore, and mixed case
SELECT iceberg_catalog.load_namespace('ns-with-dash') -> 'namespace' ->> 0 AS dash_name;
  dash_name   
--------------
 ns-with-dash
(1 row)
SELECT iceberg_catalog.load_namespace('ns_with_underscore') -> 'namespace' ->> 0 AS underscore_name;
  underscore_name  
-------------------
 ns_with_underscore
(1 row)
SELECT iceberg_catalog.load_namespace('NS123MixedCase') -> 'namespace' ->> 0 AS mixed_case_name;
 mixed_case_name 
-----------------
 NS123MixedCase
(1 row)
-- 10. c##-prefixed namespace
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'c##special', '{"env": "test"}'::JSONB);
INSERT 0 1
SELECT iceberg_catalog.load_namespace('c##special') =
       '{"namespace":["c##special"],"properties":{"env":"test"}}'::JSONB
       AS special_matches;
 special_matches 
-----------------
 t
(1 row)
ROLLBACK;
ROLLBACK

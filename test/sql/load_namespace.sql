-- ============================================================================
-- iceberg_catalog.load_namespace tests
-- ============================================================================

BEGIN;

INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'test_ns', '{}'::JSONB);
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'sales', '{}'::JSONB);
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'ns-with-dash', '{}'::JSONB);
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'ns_with_underscore', '{}'::JSONB);
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'NS123MixedCase', '{}'::JSONB);

-- 1. Returns JSONB object
SELECT jsonb_typeof(iceberg_catalog.load_namespace('test_ns')) AS result_type;

-- 2. Response contains namespace and properties keys
SELECT
    iceberg_catalog.load_namespace('test_ns') ? 'namespace'  AS has_namespace,
    iceberg_catalog.load_namespace('test_ns') ? 'properties' AS has_properties;

-- 3. Namespace field is an array containing the requested namespace
SELECT
    jsonb_typeof(iceberg_catalog.load_namespace('sales') -> 'namespace') AS namespace_type,
    (iceberg_catalog.load_namespace('sales') -> 'namespace' -> 0)        AS first_element;

-- 4. Existing namespace returns stored properties
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'accounting', '{"owner": "Ralph", "created_at": "1452120468"}'::JSONB);

SELECT iceberg_catalog.load_namespace('accounting') =
       '{"namespace":["accounting"],"properties":{"owner":"Ralph","created_at":"1452120468"}}'::JSONB
       AS accounting_matches;

-- 5. Existing namespace with empty properties
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'empty_props_ns', '{}'::JSONB);

SELECT iceberg_catalog.load_namespace('empty_props_ns') =
       '{"namespace":["empty_props_ns"],"properties":{}}'::JSONB
       AS empty_props_matches;

-- 6. Empty namespace argument errors
SAVEPOINT sp6;
SELECT iceberg_catalog.load_namespace('');
ROLLBACK TO SAVEPOINT sp6;

-- 7. NULL namespace argument errors
SAVEPOINT sp7;
SELECT iceberg_catalog.load_namespace(NULL::TEXT);
ROLLBACK TO SAVEPOINT sp7;

-- 8. Missing namespace errors
SAVEPOINT sp8;
SELECT iceberg_catalog.load_namespace('non_existent_namespace');
ROLLBACK TO SAVEPOINT sp8;

-- 9. Names with dash, underscore, and mixed case
SELECT iceberg_catalog.load_namespace('ns-with-dash') -> 'namespace' ->> 0 AS dash_name;
SELECT iceberg_catalog.load_namespace('ns_with_underscore') -> 'namespace' ->> 0 AS underscore_name;
SELECT iceberg_catalog.load_namespace('NS123MixedCase') -> 'namespace' ->> 0 AS mixed_case_name;

-- 10. c##-prefixed namespace
INSERT INTO iceberg_catalog.namespaces(catalog_name, namespace, properties)
VALUES (current_database(), 'c##special', '{"env": "test"}'::JSONB);

SELECT iceberg_catalog.load_namespace('c##special') =
       '{"namespace":["c##special"],"properties":{"env":"test"}}'::JSONB
       AS special_matches;

ROLLBACK;

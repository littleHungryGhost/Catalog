BEGIN;
SELECT iceberg_catalog.drop_namespace('dropcreate_ns');
COMMIT;

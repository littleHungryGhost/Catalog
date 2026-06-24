BEGIN;
SELECT iceberg_catalog.create_namespace('race_ns', '{}'::JSONB);
COMMIT;

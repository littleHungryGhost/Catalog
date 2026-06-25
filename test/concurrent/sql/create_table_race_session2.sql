BEGIN;
SELECT iceberg_catalog.create_table(
    'race_ns',
    'race_tbl',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::JSONB
);
COMMIT;

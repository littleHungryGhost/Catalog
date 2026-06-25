BEGIN;
SELECT iceberg_catalog.create_table(
    'dropcreate_ns',
    'new_tbl',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::JSONB
);
COMMIT;

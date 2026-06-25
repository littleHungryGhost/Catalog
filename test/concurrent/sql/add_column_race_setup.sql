DROP DATABASE IF EXISTS iceberg_concur_test;
CREATE DATABASE iceberg_concur_test;
\c iceberg_concur_test
CREATE EXTENSION iceberg_fdw;
CREATE EXTENSION iceberg_catalog;

SELECT iceberg_catalog.create_namespace('addcol_ns', '{}'::JSONB);
SELECT iceberg_catalog.create_table(
    'addcol_ns',
    'addcol_tbl',
    '{"type":"struct","fields":[{"id":1,"name":"id","type":"long","required":true}]}'::JSONB
);

DROP DATABASE IF EXISTS iceberg_concur_test;
CREATE DATABASE iceberg_concur_test;
\c iceberg_concur_test
CREATE EXTENSION iceberg_fdw;
CREATE EXTENSION iceberg_catalog;

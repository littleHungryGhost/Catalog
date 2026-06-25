BEGIN;
SELECT iceberg_catalog.load_table('read_ns', 'read_tbl');
SELECT iceberg_catalog.is_table_existed('read_ns', 'read_tbl');
SELECT iceberg_catalog.load_table('read_ns', 'read_tbl');
SELECT iceberg_catalog.is_table_existed('read_ns', 'read_tbl');
COMMIT;

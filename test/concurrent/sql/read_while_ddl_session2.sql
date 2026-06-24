BEGIN;
SELECT iceberg_catalog.add_column('read_ns', 'read_tbl', 'new_col', 'string');
COMMIT;

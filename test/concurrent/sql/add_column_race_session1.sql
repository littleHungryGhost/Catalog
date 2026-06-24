BEGIN;
SELECT iceberg_catalog.add_column('addcol_ns', 'addcol_tbl', 'col_a', 'string');
COMMIT;

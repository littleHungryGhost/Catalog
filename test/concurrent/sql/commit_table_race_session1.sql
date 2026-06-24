BEGIN;
SELECT iceberg_catalog.commit_table(
    'commit_ns',
    'commit_tbl',
    '[{"type":"assert-ref-snapshot-id","ref":"main","snapshot-id":0}]'::JSONB,
    '[{"action":"add-snapshot","snapshot":{"snapshot-id":1,"timestamp-ms":2000000000000,"manifest-list":"s3://bucket/tbl/metadata/snap-1.avro","summary":{"operation":"append"}}}]'::JSONB
);
COMMIT;

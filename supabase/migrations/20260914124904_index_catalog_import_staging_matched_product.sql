create index if not exists idx_catalog_import_staging_matched_product_id on private.catalog_import_staging(matched_product_id) where matched_product_id is not null;

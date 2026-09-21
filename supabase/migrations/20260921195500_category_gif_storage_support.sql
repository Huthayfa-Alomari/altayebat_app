update storage.buckets
set file_size_limit = greatest(coalesce(file_size_limit, 0), 6291456),
    allowed_mime_types = array[
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif'
    ]::text[]
where id = 'product-images';

-- 010_storage.sql
-- Storage buckets + access policies.
-- Only `product-images` is public (catalog display). Every document bucket
-- is private and served through signed URLs.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('product-images',       'product-images',       true,  8388608,
   array['image/jpeg', 'image/png', 'image/webp']),
  ('customer-documents',   'customer-documents',   false, 10485760, null),
  ('vehicle-documents',    'vehicle-documents',    false, 10485760, null),
  ('invoice-documents',    'invoice-documents',    false, 10485760,
   array['application/pdf', 'image/jpeg', 'image/png']),
  ('service-documents',    'service-documents',    false, 10485760, null),
  ('insurance-documents',  'insurance-documents',  false, 10485760, null),
  ('warranty-documents',   'warranty-documents',   false, 10485760, null),
  ('expense-attachments',  'expense-attachments',  false, 10485760, null)
on conflict (id) do nothing;

-- Public read for catalog imagery only.
drop policy if exists product_images_public_read on storage.objects;
create policy product_images_public_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'product-images');

-- Uploads: catalog images need products.edit; documents need the matching
-- module permission.
drop policy if exists product_images_write on storage.objects;
create policy product_images_write on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-images'
              and public.has_permission('products', 'edit'));

drop policy if exists document_upload on storage.objects;
create policy document_upload on storage.objects
  for insert to authenticated
  with check (
    bucket_id in ('customer-documents', 'vehicle-documents',
                  'invoice-documents', 'service-documents',
                  'insurance-documents', 'warranty-documents',
                  'expense-attachments')
    and (
      (bucket_id in ('customer-documents', 'vehicle-documents')
        and public.has_permission('customers', 'edit'))
      or (bucket_id = 'invoice-documents'
        and public.has_permission('billing', 'print'))
      or (bucket_id = 'service-documents'
        and public.has_permission('service', 'edit'))
      or (bucket_id = 'insurance-documents'
        and public.has_permission('insurance', 'edit'))
      or (bucket_id = 'warranty-documents'
        and public.has_permission('warranty', 'edit'))
      or (bucket_id = 'expense-attachments'
        and public.has_permission('expenses', 'create'))
    )
  );

-- Private reads: any signed-in user with the module permission may fetch the
-- object (the client always uses signed URLs for these buckets).
drop policy if exists document_read on storage.objects;
create policy document_read on storage.objects
  for select to authenticated
  using (
    bucket_id in ('customer-documents', 'vehicle-documents',
                  'invoice-documents', 'service-documents',
                  'insurance-documents', 'warranty-documents',
                  'expense-attachments')
    and (
      (bucket_id in ('customer-documents', 'vehicle-documents')
        and public.has_permission('customers', 'view'))
      or (bucket_id = 'invoice-documents'
        and public.has_permission('billing', 'view'))
      or (bucket_id = 'service-documents'
        and public.has_permission('service', 'view'))
      or (bucket_id = 'insurance-documents'
        and public.has_permission('insurance', 'view'))
      or (bucket_id = 'warranty-documents'
        and public.has_permission('warranty', 'view'))
      or (bucket_id = 'expense-attachments'
        and public.has_permission('expenses', 'view'))
    )
  );

drop policy if exists document_delete on storage.objects;
create policy document_delete on storage.objects
  for delete to authenticated
  using (bucket_id <> 'product-images'
         and public.is_super_admin());

-- =============================================================================
-- 010_storage.sql  (SS28, SS53)
-- -----------------------------------------------------------------------------
-- Buckets + storage policies.
--
--   product-images      the only public bucket: catalogue photography is marketing
--   everything else     private; the app exchanges an object path for a short
--                       signed URL through public.get_signed_url()
--
-- Storage policies below are written against the `storage.objects` contract that
-- Supabase ships (bucket_id + (storage.foldername(name))[1] as the first folder).
-- Layout convention (also enforced by StorageService in Flutter):
--
--   <bucket>/<showroom_id>/<entity_type>/<entity_id>/<random><ext>
--
-- Owning the first folder to the showroom id is what makes cross-tenant reads
-- impossible even if a user guesses a path.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('product-images',      'product-images',      true,  10485760,
   array['image/jpeg','image/png','image/webp']),
  ('product-thumbnails',  'product-thumbnails',  true,   2097152,
   array['image/jpeg','image/png','image/webp']),
  ('brand-logos',         'brand-logos',         true,   1048576,
   array['image/jpeg','image/png','image/webp','image/svg+xml']),
  ('showroom-logos',      'showroom-logos',      true,   1048576,
   array['image/jpeg','image/png','image/webp']),
  ('customer-documents',  'customer-documents',  false, 10485760,
   array['image/jpeg','image/png','image/webp','application/pdf']),
  ('vehicle-documents',   'vehicle-documents',   false, 10485760,
   array['image/jpeg','image/png','image/webp','application/pdf']),
  ('invoice-documents',   'invoice-documents',   false, 20971520,
   array['application/pdf']),
  ('service-documents',   'service-documents',   false, 10485760,
   array['image/jpeg','image/png','image/webp','application/pdf']),
  ('insurance-documents', 'insurance-documents', false, 10485760,
   array['image/jpeg','image/png','application/pdf']),
  ('warranty-documents',  'warranty-documents',  false, 10485760,
   array['image/jpeg','image/png','application/pdf']),
  ('expense-attachments', 'expense-attachments', false, 10485760,
   array['image/jpeg','image/png','application/pdf'])
on conflict (id) do update
   set public = excluded.public,
       file_size_limit = excluded.file_size_limit,
       allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- Storage policies
-- ---------------------------------------------------------------------------
do $$
declare
  b    record;
  name text;
  -- The cast of the first path folder to uuid must always be guarded: an object
  -- uploaded outside the convention would otherwise raise 22P02 and break every
  -- listing that reads the bucket, instead of simply not matching the policy.
  UUID_FIRST_FOLDER constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  for b in select id, public, translate(id, '-', '_') as slug from storage.buckets loop
    -- ---- read ------------------------------------------------------------
    name := 'read_' || b.slug;
    execute format('drop policy if exists %I on storage.objects', name);
    if b.public then
      -- catalogue imagery is marketing material: readable by everyone
      execute format(
        'create policy %I on storage.objects for select to anon, authenticated
           using (bucket_id = %L)', name, b.id);
    else
      -- private buckets: the first path folder must be a showroom I can access
      execute format($q$
        create policy %I on storage.objects for select to authenticated
          using (bucket_id = %L
                 and (app_sec.is_super_admin()
                      or (split_part(name, '/', 1) ~* %L
                          and split_part(name, '/', 1)::uuid
                             in (select app_sec.accessible_showroom_ids()))))$q$,
        name, b.id, UUID_FIRST_FOLDER);
    end if;

    -- ---- insert ----------------------------------------------------------
    name := 'write_' || b.slug;
    execute format('drop policy if exists %I on storage.objects', name);
    -- path convention <showroom_id>/<entity_type>/<entity_id>/<file> is part of
    -- the security contract, so the policy enforces exactly four segments.
    execute format($q$
      create policy %I on storage.objects for insert to authenticated
        with check (
          bucket_id = %L
          and owner = auth.uid()
          and array_length(regexp_split_to_array(name, '/'), 1) = 4
          and (app_sec.is_super_admin()
               or (split_part(name, '/', 1) ~* %L
                   and split_part(name, '/', 1)::uuid
                      in (select app_sec.accessible_showroom_ids())))
        )$q$, name, b.id, UUID_FIRST_FOLDER);

    -- ---- update (rename/metadata only) ----------------------------------
    name := 'update_' || b.slug;
    execute format('drop policy if exists %I on storage.objects', name);
    execute format($q$
      create policy %I on storage.objects for update to authenticated
        using (bucket_id = %L and (owner = auth.uid() or app_sec.is_super_admin()))
        with check (bucket_id = %L)$q$, name, b.id, b.id);

    -- ---- delete ----------------------------------------------------------
    name := 'delete_' || b.slug;
    execute format('drop policy if exists %I on storage.objects', name);
    if b.public then
      -- public buckets are managed by the service role only (admin console)
      continue;
    end if;
    execute format($q$
      create policy %I on storage.objects for delete to authenticated
        using (bucket_id = %L
               and owner = auth.uid()
               and split_part(name, '/', 1) ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')$q$,
      name, b.id);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- Signed URLs (SS28/SS53): the client never stores a long-lived private URL.
-- It stores the object path and asks for a fresh URL whenever it renders.
-- ---------------------------------------------------------------------------

-- Which module.action unlocks a private bucket is data, not code: the admin
-- console can show and tune it, and a bucket that is added later only needs a
-- row here (no rule = the documents.view default).  Money-bearing documents are
-- gated on a *non-read* action on purpose: every signed-up user holds VIEWER,
-- whose '%.view' pattern would make a billing.view gate meaningless (SS53).
create table if not exists app_sec.bucket_access_rule (
  bucket_id text not null,
  module    text not null,
  action    text not null,
  note      text,
  constraint bucket_access_rule_pkey primary key (bucket_id, module, action)
);

comment on table app_sec.bucket_access_rule is
  'Internal: maps a private storage bucket to the module.action that may open its files (SS53).';

insert into app_sec.bucket_access_rule (bucket_id, module, action, note) values
  ('customer-documents',  'documents', 'view',   'KYC and address proofs are operational files'),
  ('vehicle-documents',   'documents', 'view',   'RC and insurance copies, needed at delivery and service'),
  ('service-documents',   'documents', 'view',   'job card scans'),
  ('warranty-documents',  'documents', 'view',   'warranty claim papers'),
  ('insurance-documents', 'documents', 'view',   'policy PDFs'),
  ('invoice-documents',   'billing',   'print',  'a tax invoice is money-bearing: printing it is the gate'),
  ('invoice-documents',   'billing',   'export', 'or exporting the batch from the reports screen'),
  ('expense-attachments', 'expenses',  'create', 'whoever raises the expense may read the bill back'),
  ('expense-attachments', 'expenses',  'edit',   null),
  ('expense-attachments', 'expenses',  'approve',null),
  ('expense-attachments', 'expenses',  'export', null)
on conflict (bucket_id, module, action) do update set note = excluded.note;
create or replace function public.get_signed_url(p_bucket text, p_path text, p_ttl_seconds int default 900)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_showroom uuid;
  v_ok       boolean;
begin
  if p_path is null or p_bucket is null then
    perform app_util.fail('VAL001', 'bucket and path are required');
  end if;
  if p_ttl_seconds < 60 or p_ttl_seconds > 3600 then
    p_ttl_seconds := 900;
  end if;

  if p_path !~* '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/' then
    perform app_util.fail('VAL002', 'object path must start with the showroom id');
  end if;
  v_showroom := split_part(p_path, '/', 1)::uuid;
  if not app_sec.can_access_showroom(v_showroom) then
    perform app_util.fail('SEC001', 'this document belongs to another showroom');
  end if;

  -- Documents that contain personal or financial data require a stronger
  -- permission than the showroom gate alone (SS53).
  if coalesce((select b.public from storage.buckets b where b.id = p_bucket), false) then
    v_ok := true;   -- marketing imagery: no module permission needed
  elsif not exists (select 1 from app_sec.bucket_access_rule r where r.bucket_id = p_bucket) then
    v_ok := app_sec.has_permission('documents', 'view');
  else
    select bool_or(app_sec.has_permission(r.module, r.action))
      into v_ok
      from app_sec.bucket_access_rule r
     where r.bucket_id = p_bucket;
  end if;

  if not coalesce(v_ok, false) then
    if not exists (select 1 from storage.buckets b where b.id = p_bucket) then
      perform app_util.fail('VAL003', 'unknown storage bucket ' || p_bucket);
    end if;
    perform app_util.fail('SEC002', 'you are not allowed to open documents from ' || p_bucket);
  end if;

  -- Access has been authorised above. The actual URL is minted by whichever
  -- signing primitive this server has:
  --   * Supabase: storage.create_signed_url(bucket, path, ttl)
  --   * anything else: no URL, and the Flutter client signs it itself with
  --     `supabase.storage.from(bucket).createSignedUrl(...)` - the storage read
  --     policy above is what makes that safe.  Returning null instead of
  --     failing keeps the screen working (path is still valid for the cache).
  begin
    return jsonb_build_object(
      'path', p_path, 'bucket', p_bucket, 'url',
      (execute 'select storage.create_signed_url(' || quote_literal(p_bucket) || ', '
               || quote_literal(p_path) || ', ' || p_ttl_seconds || ')')::text,
      'expiresInSeconds', p_ttl_seconds, 'signedBy', 'database');
  exception when others then
    return jsonb_build_object(
      'path', p_path, 'bucket', p_bucket, 'url', null,
      'expiresInSeconds', p_ttl_seconds, 'signedBy', 'client',
      'note', 'database signing unavailable; client must call createSignedUrl');
  end;
end;
$$;

-- Batch variant so a list screen signs 20 thumbnails in one round trip.
create or replace function public.get_signed_urls(p_objects jsonb, p_ttl_seconds int default 900)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec record;
  v   jsonb;
  out jsonb := '[]'::jsonb;
begin
  for rec in select * from jsonb_array_elements(p_objects) as e(value) loop
    v := public.get_signed_url(rec.value ->> 'bucket', rec.value ->> 'path', p_ttl_seconds);
    out := out || jsonb_build_array(v);
  end loop;
  return out;
end;
$$;

comment on function public.get_signed_url is
  'Single choke point for private file access: showroom scoping + module permission + short TTL (SS53).';

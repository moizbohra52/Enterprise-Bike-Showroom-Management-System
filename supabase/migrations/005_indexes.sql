-- 005_indexes.sql
-- Read-path indexes: every tenant filter, every FK used in list queries and
-- the date columns used by dashboards/reports, plus trigram indexes for the
-- global search box.

-- tenancy
create index if not exists inventory_showroom_idx    on public.inventory (showroom_id);
create index if not exists customers_showroom_idx    on public.customers (showroom_id);
create index if not exists sales_showroom_date_idx   on public.sales (showroom_id, sale_date desc);
create index if not exists invoices_showroom_idx     on public.invoices (showroom_id);
create index if not exists payments_showroom_date_idx on public.payments (showroom_id, payment_date desc);
create index if not exists loans_showroom_idx        on public.loans (showroom_id);
create index if not exists purchases_showroom_idx    on public.purchases (showroom_id);
create index if not exists expenses_showroom_date_idx on public.expenses (showroom_id, date desc);
create index if not exists service_showroom_idx      on public.service_records (showroom_id);
create index if not exists reminders_showroom_idx    on public.reminders (showroom_id, reminder_date);
create index if not exists notifications_showroom_idx on public.notifications (showroom_id, created_at desc);
create index if not exists audit_showroom_idx        on public.audit_logs (showroom_id, created_at desc);

-- relationships used by embedded selects
create index if not exists sale_items_sale_idx       on public.sale_items (sale_id);
create index if not exists invoice_items_invoice_idx on public.invoice_items (invoice_id);
create index if not exists purchase_items_purchase_idx on public.purchase_items (purchase_id);
create index if not exists service_items_service_idx on public.service_items (service_id);
create index if not exists emi_loan_idx              on public.emi_schedules (loan_id, installment_no);
create index if not exists vehicles_customer_idx     on public.customer_vehicles (customer_id);
create index if not exists vehicles_inventory_idx    on public.customer_vehicles (inventory_id);
create index if not exists free_service_grants_vehicle_idx on public.free_service_grants (vehicle_id);
create index if not exists emi_plans_product_idx on public.emi_plans (product_id);
create index if not exists product_accessories_product_idx on public.product_accessories (product_id);
create index if not exists warranties_vehicle_idx    on public.warranties (vehicle_id);
create index if not exists claims_warranty_idx       on public.warranty_claims (warranty_id);
create index if not exists insurance_vehicle_idx     on public.insurance_policies (vehicle_id);
create index if not exists payments_invoice_idx      on public.payments (invoice_id);
create index if not exists payments_sale_idx         on public.payments (sale_id);
create index if not exists payments_loan_idx         on public.payments (loan_id);
create index if not exists payments_customer_idx     on public.payments (customer_id);
create index if not exists invoices_customer_idx     on public.invoices (customer_id);
create index if not exists invoices_sale_idx         on public.invoices (sale_id);
create index if not exists inventory_product_idx     on public.inventory (product_id);
create index if not exists product_colors_product_idx on public.product_colors (product_id);
create index if not exists product_images_product_idx on public.product_images (product_id);
create index if not exists user_roles_user_idx       on public.user_roles (user_id);
create index if not exists role_permissions_role_idx on public.role_permissions (role_id);
create index if not exists attachments_entity_idx    on public.attachments (entity_type, entity_id);

-- status / date driven worklists
create index if not exists emi_due_idx        on public.emi_schedules (due_date) where status = 'pending';
create index if not exists invoices_unpaid_idx on public.invoices (status) where status in ('unpaid', 'partial', 'overdue');
create index if not exists service_open_idx   on public.service_records (status) where status in ('open', 'in_progress');
create index if not exists reminders_pending_idx on public.reminders (reminder_date) where status = 'pending';
create index if not exists inventory_status_idx on public.inventory (showroom_id, status);
create index if not exists stock_history_inventory_idx on public.stock_history (inventory_id);
create index if not exists stock_transfers_from_idx on public.stock_transfers (from_showroom_id, transfer_date desc);
create index if not exists expenses_pending_idx on public.expenses (status) where status = 'pending';
create index if not exists notifications_unread_idx on public.notifications (user_id, is_read);

-- global search (pg_trgm)
create index if not exists customers_name_trgm_idx
  on public.customers using gin (name extensions.gin_trgm_ops);
create index if not exists customers_phone_idx
  on public.customers (phone);
create index if not exists products_name_trgm_idx
  on public.products using gin (name extensions.gin_trgm_ops);
create index if not exists inventory_chassis_trgm_idx
  on public.inventory using gin (chassis_number extensions.gin_trgm_ops);
create index if not exists vehicles_registration_idx
  on public.customer_vehicles (registration_number);

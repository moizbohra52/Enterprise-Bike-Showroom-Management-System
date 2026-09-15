-- =============================================================================
-- 002_sales_flow.sql  -  the money path, end to end
-- -----------------------------------------------------------------------------
-- Everything here goes through the exact RPC surface the Flutter repositories
-- call, under the `authenticated` role, so it proves the whole stack together:
-- policies -> permission checks -> business rules -> triggers -> roll-ups ->
-- journals -> reporting views.  Amounts are asserted as recomputed from the
-- database, never copied from a screenshot.
-- =============================================================================

reset role;
set plpgsql.check_asserts = off;

-- ---------------------------------------------------------------------------
-- Reference rows (created by the superuser because stock references the seeded
-- catalogue; the sale itself is created by the API exactly as the app does)
-- ---------------------------------------------------------------------------
do $$
declare v_prod uuid; v_color uuid; v_shr uuid;
begin
  select id into v_shr from public.showrooms where code = 'TST-BLR';
  select id into v_prod from public.products where model = 'Shine 125' and variant = 'DX Smart';
  if v_prod is null then
    raise exception 'seed data missing: expected Honda Shine 125 in the catalogue';
  end if;
  select id into v_color from public.product_colors where product_id = v_prod limit 1;
  perform test.remember('blr', v_shr::text);
  perform test.remember('product', v_prod::text);
  perform test.remember('color', coalesce(v_color::text, ''));
end
$$;

-- ---------------------------------------------------------------------------
-- Stock: three units in via the documented RPC
-- ---------------------------------------------------------------------------
set role authenticated;
select test.as('a0000000-0000-0000-0000-000000000001'::uuid, test.uuid_of('blr'));

do $$
declare i int; v jsonb; ids uuid[] := '{}';
begin
  for i in 1..3 loop
    v := public.create_inventory_unit(jsonb_build_object(
          'showroom_id', test.uuid_of('blr'),
          'product_id',  test.uuid_of('product'),
          'color_id',    nullif(test.txt_of('color'),'')::uuid,
          'chassis_number', 'MAT' || lpad(i::text, 12, '0'),
          'engine_number',  'ENG' || lpad(i::text, 12, '0'),
          'stock_code',     'STK-BLR-' || lpad(i::text, 3, '0'),
          'manufacturing_date', '2025-06-15',
          'model_year', 2025,
          'purchase_price', 78000,
          'landing_price', 81500,
          'mrp', 99000));
    perform test.ok(v ? 'inventoryId', 'create_inventory_unit returned an id');
    ids := array_append(ids, (v ->> 'inventoryId')::uuid);
  end loop;
  perform test.remember('inv1', ids[1]::text);
  perform test.remember('inv2', ids[2]::text);
  perform test.remember('inv3', ids[3]::text);

  perform test.ok((select count(*) from public.inventory
                    where showroom_id = test.uuid_of('blr')) = 3,
                  'three units are on the floor of the Bengaluru showroom');
  perform test.ok((select count(*) from public.stock_movements m
                    join public.inventory i on i.id = m.inventory_id
                   where i.showroom_id = test.uuid_of('blr')
                     and m.movement_type = 'STOCK_IN') = 3,
                  'every unit has its STOCK_IN ledger entry');
end
$$;

-- ---------------------------------------------------------------------------
-- Customers, written through the API so the tenant INSERT policy is exercised
-- ---------------------------------------------------------------------------
do $$
declare v_c1 uuid; v_c2 uuid;
begin
  insert into public.customers (showroom_id, customer_code, name, phone, email, address, city,
                                state, pincode, customer_type, reference_source, notes)
  values (test.uuid_of('blr'), 'CUST-0001', 'Asha Krishnan', '9876543210', 'asha@test.local',
          '22 Indiranagar 2nd Stage', 'Bengaluru', 'Karnataka', '560038', 'RETAIL', 'WALK_IN',
          'Prefers WhatsApp contact')
  returning id into v_c1;

  insert into public.customers (showroom_id, customer_code, name, phone, address, city, state,
                                pincode, customer_type, pan_number, gst_number, credit_limit)
  values (test.uuid_of('blr'), 'CUST-0002', 'Blue Ridge Cab Services', '9812345670',
          '5th Floor, Webb Market Road', 'Bengaluru', 'Karnataka', '560025', 'CORPORATE',
          'AACCB1234K', '29AACCB1234K1Z9', 500000)
  returning id into v_c2;

  perform test.remember('customer', v_c1::text);
  perform test.remember('corporate', v_c2::text);
  perform test.ok((select count(*) from public.customers
                    where showroom_id = test.uuid_of('blr')) = 2,
                  'both customers landed in the caller''s showroom');
  perform test.ok((select customer_code from public.customers where id = v_c1) = 'CUST-0001',
                  'the API may create a customer with an explicit code');
end
$$;

-- ---------------------------------------------------------------------------
-- A reservation that the sale then consumes
-- ---------------------------------------------------------------------------
do $$
declare v jsonb;
begin
  v := public.reserve_inventory(test.uuid_of('inv1'), test.uuid_of('customer'), 2);
  perform test.ok(coalesce((v ->> 'reserved')::boolean, true), 'reserve_inventory accepted the hold');
  perform test.ok((select status from public.inventory where id = test.uuid_of('inv1')) = 'RESERVED',
                  'the unit is now RESERVED');
  perform test.ok((select reserved_customer_id from public.inventory
                    where id = test.uuid_of('inv1')) = test.uuid_of('customer'),
                  'the reservation names the customer');
  perform test.raises(format(
      'select public.reserve_inventory(%L::uuid, %L::uuid, 1)', test.uuid_of('inv1'), test.uuid_of('corporate')),
      null, 'a second customer cannot reserve an already reserved unit');
end
$$;

-- ---------------------------------------------------------------------------
-- THE CASH SALE: 1 bike + 2 accessories, discount, tax, other charges, part payment
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; v_exp_total numeric; v_sale uuid; v_invoice uuid;
begin
  v := public.create_sale_transaction(jsonb_build_object(
        'showroom_id',   test.uuid_of('blr'),
        'customer_id',   test.uuid_of('customer'),
        'sale_type',     'CASH',
        'sale_date',     current_date,
        'delivery_date', current_date + 2,
        'registration_number', 'KA01AB1234',
        'other_charges', 1500,
        'notes',           'Counter sale with helmet and cover',
        'idempotency_key', '11111111-1111-1111-1111-111111111111',
        'lines', jsonb_build_array(
          jsonb_build_object('inventory_id', test.uuid_of('inv1'), 'quantity', 1,
                             'unit_price', 86000, 'discount', 4000, 'item_type', 'VEHICLE'),
          jsonb_build_object('description', 'ISAI Helmet ISI', 'quantity', 2, 'unit_price', 1450,
                             'tax_rate', 18, 'item_type', 'ACCESSORY'),
          jsonb_build_object('description', 'Seat cover set', 'quantity', 1, 'unit_price', 2500,
                             'tax_rate', 18, 'discount', 250, 'item_type', 'ACCESSORY')),
        'payments', jsonb_build_array(
          jsonb_build_object('amount', 50000, 'payment_method', 'CASH',
                             'reference_number', 'CTR-9001', 'notes', 'Booking at counter'))
      ));

  perform test.ok(coalesce((v ->> 'replayed')::boolean, false) = false,
                  'the first call is executed, not replayed');
  perform test.remember('sale', (v ->> 'saleId')::text);
  perform test.remember('invoice', (v ->> 'invoiceId')::text);
  perform test.remember('vehicle', (v ->> 'vehicleId')::text);
  v_sale := (v ->> 'saleId')::uuid; v_invoice := (v ->> 'invoiceId')::uuid;

  -- ---- the arithmetic the client is not trusted with (SS50) ----------------
  v_exp_total := round(86000 - 4000 + round((86000 - 4000) * 0.18, 2)          -- bike + GST
                     + round(2 * 1450 * 1.18, 2)                                  -- helmets
                     + round((2500 - 250) * 1.18, 2)                             -- seat cover
                     + 1500, 2);
  perform test.eq_num((v ->> 'totalAmount')::numeric, v_exp_total,
                      'the RPC computed the total exactly as the tax rules say');
  perform test.eq_num((select total_amount from public.sales where id = v_sale), v_exp_total,
                      'sales.total_amount matches the computed total');
  perform test.eq_num((select round(subtotal - discount + tax_amount + other_charges
                                    - exchange_value, 2) from public.sales where id = v_sale),
                      v_exp_total, 'the sales total CHECK formula holds');
  perform test.eq_num((select total_amount from public.invoices where id = v_invoice), v_exp_total,
                      'the invoice carries the same total as the sale');
  -- total = sum(lines) + other_charges (the roll-up formula in 007): the handling
  -- charge is a header amount, not a line, so it is added here, not in the items.
  perform test.eq_num((select round(sum(ii.total_amount), 2) from public.invoice_items ii
                        where ii.invoice_id = v_invoice)
                      + (select other_charges from public.invoices where id = v_invoice),
                      v_exp_total, 'the invoice lines plus other charges foot to the total');
  perform test.eq_num((select outstanding_amount from public.invoices where id = v_invoice),
                      round(v_exp_total - 50000, 2), 'outstanding = total - part payment');
  perform test.eq((select status from public.sales where id = v_sale), 'CONFIRMED',
                  'an admin''s sale auto-confirms (threshold + permission aware)');
  -- the 50,000 booking payment rides in the same call, so the freshly issued
  -- invoice is already PARTIALLY_PAID rather than plain FINALIZED.
  perform test.eq((select status from public.invoices where id = v_invoice), 'PARTIALLY_PAID',
                  'the invoice was finalised and then marked partially paid');
  perform test.ok((select finalized from public.invoices where id = v_invoice),
                  'the finalized flag matches the status (003 CHECK)');
  perform test.eq((select count(*) from public.sale_items where sale_id = v_sale)::int, 3,
                  'three line items were written');
  perform test.eq((select status from public.inventory where id = test.uuid_of('inv1')), 'SOLD',
                  'the unit left the floor');
  perform test.ok((select reserved_customer_id is null and allocated_sale_id = v_sale
                    from public.inventory where id = test.uuid_of('inv1')),
                  'the reservation became an allocation');
  perform test.eq((select count(*) from public.stock_movements m
                    where m.reference_id = v_sale and m.movement_type = 'SALE_ALLOCATE')::int, 1,
                  'exactly one SALE_ALLOCATE movement for the sale');
  perform test.eq((select registration_number from public.customer_vehicles
                    where id = test.uuid_of('vehicle')), 'KA01AB1234',
                  'the vehicle picked up the registration number');
  perform test.ok((select warranty_end >= warranty_start + 300 from public.customer_vehicles
                    where id = test.uuid_of('vehicle')),
                  'warranty dates were derived from the product master');
  perform test.ok((select count(*) from public.vehicle_free_services
                    where vehicle_id = test.uuid_of('vehicle')) >= 3,
                  'free service slots were opened for the new bike (SS18)');
  perform test.eq((select lifetime_value from public.customers where id = test.uuid_of('customer')),
                  v_exp_total, 'customer lifetime value absorbed the sale');

  -- ---- double entry (SS24) -------------------------------------------------
  perform test.ok((select count(*) from public.accounting_transactions t
                    where t.reference_id in (v_sale, v_invoice)) >= 1,
                  'the sale posted at least one journal');
  perform test.ok((select count(*) = 0 from (
                     select e.transaction_id from public.accounting_entries e
                       join public.accounting_transactions t on t.id = e.transaction_id
                      where t.reference_id in (v_sale, v_invoice)
                      group by e.transaction_id
                     having round(sum(e.debit),2) <> round(sum(e.credit),2)) unbalanced),
                  'every journal posted for the sale balances');
  perform test.ok(exists (select 1 from public.accounting_entries e
                            join public.accounting_transactions t on t.id = e.transaction_id
                            join public.accounts a on a.id = e.account_id
                           where t.reference_id in (v_sale, v_invoice) and a.account_code = '4100'),
                  'revenue (4100) was credited');
  perform test.ok(exists (select 1 from public.accounting_entries e
                            join public.accounting_transactions t on t.id = e.transaction_id
                            join public.accounts a on a.id = e.account_id
                           where t.reference_id in (v_sale, v_invoice) and a.account_code = '1200'),
                  'inventory (1200) was relieved for the sold unit');

  -- ---- audit + notifications ----------------------------------------------
  perform test.ok((select count(*) from public.audit_logs a
                    where a.record_id = v_sale and a.module = 'sales') >= 1,
                  'the sale is in the audit log with the acting user');
  perform test.ok((select count(*) from public.idempotency_keys k
                    where k.key = '11111111-1111-1111-1111-111111111111'::uuid
                      and k.status = 'COMPLETED') = 1,
                  'the idempotency key was marked COMPLETED');
end
$$;

-- ---------------------------------------------------------------------------
-- Replay safety: the same key must return the same document, never a second sale
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; n_before bigint;
begin
  select count(*) into n_before from public.sales where showroom_id = test.uuid_of('blr');
  v := public.create_sale_transaction(jsonb_build_object(
        'showroom_id', test.uuid_of('blr'), 'customer_id', test.uuid_of('customer'),
        'sale_type', 'CASH', 'other_charges', 1500,
        'idempotency_key', '11111111-1111-1111-1111-111111111111',
        'lines', jsonb_build_array(jsonb_build_object(
          'inventory_id', test.uuid_of('inv2'), 'quantity', 1, 'unit_price', 86000)),
        'payments', jsonb_build_array()));
  perform test.eq((v ->> 'saleId')::uuid, test.uuid_of('sale'),
                  'a replayed call returns the original sale id');
  perform test.ok((v ->> 'replayed')::boolean, 'the replay is flagged to the client');
  perform test.eq((select count(*) from public.sales where showroom_id = test.uuid_of('blr')),
                  n_before, 'the replay created no second sale');
  perform test.ok((select paid_amount from public.sales where id = test.uuid_of('sale')) = 50000,
                  'the replay did not re-apply the payment');
end
$$;

-- ---------------------------------------------------------------------------
-- The balance, then a reversal, then the balance again
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; v_pay uuid; v_outstanding numeric;
begin
  v_outstanding := (select outstanding_amount from public.invoices
                     where id = test.uuid_of('invoice'));
  perform test.ok(v_outstanding > 0, 'the invoice still owes money');

  v := public.record_payment(jsonb_build_object(
        'showroom_id', test.uuid_of('blr'), 'customer_id', test.uuid_of('customer'),
        'invoice_id', test.uuid_of('invoice'), 'sale_id', test.uuid_of('sale'),
        'amount', v_outstanding, 'payment_method', 'UPI', 'payment_type', 'RECEIPT',
        'reference_number', 'UPI-778899', 'notes', 'Balance via UPI'));
  v_pay := (v ->> 'paymentId')::uuid;
  perform test.remember('payment_upi', v_pay::text);
  perform test.eq_num((select outstanding_amount from public.invoices
                        where id = test.uuid_of('invoice')), 0,
                      'the invoice is settled');
  perform test.eq((select status from public.invoices where id = test.uuid_of('invoice')), 'PAID',
                  'settling the invoice moves it to PAID');
  perform test.eq_num((select paid_amount from public.sales where id = test.uuid_of('sale')),
                      (select total_amount from public.sales where id = test.uuid_of('sale')),
                      'the sale header sees the full amount');
  perform test.eq((select count(*) from public.payments where invoice_id = test.uuid_of('invoice'))::int,
                  2, 'both receipts are recorded on the invoice');

  -- Paying more than the outstanding balance: refused when the caller forbids an
  -- advance, otherwise kept as a credit without inflating the invoice (SS14).
  perform test.raises(format(
      'select public.record_payment(%L::jsonb)',
      jsonb_build_object('showroom_id', test.uuid_of('blr'),
                         'customer_id', test.uuid_of('customer'),
                         'invoice_id', test.uuid_of('invoice'),
                         'amount', 500, 'payment_method', 'CASH',
                         'allow_advance', false)::text),
      null, 'an over-payment is refused when allow_advance is false');

  v := public.record_payment(jsonb_build_object(
        'showroom_id', test.uuid_of('blr'), 'customer_id', test.uuid_of('customer'),
        'invoice_id', test.uuid_of('invoice'), 'sale_id', test.uuid_of('sale'),
        'amount', 500, 'payment_method', 'CASH', 'notes', 'Extra, held as credit'));
  perform test.ok((select allocated_amount from public.payments
                    where id = (v ->> 'paymentId')::uuid) = 0,
                  'an accepted over-payment allocates nothing to the settled invoice');
  perform test.eq_num((select paid_amount from public.invoices where id = test.uuid_of('invoice')),
                      (select total_amount from public.invoices where id = test.uuid_of('invoice')),
                      'the credit never inflates invoices.paid_amount');
  perform test.remember('credit_payment', (v ->> 'paymentId')::text);

  -- financial records are never deleted: reversing is the only path (SS15, SS42)
  v := public.reverse_payment(v_pay, 'Customer asked to split the payment', current_date);
  perform test.ok((v ->> 'reversalPaymentId') is not null,
                  'reversal writes a REFUND/REVERSAL row instead of deleting');
  perform test.eq_num((select outstanding_amount from public.invoices
                        where id = test.uuid_of('invoice')), v_outstanding,
                      'the reversal restored the outstanding amount');
  -- the 50,000 booking receipt is still allocated, so the invoice falls back to
  -- PARTIALLY_PAID rather than a plain FINALIZED.
  perform test.eq((select status from public.invoices where id = test.uuid_of('invoice')),
                  'PARTIALLY_PAID', 'the invoice is partly payable again after the reversal');
  perform test.ok((select status from public.payments where id = v_pay) in
                    ('REVERSED','REJECTED','CANCELLED'),
                  'the original payment keeps its history with a REVERSED status');
end
$$;

-- ---------------------------------------------------------------------------
-- Immutability: money that has been issued must not be rewritable. There are
-- two independent locks and both are tested, because they protect different
-- callers:
--   1. the API role (anon/authenticated) - grants + RLS: writes are refused
--      outright or silently match no row, so a compromised client cannot edit
--      or erase a receipt;
--   2. a privileged writer (service_role, migrations, a DBA) - the triggers,
--      which is why the same statements are retried without the RLS layer.
-- ---------------------------------------------------------------------------
do $$
declare
  v_rows integer;
begin
  -- payments only carry select+insert policies, so even a correctly privileged
  -- UPDATE finds nothing to write.
  update public.payments set amount = 1 where id = test.uuid_of('payment_upi');
  get diagnostics v_rows = row_count;
  perform test.ok(v_rows = 0, 'the API role cannot rewrite a payment');

  -- invoices keep an UPDATE policy (the RPCs and the print counters write to
  -- them), so prove the policy is real: a non-monetary edit lands, while every
  -- money column is frozen by the guards tested below.
  update public.invoices set notes = 'checked by the test' where id = test.uuid_of('invoice');
  get diagnostics v_rows = row_count;
  perform test.ok(v_rows = 1, 'the API role can still annotate an invoice');

  perform test.raises('delete from public.payments', null, 'payments cannot be deleted through the API');
  perform test.raises('update public.stock_movements set quantity = 5', null, 'stock movements are append-only');
  perform test.raises('delete from public.accounting_entries', null, 'journal lines cannot be removed');
  perform test.raises('delete from public.audit_logs', null, 'the audit trail cannot be erased');
end
$$;

reset role;   -- now as a privileged writer: the RLS layer is out of the way
do $$
begin
  perform test.raises(format('update public.invoices set total_amount = 1 where id = %L',
                             test.uuid_of('invoice')), null, 'a finalized invoice cannot be re-priced');
  perform test.raises(format('update public.invoice_items set unit_price = 1 where invoice_id = %L',
                             test.uuid_of('invoice')), null, 'lines of a finalized invoice are frozen');
  perform test.raises(format('update public.payments set amount = 1 where id = %L',
                             test.uuid_of('payment_upi')), null, 'a payment row cannot be edited');
  perform test.raises(format('delete from public.payments where id = %L', test.uuid_of('payment_upi')),
                      null, 'a payment row cannot be deleted');
  perform test.raises(format('update public.accounting_transactions set transaction_date = transaction_date + 1 '
                             'where reference_id = %L', test.uuid_of('sale')),
                      null, 'a posted journal is immutable apart from its reversal');
  perform test.raises('delete from public.accounting_transactions', null, 'journals cannot be deleted');
end
$$;
set role authenticated;

-- ---------------------------------------------------------------------------
-- FINANCE sale: loan, schedule, lender disbursement, EMI reporting
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; v_loan uuid; v_finco uuid; v_sch jsonb;
        v_emi_count int; v_total numeric; v_calc numeric;
begin
  select id into v_finco from public.finance_companies where code = 'BAJAJ-FINSERV';
  if v_finco is null then raise exception 'seed finance company missing'; end if;
  perform test.remember('finance_company', v_finco::text);

  v := public.create_sale_transaction(jsonb_build_object(
        'showroom_id', test.uuid_of('blr'), 'customer_id', test.uuid_of('corporate'),
        'sale_type', 'FINANCE', 'sale_date', current_date, 'other_charges', 2000,
        'lines', jsonb_build_array(jsonb_build_object(
          'inventory_id', test.uuid_of('inv2'), 'quantity', 1, 'unit_price', 86000,
          'item_type', 'VEHICLE')),
        'payments', jsonb_build_array(jsonb_build_object(
          'amount', 20000, 'payment_method', 'CHEQUE', 'reference_number', 'CHQ-55',
          'instrument_number', 'CHQ-000555', 'bank_name', 'Bank of Bangalore')),
        'finance', jsonb_build_object(
          'finance_company_id', v_finco, 'down_payment', 20000, 'interest_rate', 12.5,
          'tenure_months', 24, 'interest_type', 'REDUCING', 'start_date', current_date,
          'lender_reference', 'BFL/2026/000777', 'processing_fee', 1500)));

  v_loan := (v ->> 'loanId')::uuid;
  perform test.remember('loan', v_loan::text);
  perform test.ok(v_loan is not null, 'a FINANCE sale produced a loan row');
  perform test.eq((select count(*) from public.emi_schedules where loan_id = v_loan)::int, 24,
                  'the schedule has one row per instalment');
  perform test.eq((select status from public.loans where id = v_loan), 'ACTIVE',
                  'the loan is ACTIVE once the sale confirms');
  perform test.eq((select lender_reference from public.loans where id = v_loan), 'BFL/2026/000777',
                  'the lender reference was stored');

  v_total := (select round(sum(emi_amount), 2) from public.emi_schedules where loan_id = v_loan);
  perform test.eq_num((select total_payable from public.loans where id = v_loan), v_total,
                      'loans.total_payable equals the sum of the schedule');
  perform test.eq((select round(sum(principal_amount), 2) from public.emi_schedules
                    where loan_id = v_loan),
                  (select loan_amount from public.loans where id = v_loan),
                  'the principal across the schedule equals the financed amount');
  perform test.ok((select count(*) from public.emi_schedules e
                    where e.loan_id = v_loan
                      and round(e.emi_amount - (e.principal_amount + e.interest_amount), 2) <> 0) = 0,
                  'every instalment is principal + interest (004 CHECK + math)');
  perform test.ok((select min(due_date) from public.emi_schedules where loan_id = v_loan)
                    > current_date, 'the first instalment is in the future');
  -- the schedule must walk forward in time, one instalment per month
  perform test.eq((select count(*) from (
                     select due_date, lag(due_date) over (order by emi_number) as prev
                       from public.emi_schedules where loan_id = v_loan
                   ) w where w.prev is not null and w.due_date <= w.prev), 0::bigint,
                  'instalment due dates increase monotonically');

  -- the EMI on the loan row must be what calculate_emi() says it is
  v_calc := (select emi_amount from public.loans where id = v_loan);
  perform test.eq_num(v_calc,
                      public.calculate_emi((select principal_amount from public.loans where id = v_loan),
                                          (select interest_rate from public.loans where id = v_loan),
                                          24, 'REDUCING'),
                      'the stored EMI matches calculate_emi()');

  -- the lender's money is a receipt on the same invoice (SS16)
  perform test.ok((select count(*) from public.payments p
                    where p.loan_id = v_loan and p.payment_method = 'FINANCE') = 1,
                  'the disbursement was recorded as a FINANCE payment');
  perform test.eq_num((select paid_amount from public.sales where id = (v ->> 'saleId')::uuid),
                      (select total_amount from public.sales where id = (v ->> 'saleId')::uuid),
                      'down payment + disbursement settle the finance sale');
  perform test.remember('finance_sale', (v ->> 'saleId')::text);

  -- EMI reminders (SS17). The schedule starts a month after the loan start, so a
  -- three-day horizon must create nothing; widening the horizon queues the
  -- instalments that actually come due, keyed to the schedule row (not the loan).
  perform test.ok((select count(*) from public.reminders r
                    where r.reminder_type = 'EMI'
                      and r.reference_id in
                          (select e.id from public.emi_schedules e where e.loan_id = v_loan)) = 0,
                  'no EMI reminders before they are generated');

  v_sch := public.create_emi_reminders(v_loan, 3);
  perform test.ok(coalesce((v_sch ->> 'created')::int, 0) = 0,
                  'a horizon shorter than the first due date creates no reminder');

  v_sch := public.create_emi_reminders(v_loan, 40);
  perform test.ok(coalesce((v_sch ->> 'created')::int, 0) >= 1,
                  'create_emi_reminders reports the rows it inserted');
  perform test.ok((select count(*) from public.reminders r
                    where r.reminder_type = 'EMI' and r.status = 'PENDING'
                      and r.reference_id in
                          (select e.id from public.emi_schedules e where e.loan_id = v_loan)) >= 1,
                  'the reminder is pending and points at the schedule row');

  v_sch := public.create_emi_reminders(v_loan, 40);
  perform test.ok(coalesce((v_sch ->> 'created')::int, 0) = 0,
                  'a second run dedupes instead of spamming the customer');

  -- reporting views see the sale (SS51)
  perform test.ok((select count(*) from public.daily_sales_summary d
                    where d.showroom_id = test.uuid_of('blr')) = 1,
                  'daily_sales_summary aggregates the showroom');
  perform test.eq(coalesce((select sum(d.gross_amount) from public.daily_sales_summary d
                             where d.showroom_id = test.uuid_of('blr')), 0),
                  (select sum(s.total_amount) from public.sales s
                     where s.showroom_id = test.uuid_of('blr') and s.status <> 'RETURNED'),
                  'the daily summary foots to the sales ledger');
  perform test.ok((select count(*) from public.emi_due_summary e
                    where e.loan_id = v_loan) > 0, 'emi_due_summary lists the schedule');
  perform test.ok((select count(*) from public.inventory_summary i
                    where i.showroom_id = test.uuid_of('blr')) >= 1,
                  'inventory_summary still reports the remaining stock');

  -- Customer 360 / Vehicle 360 (SS35) and the print payload the PDF layer consumes (SS15)
  perform test.ok((select count(*) from jsonb_object_keys(
                       public.get_customer_360(test.uuid_of('customer')))) >= 5,
                  'get_customer_360 returns a rich payload');
  perform test.ok((select count(*) from jsonb_object_keys(
                       public.get_vehicle_360(test.uuid_of('vehicle')))) >= 5,
                  'get_vehicle_360 returns a rich payload');
  perform test.eq(
      (select (g -> 'invoice' ->> 'total_amount')::numeric
         from public.get_invoice_print_payload(test.uuid_of('invoice')) as g),
      (select i.total_amount from public.invoices i where i.id = test.uuid_of('invoice')),
      'the print payload foots to the invoice header');
  perform test.ok((select count(*) from jsonb_object_keys(
                       public.get_invoice_print_payload(test.uuid_of('invoice')))) >= 6,
                  'the print payload carries parties, lines, payments and the vehicle');

  -- global search is RLS filtered: the API role sees its own showroom's customer
  perform test.ok((select count(*) from public.global_search('Asha', 20) r
                    where r.result_type = 'customer'
                      and r.id = test.uuid_of('customer')) = 1,
                  'global_search finds the customer by name');

  -- the ledger must still be sane after two sales, a payment and a reversal
  perform test.assert_ledger_is_sane();
end
$$;

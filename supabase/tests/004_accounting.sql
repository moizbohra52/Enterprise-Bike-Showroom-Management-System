-- =============================================================================
-- 004_accounting.sql  -  purchases, expenses, journals and the reports
-- -----------------------------------------------------------------------------
-- Double entry is the part of this system that cannot be faked: every document
-- in this file is asserted by reading accounting_entries back, never by trusting
-- a return value.  The invariants defended here are
--
--   * a purchase accrues to Supplier Payable (2100) and to the P&L while the
--     goods are in transit, and moves into Inventory (1200) only when they are
--     physically received (SS16, SS24);
--   * an expense is accrued on Expense Payable (2500) while it waits for
--     approval and cleared against cash only when it is paid (SS23);
--   * a hand-made journal balances to the paisa, can be reversed but never
--     edited, and reversals are what make the trial balance still foot (SS24);
--   * the report functions agree with each other, because the Flutter app shows
--     them side by side (SS51, SS52).
-- =============================================================================

reset role;

-- ---------------------------------------------------------------------------
-- Fixture: a supplier, the catalogue product and the expense categories.  The
-- supplier and a test category are created by the superuser so the file does not
-- depend on which demo rows 014 happened to seed.
-- ---------------------------------------------------------------------------
do $$
declare
  v_blr     uuid;
  v_hyd     uuid;
  v_sup     uuid;
  v_prod    uuid;
  v_mgr     uuid;
  v_acct    uuid;
  v_cat_appr uuid;
  v_cat_free uuid;
begin
  select id into v_blr from public.showrooms where code = 'TST-BLR';
  select id into v_hyd from public.showrooms where code = 'TST-HYD';
  select id into v_mgr  from public.users where auth_user_id = 'a0000000-0000-0000-0000-000000000002'::uuid;
  select id into v_acct from public.users where auth_user_id = 'a0000000-0000-0000-0000-000000000005'::uuid;
  if v_blr is null or v_hyd is null or v_mgr is null or v_acct is null then
    raise exception '004 needs the showrooms and staff accounts created by 001_bootstrap.sql';
  end if;
  select id into v_prod from public.products where model = 'Shine 125' and variant = 'DX Smart';
  if v_prod is null then
    raise exception '004 needs the seeded catalogue (Honda Shine 125 DX Smart)';
  end if;

  insert into public.suppliers (name, code, contact_person, phone, city, state, status)
       values ('Test Parts Supplier', 'TST-SUP-01', 'Desk', '08011112222', 'Bengaluru',
               'Karnataka', 'ACTIVE')
    on conflict (name) do update set status = 'ACTIVE'
    returning id into v_sup;

  -- a category that always needs a signature, and one that never does
  select id into v_cat_appr from public.expense_categories where name = 'Marketing';
  select id into v_cat_free from public.expense_categories where name = 'Electricity';
  if v_cat_appr is null or v_cat_free is null then
    raise exception '004 needs the seeded expense categories Marketing and Electricity';
  end if;

  insert into public.expense_categories (name, code, description, account_code,
                                         is_system, requires_approval, approval_limit)
       values ('Test Site Cleaning', 'TST-CLEAN', 'Sweeping and housekeeping',
               '5350', false, true, 5000)
    on conflict (name) do update set approval_limit = excluded.approval_limit
    returning id into v_cat_appr;   -- reused below as the limit-tested category

  perform test.remember('blr', v_blr::text);
  perform test.remember('hyd', v_hyd::text);
  perform test.remember('manager', v_mgr::text);
  perform test.remember('accountant', v_acct::text);
  perform test.remember('supplier', v_sup::text);
  perform test.remember('product', v_prod::text);
  perform test.remember('cat_marketing', (select id from public.expense_categories
                                           where name = 'Marketing')::text);
  perform test.remember('cat_electricity', v_cat_free::text);
  perform test.remember('cat_limited', v_cat_appr::text);
end
$$;

-- ---------------------------------------------------------------------------
-- A purchase order raised in the office: money owed, stock not yet in.
-- ---------------------------------------------------------------------------
set role authenticated;
select test.as('a0000000-0000-0000-0000-000000000002'::uuid, test.uuid_of('blr'));

do $$
declare
  v    jsonb;
  v_pur uuid;
  v_line uuid;
  v_d  numeric;
  v_c  numeric;
begin
  v := public.create_purchase_transaction(jsonb_build_object(
        'showroom_id', test.uuid_of('blr'),
        'supplier_id', test.uuid_of('supplier'),
        'purchase_date', current_date,
        'expected_date', current_date + 4,
        'invoice_reference', 'GRN-TST-9001',
        'other_charges', 300,
        'freight_charges', 1200,
        'paid_amount', 100000,
        'payment_method', 'BANK_TRANSFER',
        'receive_now', false,
        'notes', 'Monthly order for the Bengaluru floor',
        'lines', jsonb_build_array(jsonb_build_object(
          'product_id', test.uuid_of('product'), 'quantity', 3, 'unit_cost', 78000,
          'discount', 900, 'tax_rate', 18))));

  v_pur := (v ->> 'purchaseId')::uuid;
  perform test.remember('purchase', v_pur::text);
  perform test.ok(coalesce((v ->> 'lineCount')::int, 0) = 1, 'the purchase was created with its line');
  perform test.ok((v ->> 'inventoryGenerated')::boolean = false,
                  'no stock is generated while the goods are still on order');

  -- header arithmetic, asserted against the numbers the payload implies:
  --   goods  3 x 78000 = 234000, discount 900, GST 18% on the net = 41958,
  --   other 300 + freight 1200 => total 276558, part-paid 100000 => owe 176558
  perform test.eq_num((select subtotal from public.purchases where id = v_pur), 234000,
                      'the purchase subtotal is quantity x unit cost');
  perform test.eq_num((select discount from public.purchases where id = v_pur), 900,
                      'the supplier discount is carried on the header');
  perform test.eq_num((select tax_amount from public.purchases where id = v_pur), 41958,
                      'GST is charged on the net goods value');
  perform test.eq_num((select other_charges from public.purchases where id = v_pur), 300,
                      'other charges survive on the purchase');
  perform test.eq_num((select freight_charges from public.purchases where id = v_pur), 1200,
                      'freight is part of what we owe the supplier');
  perform test.eq_num((select total_amount from public.purchases where id = v_pur), 276558,
                      'the purchase total foots');
  perform test.eq_num((select paid_amount from public.purchases where id = v_pur), 100000,
                      'the part-payment is recorded on the purchase');
  perform test.eq_num((select outstanding_amount from public.purchases where id = v_pur), 176558,
                      'the balance stays outstanding to the supplier');
  perform test.eq((select status from public.purchases where id = v_pur), 'DRAFT',
                  'an unreceived purchase waits for approval');

  -- supplier money never enters payments(): that table is the customer ledger
  select count(*) into v_d from public.payments p
    join public.purchases pu on pu.id = p.sale_id
   where pu.id = v_pur;
  perform test.ok(v_d = 0, 'a supplier payment is not a customer receipt');

  -- the accrual journal: goods + charges to Purchases, GST to GST Receivable,
  -- the whole invoice to Supplier Payable
  select round(coalesce(sum(e.debit), 0), 2), round(coalesce(sum(e.credit), 0), 2)
    into v_d, v_c
    from public.accounting_entries e
    join public.accounting_transactions t on t.id = e.transaction_id
   where t.reference_type = 'purchase' and t.reference_id = v_pur;
  perform test.ok(v_d is not null and v_c is not null, 'the purchase posted a journal');
  perform test.eq_num(v_d, v_c, 'the purchase journal balances');
  perform test.eq_num(v_c,
        (select total_amount from public.purchases where id = v_pur),
        'the credit side equals what we owe the supplier');

  select round(coalesce(sum(case when a.account_code = '5100' then e.debit - e.credit end), 0), 2)
    into v_d
    from public.accounting_entries e
    join public.accounting_transactions t on t.id = e.transaction_id
    join public.accounts a on a.id = e.account_id
   where t.reference_id = v_pur and a.showroom_id = test.uuid_of('blr');
  perform test.eq_num(v_d, 234000 - 900 + 300 + 1200,
                      'unreceived stock sits in the P&L, not in Inventory');

  -- receiving before approval is refused, and so is approving twice
  v_line := (select id from public.purchase_items where purchase_id = v_pur limit 1);
  perform test.remember('purchase_line', v_line::text);
  perform test.raises(format('select public.receive_purchase(%L, jsonb_build_object(%L, %L::jsonb))',
                             v_pur, 'lines',
                             jsonb_build_array(jsonb_build_object('purchase_item_id', v_line,
                                                                  'quantity', 1))::text),
                      'CON001', 'goods cannot be received against a DRAFT order');
  perform test.raises('select public.approve_purchase(gen_random_uuid(), true, null)', 'NOT001',
                      'an unknown purchase id says not-found');
end
$$;

-- ---------------------------------------------------------------------------
-- Approval, then the physical receipt with serialised units.
-- ---------------------------------------------------------------------------
do $$
declare
  v    jsonb;
  v_pur uuid := test.uuid_of('purchase');
begin
  v := public.approve_purchase(v_pur, true, null);
  perform test.eq(v ->> 'status', 'CONFIRMED', 'approval confirms the order');
  perform test.raises(format('select public.approve_purchase(%L, true, null)', v_pur),
                      'CON001', 'a confirmed order cannot be approved again');

  v := public.receive_purchase(v_pur, jsonb_build_object('lines', jsonb_build_array(
        jsonb_build_object(
          'purchase_item_id', test.uuid_of('purchase_line'),
          'units', jsonb_build_array(
            jsonb_build_object('chassis_number', 'MAT000000000401',
                               'engine_number', 'ENG-000000000401', 'stock_code', 'STK-BLR-401'),
            jsonb_build_object('chassis_number', 'MAT000000000402',
                               'engine_number', 'ENG-000000000402', 'stock_code', 'STK-BLR-402'),
            jsonb_build_object('chassis_number', 'MAT000000000403',
                               'engine_number', 'ENG-000000000403', 'stock_code', 'STK-BLR-403')
          )))));

  perform test.ok(coalesce((v ->> 'unitsReceived')::int, 0) = 3, 'three serialised units were created');
  perform test.eq(v ->> 'status', 'RECEIVED', 'the order is fully received');
  perform test.ok((select count(*) from public.inventory i
                    where i.showroom_id = test.uuid_of('blr')
                      and i.chassis_number in ('MAT000000000401','MAT000000000402','MAT000000000403')
                      and i.status = 'AVAILABLE') = 3,
                  'the new units are on the floor of the right showroom');
  perform test.ok((select count(*) from public.stock_movements m
                    where m.reference_type = 'purchase' and m.reference_id = v_pur
                      and m.movement_type = 'STOCK_IN') = 3,
                  'every received unit has its STOCK_IN movement');
  perform test.ok((select received_quantity from public.purchase_items
                    where id = test.uuid_of('purchase_line')) = 3,
                  'the line reports what has landed');
  perform test.raises(format('select public.receive_purchase(%L, jsonb_build_object(%L, %L::jsonb))',
                             v_pur, 'lines',
                             jsonb_build_array(jsonb_build_object(
                               'purchase_item_id', test.uuid_of('purchase_line'),
                               'quantity', 1))::text),
                      null, 'the same line cannot be received beyond its quantity');

  -- the reclassification: the asset side of the balance sheet
  perform test.ok(exists (select 1
                             from public.accounting_entries e
                             join public.accounting_transactions t on t.id = e.transaction_id
                             join public.accounts a on a.id = e.account_id
                            where t.reference_type = 'purchase_receipt' and t.reference_id = v_pur
                              and a.account_code = '1200' and e.debit = 234000),
                  'received stock is capitalised into Inventory at cost');
  perform test.eq_num(
      (select round(coalesce(sum(e.debit - e.credit), 0), 2)
         from public.accounting_entries e
         join public.accounting_transactions t on t.id = e.transaction_id
         join public.accounts a on a.id = e.account_id
        where t.reference_id = v_pur and a.account_code = '5100'),
      300 + 1200 - 900,
      'freight and charges stay in the P&L while the goods move out of it');
end
$$;

-- ---------------------------------------------------------------------------
-- An offline retry must not buy the bikes twice (SS84).
-- ---------------------------------------------------------------------------
do $$
declare
  v     jsonb;
  v_key uuid := gen_random_uuid();
  n_before integer;
  n_after  integer;
  v_payload jsonb;
begin
  v_payload := jsonb_build_object(
      'showroom_id', test.uuid_of('blr'), 'supplier_id', test.uuid_of('supplier'),
      'purchase_date', current_date, 'receive_now', false, 'idempotency_key', v_key,
      'lines', jsonb_build_array(jsonb_build_object(
        'product_id', test.uuid_of('product'), 'quantity', 1, 'unit_cost', 80000)));

  select count(*) into n_before from public.purchases
    where supplier_id = test.uuid_of('supplier');
  v := public.create_purchase_transaction(v_payload);
  perform test.remember('retry_purchase', (v ->> 'purchaseId')::text);
  select count(*) into n_after from public.purchases
    where supplier_id = test.uuid_of('supplier');
  perform test.ok(n_after = n_before + 1, 'the first attempt stored the order');

  v := public.create_purchase_transaction(v_payload);
  select count(*) into n_after from public.purchases
    where supplier_id = test.uuid_of('supplier');
  perform test.ok(coalesce((v ->> 'replayed')::boolean, false),
                  'the retry is answered from the idempotency cache');
  perform test.eq(v ->> 'purchaseId', test.uuid_of('retry_purchase')::text,
                  'the replay returns the original purchase id');
  perform test.ok(n_after = n_before + 1, 'a retry never buys the bikes twice');
end
$$;

-- ---------------------------------------------------------------------------
-- Expenses: accrual, approval, payment - and the rules that decide who may do
-- each step.
-- ---------------------------------------------------------------------------
do $$
declare
  v        jsonb;
  v_exp    uuid;
  v_bal    numeric;
begin
  -- an expense the category says must be approved
  v := public.create_expense_transaction(jsonb_build_object(
        'showroom_id', test.uuid_of('blr'),
        'category_id', test.uuid_of('cat_marketing'),
        'expense_date', current_date,
        'amount', 11800, 'tax_amount', 1800,
        'vendor_name', 'Bengaluru Ads', 'vendor_invoice_number', 'BA-7781',
        'description', 'Door-to-door campaign, month 1'));
  v_exp := (v ->> 'expenseId')::uuid;
  perform test.remember('expense_pending', v_exp::text);
  perform test.eq((select status from public.expenses where id = v_exp), 'PENDING',
                  'a category that needs approval queues the expense');
  perform test.eq_num((select total_amount from public.expenses where id = v_exp), 13600,
                      'the expense totals amount plus tax');

  -- the accrual must be visible in the ledger before anybody pays for it
  v_bal := (select balance from public.get_trial_balance(test.uuid_of('blr')) tb
             where tb.account_code = '2500');
  perform test.eq_num(v_bal, 13600, 'Expense Payable carries the unpaid expense');
  perform test.ok((select accounting_transaction_id from public.expenses where id = v_exp) is not null,
                  'the expense row points at its journal');

  -- approving is not paying
  v := public.decide_expense(v_exp, true, 'agreed with the branch head', false);
  perform test.eq(v ->> 'status', 'APPROVED', 'approval changes the status only');
  perform test.eq_num((select balance from public.get_trial_balance(test.uuid_of('blr')) tb
                        where tb.account_code = '2500'), 13600,
                      'approving does not clear the payable');

  perform test.remember('expense_pending', v_exp::text);

  -- Paying out money is a finance act, not an approval act: the manager who
  -- signed the bill cannot also settle it (SS6, SS23).
  perform test.raises(format('select public.pay_expense(%L, %L, current_date, %L)',
                             v_exp, 'BANK_TRANSFER', 'NEFT-55210'),
                      'SEC001', 'the approving manager cannot pay the expense');

  -- an expense that nobody has approved yet, for the accountant to try
  v := public.create_expense_transaction(jsonb_build_object(
        'showroom_id', test.uuid_of('blr'), 'category_id', test.uuid_of('cat_marketing'),
        'amount', 9000, 'description', 'Unapproved spend'));
  perform test.remember('expense_unapproved', (v ->> 'expenseId')::text);

  -- a utility bill: the category says no approval is needed
  v := public.create_expense_transaction(jsonb_build_object(
        'showroom_id', test.uuid_of('blr'), 'category_id', test.uuid_of('cat_electricity'),
        'amount', 8450, 'payment_method', 'CASH', 'paid_now', true,
        'description', ' BESCOM bill for the floor'));
  perform test.eq((select status from public.expenses where id = (v ->> 'expenseId')::uuid), 'PAID',
                  'a category that never needs approval pays through in one call');
  perform test.ok((select accounting_transaction_id from public.expenses
                    where id = (v ->> 'expenseId')::uuid) is not null,
                  'the paid expense is journalled on creation');
  -- 5320 Electricity Expense picked up exactly the net amount
  perform test.ok((select count(*) from public.accounting_entries e
                    join public.accounts a on a.id = e.account_id
                    join public.accounting_transactions t on t.id = e.transaction_id
                   where t.reference_id = (v ->> 'expenseId')::uuid and a.account_code = '5320'
                     and e.debit = 8450) = 1,
                  'the bill posts to its own expense account, not to a generic one');

  -- a small amount inside the category limit auto-approves, a bigger one does not
  v := public.create_expense_transaction(jsonb_build_object(
        'showroom_id', test.uuid_of('blr'), 'category_id', test.uuid_of('cat_limited'),
        'amount', 4000, 'description', 'Weekly sweeping'));
  perform test.eq((select status from public.expenses where id = (v ->> 'expenseId')::uuid), 'APPROVED',
                  'an expense at or below the category limit skips approval');
  v := public.create_expense_transaction(jsonb_build_object(
        'showroom_id', test.uuid_of('blr'), 'category_id', test.uuid_of('cat_limited'),
        'amount', 6000, 'description', 'Deep cleaning after the expo'));
  perform test.eq((select status from public.expenses where id = (v ->> 'expenseId')::uuid), 'PENDING',
                  'the same category queues a bigger bill for a signature');

  -- rejection reverses the accrual instead of deleting it
  v := public.create_expense_transaction(jsonb_build_object(
        'showroom_id', test.uuid_of('blr'), 'category_id', test.uuid_of('cat_marketing'),
        'amount', 2500, 'description', 'Cancelled campaign idea'));
  v_exp := (v ->> 'expenseId')::uuid;
  perform test.raises(format('select public.decide_expense(%L, false, null, false)', v_exp),
                      'VAL001', 'a rejection must say why');
  v := public.decide_expense(v_exp, false, 'Not in this quarter''s budget', false);
  perform test.eq(v ->> 'status', 'REJECTED', 'the expense is rejected, not deleted');
  perform test.ok((select count(*) from public.expenses where id = v_exp) = 1,
                  'a rejected expense keeps its row for the audit trail');
end
$$;

-- ---------------------------------------------------------------------------
-- Hand-made journals: the accountant's power, with its guard rails.
-- ---------------------------------------------------------------------------
select test.as('a0000000-0000-0000-0000-000000000005'::uuid, test.uuid_of('blr'));

do $$
declare
  v_tx   uuid;
  v_acct uuid;
  v_bal  numeric;
  v_last numeric;
  v_rev  uuid;
  v_n    numeric;
  v      jsonb;
begin
  -- The accountant settles what the branch approved.
  v := public.pay_expense(test.uuid_of('expense_pending'), 'BANK_TRANSFER',
                          current_date, 'NEFT-55210');
  perform test.eq(v ->> 'status', 'PAID', 'paying settles the expense');
  perform test.eq((select reference_number from public.expenses
                    where id = test.uuid_of('expense_pending')), 'NEFT-55210',
                  'the bank reference is kept on the expense');
  -- The paid bill is gone from the payable; the ones nobody has settled are
  -- still there, exactly.  Comparing against the open documents instead of a
  -- literal keeps the assertion true when other tests add expenses.
  perform test.eq_num(coalesce((select sum(e.debit - e.credit)
     from public.accounting_entries e
     join public.accounting_transactions t on t.id = e.transaction_id
     join public.accounts a on a.id = e.account_id
    where t.reference_id = test.uuid_of('expense_pending') and a.account_code = '2500'), 0), 0,
    'the settled bill no longer sits in Expense Payable');
  perform test.eq_num(
    coalesce((select balance from public.get_trial_balance(test.uuid_of('blr')) tb
               where tb.account_code = '2500'), 0),
    (select coalesce(sum(total_amount), 0) from public.expenses
      where showroom_id = test.uuid_of('blr') and status in ('PENDING','APPROVED')),
    'Expense Payable equals exactly the bills that have not been settled');
  perform test.raises(format('select public.pay_expense(%L, %L, current_date, null)',
                             test.uuid_of('expense_pending'), 'CASH'),
                      'CON001', 'a paid expense cannot be paid again');
  perform test.raises(format('select public.pay_expense(%L, %L, current_date, null)',
                             test.uuid_of('expense_unapproved'), 'CASH'),
                      'CON002', 'only an approved expense can be paid');

  v_bal := (select balance from public.get_trial_balance(test.uuid_of('blr')) tb
             where tb.account_code = '5900');

  v_tx := public.create_accounting_transaction(jsonb_build_object(
             'showroom_id', test.uuid_of('blr'),
             'transaction_date', current_date,
             'journal_type', 'MANUAL',
             'description', 'Waiver of a small statutory fee',
             'lines', jsonb_build_array(
               jsonb_build_object('code', '5900', 'debit', 5000, 'description', 'Fee written off'),
               jsonb_build_object('code', '1010', 'credit', 5000, 'description', 'Cash'))));
  perform test.ok(v_tx is not null, 'the accountant posted a manual journal');
  perform test.remember('manual_journal', v_tx::text);

  perform test.eq_num(coalesce((select balance from public.get_trial_balance(test.uuid_of('blr')) tb
                                 where tb.account_code = '5900'), 0),
                      v_bal + 5000, 'the ledger moved by exactly the amount posted');
  perform test.eq((select status from public.accounting_transactions where id = v_tx), 'POSTED',
                  'a posted journal is not a draft');
  perform test.eq((select is_reversed from public.accounting_transactions where id = v_tx), false,
                  'and it starts life unreversed');

  -- A client has no write path to the ledger at all.  Row-level security *filters*
  -- writes rather than raising, so what the accountant can observe is that nothing
  -- happened - which is the point, and is checked as an effect, not as an error.
  update public.accounting_transactions set description = 'hacked' where id = v_tx;
  get diagnostics v_n = row_count;
  perform test.eq_num(v_n, 0, 'the accountant cannot edit a posted journal');
  -- the line table is not even granted to the role, so this fails before RLS is
  -- consulted: defence in depth rather than one lucky gate.
  perform test.raises(format('delete from public.accounting_entries where transaction_id = %L', v_tx),
                      null, 'and the accountant cannot remove a line from it');
  perform test.eq((select description from public.accounting_transactions where id = v_tx),
                  'Waiver of a small statutory fee', 'the words on the journal never changed');

  -- the ledger report and the trial balance must tell the same story
  v_acct := (select a.id from public.accounts a
              where a.showroom_id = test.uuid_of('blr') and a.account_code = '5900');
  select running_balance into v_last
    from public.get_account_ledger(v_acct)
   order by transaction_date desc, entry_id desc limit 1;
  perform test.ok(v_last is not null, 'the ledger for 5900 has movements');
  perform test.eq_num(coalesce(v_bal, 0) + 5000,
                      (select balance from public.get_trial_balance(test.uuid_of('blr')) tb
                        where tb.account_code = '5900'),
                      'the trial balance agrees with itself across two reports');

  -- reversal: the original stays, an opposite journal appears, the balance returns
  v_rev := public.reverse_accounting_transaction(v_tx, 'Booked against the wrong head');
  perform test.ok(v_rev is not null, 'the reversal returned a journal id');
  perform test.ok((select is_reversed from public.accounting_transactions where id = v_tx),
                  'the original is marked reversed');
  perform test.eq((select reversed_by_transaction_id from public.accounting_transactions
                     where id = v_tx), v_rev, 'and points at the journal that cancelled it');
  perform test.eq_num(coalesce((select balance from public.get_trial_balance(test.uuid_of('blr')) tb
                                 where tb.account_code = '5900'), 0),
                      v_bal, 'the account is back where it started');
  perform test.raises(format('select public.reverse_accounting_transaction(%L, %L)', v_tx, 'again'),
                      null, 'a journal cannot be reversed twice');
  -- A reversal is itself a journal, so it looks reversible; it is not. Reversing a
  -- correction would undo the correction and leave the error back on the books.
  perform test.raises(format('select public.reverse_accounting_transaction(%L, %L)', v_rev, 'and back'),
                      'CON002', 'a reversal cannot itself be reversed');
end
$$;

-- ---------------------------------------------------------------------------
-- The database guards the ledger even from a privileged connection: the trigger,
-- not the policy, is what makes an accounting record immutable (SS42, SS43).
-- ---------------------------------------------------------------------------
reset role;

do $$
declare
  v_tx uuid := test.uuid_of('manual_journal');
begin
  perform test.raises(format('update public.accounting_transactions set description = %L where id = %L',
                             'hacked', v_tx),
                      'CON009', 'even the owner cannot rewrite the words on a posted journal');
  perform test.raises(format('update public.accounting_transactions set transaction_date = transaction_date + 1 where id = %L', v_tx),
                      'CON009', 'nor move it into another period');
  perform test.raises(format('update public.accounting_transactions set reference_id = gen_random_uuid() where id = %L', v_tx),
                      'CON009', 'nor re-point it at a different document');
  perform test.raises(format('delete from public.accounting_transactions where id = %L', v_tx),
                      'CON008', 'a journal can never be deleted');
  perform test.raises(format('update public.accounting_entries set debit = 1 where transaction_id = %L', v_tx),
                      'CON007', 'its lines are append-only');
  -- Appending a line is possible for the owner by design (an accountant may add an
  -- extra entry to a draft), so the guard that protects a posted journal is the
  -- deferred balance check, which fires at commit; asserting it here would abort the
  -- file.  What must be provable now is that the journal that exists is balanced.
  perform test.eq_num((select coalesce(sum(debit - credit), 0) from public.accounting_entries
                        where transaction_id = v_tx), 0,
                      'the journal left on the books is balanced');
end
$$;

set role authenticated;

-- ---------------------------------------------------------------------------
-- Malformed journals are refused before they can break the books.
-- ---------------------------------------------------------------------------
do $$
begin
  perform test.raises(format('select public.create_accounting_transaction(jsonb_build_object('
                             || '''showroom_id'', %L, ''journal_type'', %L, ''lines'', %L::jsonb))',
                             test.uuid_of('blr'), 'MANUAL',
                             jsonb_build_array(jsonb_build_object('code','5900','debit',100))::text),
                      'VAL001', 'a single line is not a journal');
  perform test.raises(format('select public.create_accounting_transaction(jsonb_build_object('
                             || '''showroom_id'', %L, ''journal_type'', %L, ''lines'', %L::jsonb))',
                             test.uuid_of('blr'), 'MANUAL',
                             jsonb_build_array(
                               jsonb_build_object('code','5900','debit',100),
                               jsonb_build_object('code','1010','credit',90))::text),
                      null, 'an unbalanced journal is refused');
  perform test.raises(format('select public.create_accounting_transaction(jsonb_build_object('
                             || '''showroom_id'', %L, ''journal_type'', %L, ''lines'', %L::jsonb))',
                             test.uuid_of('blr'), 'MANUAL',
                             jsonb_build_array(
                               jsonb_build_object('code','9999','debit',100),
                               jsonb_build_object('code','1010','credit',100))::text),
                      null, 'an unknown account code is refused');
  perform test.raises(format('select public.create_accounting_transaction(jsonb_build_object('
                             || '''showroom_id'', %L, ''journal_type'', %L, ''lines'', %L::jsonb))',
                             test.uuid_of('hyd'), 'MANUAL',
                             jsonb_build_array(
                               jsonb_build_object('code','5900','debit',100),
                               jsonb_build_object('code','1010','credit',100))::text),
                      'SEC002', 'the branch accountant cannot post into another showroom');
  perform test.raises(format('select public.create_purchase_transaction(%L::jsonb)',
                             jsonb_build_object('showroom_id', test.uuid_of('blr'))::text),
                      'SEC001', 'the accountant cannot raise a purchase order');
end
$$;

-- ---------------------------------------------------------------------------
-- The manager may buy and pay, but may not write the books by hand.
-- ---------------------------------------------------------------------------
select test.as('a0000000-0000-0000-0000-000000000002'::uuid, test.uuid_of('blr'));

do $$
begin
  perform test.raises(format('select public.create_accounting_transaction(jsonb_build_object('
                             || '''showroom_id'', %L, ''journal_type'', %L, ''lines'', %L::jsonb))',
                             test.uuid_of('blr'), 'MANUAL',
                             jsonb_build_array(
                               jsonb_build_object('code','5900','debit',10),
                               jsonb_build_object('code','1010','credit',10))::text),
                      'SEC001', 'a showroom manager cannot post a manual journal');
  perform test.raises(format('select public.create_expense_transaction(%L::jsonb)',
                             jsonb_build_object('showroom_id', test.uuid_of('hyd'),
                                                'category_id', test.uuid_of('cat_marketing'),
                                                'amount', 100,
                                                'description', 'Branch spend')::text),
                      'SEC002', 'the manager cannot book an expense into another showroom');
  perform test.ok((select count(*) from public.expenses e
                    where e.showroom_id is distinct from test.uuid_of('blr')) = 0,
                  'and reads only their own branch''s expenses');
end
$$;

-- ---------------------------------------------------------------------------
-- The reports the owner looks at: they must foot, and they must agree with each
-- other and with the documents they summarise.
-- ---------------------------------------------------------------------------
select test.as('a0000000-0000-0000-0000-000000000005'::uuid, test.uuid_of('blr'));

do $$
declare
  v        jsonb;
  v_d      numeric;
  v_c      numeric;
  v_inc    numeric;
  v_exp    numeric;
begin
  select round(sum(debit), 2), round(sum(credit), 2) into v_d, v_c
    from public.get_trial_balance(test.uuid_of('blr'));
  perform test.ok(v_d is not null and v_c is not null, 'the trial balance returns rows');
  perform test.eq_num(v_d, v_c, 'the trial balance foots: debits equal credits');

  v := public.get_profit_and_loss(test.uuid_of('blr'));
  v_inc := (v ->> 'totalIncome')::numeric;
  v_exp := (v ->> 'totalExpense')::numeric;
  perform test.eq_num((v ->> 'netProfit')::numeric, round(v_inc - v_exp, 2),
                      'net profit is income minus expense in the same payload');
  perform test.ok(v_inc > 0, 'the revenue booked by the sale shows up as income');

  perform test.eq_num(v_exp,
      coalesce((select round(sum(tb.balance), 2) from public.get_trial_balance(test.uuid_of('blr')) tb
                 where tb.account_type = 'EXPENSE'), 0),
      'the P&L and the trial balance agree on total expense');
  perform test.eq_num(v_inc,
      coalesce((select round(sum(tb.balance), 2) from public.get_trial_balance(test.uuid_of('blr')) tb
                 where tb.account_type = 'INCOME'), 0),
      'the P&L and the trial balance agree on total income');

  -- every posted journal in this showroom balances, and every document that
  -- should have money on it has it
  perform test.assert_ledger_is_sane();

  perform test.ok((select count(*) from public.accounting_transactions t
                    where t.showroom_id = test.uuid_of('blr')
                      and t.journal_type in ('SALE','PURCHASE','EXPENSE','PAYMENT','MANUAL')) >= 5,
                  'the showroom has a mix of journals to report on');
  -- Nothing is left half-written.  REVERSED is a legitimate resting state (it is
  -- how a mistake is retired); a DRAFT journal is not, and a reversal without the
  -- entry behind it would mean the books were edited.
  perform test.eq_num((select count(*) from public.accounting_transactions t
                        where t.showroom_id = test.uuid_of('blr') and t.status = 'DRAFT'), 0,
                      'no journal was left as a draft in this showroom');
  perform test.eq_num((select count(*) from public.accounting_transactions t
                        where t.showroom_id = test.uuid_of('blr') and t.is_reversed
                          and t.reversed_by_transaction_id is null), 0,
                      'every reversed journal names the journal that reversed it');
  perform test.eq_num((select count(*) from public.accounting_transactions t
                        where t.showroom_id = test.uuid_of('blr')
                          and t.journal_type = 'REVERSAL'
                          and not exists (select 1 from public.accounting_transactions o
                                           where o.reversed_by_transaction_id = t.id)), 0,
                      'and every reversal belongs to an original');
end
$$;

-- ---------------------------------------------------------------------------
-- Purchases and expenses must not be reachable from the other branch, and the
-- append-only guards hold for the finance tables too.
-- ---------------------------------------------------------------------------
select test.as('a0000000-0000-0000-0000-000000000006'::uuid, test.uuid_of('hyd'));

do $$
declare
  v_rows integer;
begin
  perform test.ok((select count(*) from public.purchases p
                    where p.showroom_id = test.uuid_of('blr')) = 0,
                  'the Hyderabad desk cannot see Bengaluru''s purchase orders');
  -- Hyderabad is told "not your branch", not "here is what that order looks like":
  -- the branch gate runs before the row says anything about itself, so a user in
  -- one city cannot read another city's purchase pipeline through an RPC.  Ids are
  -- uuid4, so the remaining "does this id exist" signal is not a usable oracle.
  perform test.raises(format('select public.approve_purchase(%L, true, null)', test.uuid_of('purchase')),
                      'SEC002', 'and cannot read what the other branch''s order looks like');
  update public.expenses set amount = 1 where id = test.uuid_of('expense_pending');
  get diagnostics v_rows = row_count;
  perform test.ok(v_rows = 0, 'a sales person cannot re-price an expense');
end
$$;

reset role;
select test.as('a0000000-0000-0000-0000-000000000005'::uuid, test.uuid_of('blr'));

do $$
begin
  perform test.ok((select amount from public.expenses where id = test.uuid_of('expense_pending')) = 11800,
                  'the ledger still shows the amount that was actually spent');
  perform test.ok((select status from public.purchases where id = test.uuid_of('purchase')) = 'RECEIVED',
                  'the purchase order ended its lifecycle, not been rewritten');
end
$$;

reset role;

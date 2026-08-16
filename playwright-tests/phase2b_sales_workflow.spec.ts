import * as fs from 'node:fs';
import * as path from 'node:path';

import {
  expect,
  test,
  type APIRequestContext,
  type Page,
} from '@playwright/test';

import {
  signInLocalUserAndPrimeBrowser,
  type LocalSupabaseRuntime,
} from './helpers/local_supabase_auth';

test.setTimeout(420_000);

type Row = Record<string, unknown>;
type WorkflowSnapshot = {
  order?: Row | null;
  items?: Row[];
  logistics?: Row[];
  invoices?: Row[];
  payments?: Row[];
  movements?: Row[];
  journalEntries?: Row[];
  auditTrail?: Row[];
  reconciliation?: Row[];
  opportunity?: Row | null;
};

type TestContext = {
  companyId: string;
  userId: string;
  userName: string;
};

type StockState = {
  kind: 'product';
  itemId: string;
  warehouseId: string;
  quantity: number;
  value: number;
};

type CarState = {
  kind: 'car';
  itemId: string;
  warehouseId: string;
  status: string;
  cost: number;
};

type ItemState = StockState | CarState;

const artifactRoot = path.resolve('playwright-artifacts/phase-2b/sales');

function requiredEnv(name: string): string {
  const value = process.env[name]?.trim() ?? '';
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}

function text(value: unknown): string {
  return value?.toString().trim() ?? '';
}

function lower(value: unknown): string {
  return text(value).toLowerCase();
}

function numberValue(value: unknown): number {
  if (typeof value === 'number') return value;
  return Number.parseFloat(text(value).replaceAll(',', '')) || 0;
}

function value(row: Row, ...keys: string[]): unknown {
  for (const key of keys) {
    if (row[key] !== undefined && row[key] !== null) return row[key];
  }
  return undefined;
}

function rows(value: unknown): Row[] {
  return Array.isArray(value)
    ? value.filter((entry): entry is Row => Boolean(entry) && typeof entry === 'object')
    : [];
}

function headers(runtime: LocalSupabaseRuntime, accessToken: string) {
  return {
    apikey: runtime.publishableKey,
    Authorization: `Bearer ${accessToken}`,
    'Content-Type': 'application/json',
  };
}

async function rpc<T>(options: {
  request: APIRequestContext;
  runtime: LocalSupabaseRuntime;
  accessToken: string;
  name: string;
  data?: Row;
}): Promise<T> {
  const response = await options.request.post(
    `${options.runtime.supabaseUrl}/rest/v1/rpc/${options.name}`,
    {
      headers: headers(options.runtime, options.accessToken),
      data: options.data ?? {},
    },
  );
  const body = await response.text();
  if (!response.ok()) {
    throw new Error(
      `Local RPC ${options.name} failed: HTTP ${response.status()} ${body}`,
    );
  }
  return JSON.parse(body) as T;
}

async function restRows(options: {
  request: APIRequestContext;
  runtime: LocalSupabaseRuntime;
  accessToken: string;
  table: string;
  query?: string;
}): Promise<Row[]> {
  const suffix = options.query ? `?${options.query}` : '';
  const response = await options.request.get(
    `${options.runtime.supabaseUrl}/rest/v1/${options.table}${suffix}`,
    { headers: headers(options.runtime, options.accessToken) },
  );
  const body = await response.text();
  if (!response.ok()) {
    throw new Error(
      `Local REST ${options.table} failed: HTTP ${response.status()} ${body}`,
    );
  }
  return rows(JSON.parse(body));
}

function companyCandidate(payload: Row): string {
  const direct = text(
    payload.companyId ?? payload.company_id ?? payload.currentCompanyId ?? payload.current_company_id,
  );
  if (direct) return direct;
  const company = payload.company;
  if (company && typeof company === 'object') {
    return text((company as Row).id ?? (company as Row).companyId);
  }
  return '';
}

async function resolveTestContext(options: {
  request: APIRequestContext;
  runtime: LocalSupabaseRuntime;
  accessToken: string;
}): Promise<TestContext> {
  const bootstrap = await rpc<Row>({
    ...options,
    name: 'erp_bootstrap_current_user_access',
  });
  expect(bootstrap.ok, 'Authenticated access bootstrap failed').toBe(true);
  const user = (bootstrap.user ?? {}) as Row;
  const explicitCompany = process.env.E2E_COMPANY_ID?.trim() ?? '';
  let companyId = explicitCompany || companyCandidate(bootstrap) || companyCandidate(user);

  if (!companyId) {
    const companies = await restRows({
      ...options,
      table: 'companies',
      query: 'select=id,slug&is_active=eq.true&limit=5',
    });
    if (companies.length !== 1) {
      throw new Error(
        `Unable to resolve one local E2E company from the authenticated session. ` +
          `Visible active companies=${companies.length}; set E2E_COMPANY_ID for this local runtime.`,
      );
    }
    companyId = text(companies[0].id);
  }

  const userId = text(user.id);
  const userName = text(user.fullName ?? user.full_name ?? user.username);
  if (!companyId || !userId || !userName) {
    throw new Error('Local access bootstrap did not expose company/user identity required by Phase 2B.');
  }
  return { companyId, userId, userName };
}

async function waitForFlutter(page: Page): Promise<void> {
  await page.waitForSelector('#boot', { state: 'detached', timeout: 90_000 }).catch(() => undefined);
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 45_000 });
}

async function enableSemantics(page: Page): Promise<void> {
  const placeholder = page.locator('flt-semantics-placeholder').first();
  if ((await placeholder.count()) > 0) {
    await placeholder.evaluate((element: HTMLElement) => element.click());
  }
  await page.waitForTimeout(450);
}

async function openCustomerService(page: Page, appUrl: string): Promise<void> {
  await page.goto(`${appUrl}#/customer-service`, { waitUntil: 'domcontentloaded' });
  await waitForFlutter(page);
  await expect.poll(() => page.url(), { timeout: 45_000 }).toContain('#/customer-service');
  await enableSemantics(page);
  await expect(
    page.getByRole('button', { name: /^(New opportunity|فرصة جديدة)$/i }),
  ).toBeVisible({ timeout: 30_000 });
}

async function chooseDropdown(
  page: Page,
  label: RegExp,
  option: string,
): Promise<void> {
  const field = page.getByLabel(label).last();
  await expect(field).toBeVisible({ timeout: 20_000 });
  await field.click();
  const item = page.getByText(option, { exact: true }).last();
  await expect(item).toBeVisible({ timeout: 15_000 });
  await item.click();
}

async function fillOpportunityAndOpenSalesDraft(options: {
  page: Page;
  marker: string;
  currency: 'USD' | 'IQD';
  expectedValue: string;
  responsibleUser: string;
}): Promise<void> {
  const { page } = options;
  await page.getByRole('button', { name: /^(New opportunity|فرصة جديدة)$/i }).click();

  await page.getByLabel(/^(Customer name|اسم العميل)$/i).fill(`E2E Customer ${options.marker}`);
  await page.getByLabel(/^(Opportunity title \(optional\)|عنوان الفرصة \(اختياري\))$/i).fill(options.marker);
  await page.getByLabel(/^(Expected value \(optional\)|القيمة المتوقعة \(اختيارية\))$/i).fill(options.expectedValue);

  if (options.currency === 'IQD') {
    await chooseDropdown(page, /^(Opportunity currency|عملة الفرصة)$/i, 'IQD');
  }
  await chooseDropdown(
    page,
    /^(Responsible user \(optional\)|المستخدم المسؤول \(اختياري\))$/i,
    options.responsibleUser,
  );

  await page
    .getByRole('button', {
      name: /^(Save & Create Sales Draft|Save and Create Sales Draft|حفظ وإنشاء مسودة أمر بيع)$/i,
    })
    .click();

  await expect(
    page.getByRole('button', { name: /^(Save draft|حفظ كمسودة)$/i }),
  ).toBeVisible({ timeout: 30_000 });
  const exchangeRate = page.getByLabel(
    /^(Exchange rate \(IQD per USD\)|سعر الصرف \(دينار لكل دولار\))$/i,
  );
  if (await exchangeRate.count()) await exchangeRate.fill('1300');
  await page.getByRole('button', { name: /^(Add item|إضافة بند)$/i }).click();
  await expect(page.getByLabel(/^(Quantity|الكمية)$/i).last()).toBeVisible();
  await page.getByRole('button', { name: /^(Save draft|حفظ كمسودة)$/i }).click();
}

async function listOpportunities(options: {
  request: APIRequestContext;
  runtime: LocalSupabaseRuntime;
  accessToken: string;
  companyId: string;
}): Promise<Row[]> {
  return rpc<Row[]>({
    ...options,
    name: 'erp_r84_list_opportunities',
    data: { p_company_id: options.companyId },
  });
}

async function findOpportunityByTitle(
  options: {
    request: APIRequestContext;
    runtime: LocalSupabaseRuntime;
    accessToken: string;
    companyId: string;
  },
  title: string,
): Promise<Row> {
  let found: Row | undefined;
  await expect
    .poll(
      async () => {
        found = (await listOpportunities(options)).find((row) => text(row.title) === title);
        return Boolean(found);
      },
      { timeout: 30_000, message: `Opportunity ${title} was not persisted/read back` },
    )
    .toBe(true);
  return found!;
}

async function workflowSnapshot(options: {
  request: APIRequestContext;
  runtime: LocalSupabaseRuntime;
  accessToken: string;
  companyId: string;
  orderId: string;
}): Promise<WorkflowSnapshot> {
  return rpc<WorkflowSnapshot>({
    ...options,
    name: 'erp_r62_get_commercial_order_snapshot',
    data: {
      p_company_id: options.companyId,
      p_order_id: options.orderId,
      p_purchase: false,
    },
  });
}

function activeRow(list: Row[] | undefined): Row | undefined {
  return (list ?? []).find((row) => {
    const status = lower(row.status);
    return !['cancelled', 'canceled', 'voided', 'deleted'].includes(status);
  });
}

function allocations(document: Row | undefined): Row[] {
  if (!document) return [];
  const direct = rows(document.allocations);
  if (direct.length) return direct;
  const payload = document.payload;
  return payload && typeof payload === 'object' ? rows((payload as Row).allocations) : [];
}

async function readItemState(options: {
  request: APIRequestContext;
  runtime: LocalSupabaseRuntime;
  accessToken: string;
  companyId: string;
  itemType: string;
  itemId: string;
  warehouseId: string;
}): Promise<ItemState> {
  if (options.itemType === 'car') {
    const carRows = await restRows({
      ...options,
      table: 'erp_cars',
      query: `select=*&company_id=eq.${encodeURIComponent(options.companyId)}&id=eq.${encodeURIComponent(options.itemId)}&limit=1`,
    });
    if (carRows.length !== 1) throw new Error(`Car ${options.itemId} is not readable after Sales selection.`);
    const car = carRows[0];
    return {
      kind: 'car',
      itemId: options.itemId,
      warehouseId: text(value(car, 'warehouse_id', 'warehouseId')),
      status: lower(car.status),
      cost: numberValue(value(car, 'purchase_cost', 'purchaseCost', 'cost', 'unit_cost')),
    };
  }

  const stockRows = await restRows({
    ...options,
    table: 'erp_warehouse_stock',
    query: `select=*&company_id=eq.${encodeURIComponent(options.companyId)}`,
  });
  const matches = stockRows.filter(
    (row) =>
      text(value(row, 'product_id', 'productId', 'inventory_id', 'inventoryId')) === options.itemId &&
      text(value(row, 'warehouse_id', 'warehouseId')) === options.warehouseId,
  );
  const quantity = matches.reduce((sum, row) => sum + numberValue(row.quantity), 0);
  const stockValue = matches.reduce((sum, row) => {
    const q = numberValue(row.quantity);
    const unitCost = numberValue(
      value(row, 'average_unit_cost', 'averageUnitCost', 'unit_cost', 'unitCost'),
    );
    return sum + q * unitCost;
  }, 0);
  return { kind: 'product', itemId: options.itemId, warehouseId: options.warehouseId, quantity, value: stockValue };
}

async function cashState(options: {
  request: APIRequestContext;
  runtime: LocalSupabaseRuntime;
  accessToken: string;
  companyId: string;
}): Promise<{ accounts: Row[]; transactions: Row[] }> {
  const [accounts, transactions] = await Promise.all([
    restRows({ ...options, table: 'erp_cash_accounts', query: `select=*&company_id=eq.${encodeURIComponent(options.companyId)}` }),
    restRows({ ...options, table: 'erp_cash_transactions', query: `select=*&company_id=eq.${encodeURIComponent(options.companyId)}` }),
  ]);
  return { accounts, transactions };
}

function cashBalances(state: { accounts: Row[] }): Map<string, number> {
  return new Map(
    state.accounts.map((row) => [text(row.id), numberValue(value(row, 'balance', 'current_balance', 'currentBalance'))]),
  );
}

function assertNoDownstreamEffects(snapshot: WorkflowSnapshot): void {
  expect(activeRow(snapshot.logistics), 'Approval must not implicitly create Delivery').toBeUndefined();
  expect(activeRow(snapshot.invoices), 'Approval must not implicitly create Invoice').toBeUndefined();
  expect(snapshot.payments ?? [], 'Approval must not create Payment').toHaveLength(0);
  expect(snapshot.movements ?? [], 'Approval must not move Inventory').toHaveLength(0);
  expect(snapshot.journalEntries ?? [], 'Approval must not post commercial accounting').toHaveLength(0);
}

async function clickAction(page: Page, name: RegExp): Promise<void> {
  const action = page.getByRole('button', { name }).last();
  await expect(action).toBeVisible({ timeout: 30_000 });
  await action.click();
}

for (const currency of ['USD', 'IQD'] as const) {
  test(`Phase 2B real Sales cycle with backend invariants — ${currency}`, async ({
    page,
    request,
    baseURL,
  }) => {
    fs.mkdirSync(path.join(artifactRoot, currency), { recursive: true });
    const appUrl = baseURL ?? 'http://127.0.0.1:8080';
    const email = requiredEnv('E2E_ADMIN_EMAIL');
    const password = requiredEnv('E2E_ADMIN_PASSWORD');

    const compiled = await request.get(`${appUrl}/main.dart.js`, { timeout: 20_000 });
    expect(compiled.ok(), 'Served Flutter build is unavailable/stale').toBeTruthy();

    const { runtime, session } = await signInLocalUserAndPrimeBrowser({
      request,
      page,
      email,
      password,
    });
    const accessToken = session.access_token;
    const context = await resolveTestContext({ request, runtime, accessToken });
    const backend = { request, runtime, accessToken, companyId: context.companyId };
    const marker = `R86-P2B-${currency}-${Date.now()}`;
    const expectedValue = currency === 'USD' ? '1000' : '1500000';

    console.log(`[phase2b:${currency}] 1/9 create Opportunity and Sales draft through Flutter UI`);
    await openCustomerService(page, appUrl);
    await fillOpportunityAndOpenSalesDraft({
      page,
      marker,
      currency,
      expectedValue,
      responsibleUser: context.userName,
    });

    const opportunity = await findOpportunityByTitle(backend, marker);
    expect(text(opportunity.customerId), 'Opportunity customer missing').not.toBe('');
    expect(text(opportunity.assignedUserId), 'Responsible user was not persisted').toBe(context.userId);
    expect(text(opportunity.currency)).toBe(currency);
    expect(numberValue(opportunity.expectedValue)).toBe(numberValue(expectedValue));
    expect(lower(opportunity.status)).toBe('pending');
    expect(lower(opportunity.stage)).toBe('new');
    expect(text(opportunity.salesOrderId), 'Opportunity ↔ Sales linkage missing').not.toBe('');
    expect(text(opportunity.salesOrderNumber), 'Sales business reference missing').not.toBe('');

    const orderId = text(opportunity.salesOrderId);
    const draft = await workflowSnapshot({ ...backend, orderId });
    const order = draft.order ?? {};
    expect(text(order.id)).toBe(orderId);
    expect(text(value(order, 'customerId', 'customer_id'))).toBe(text(opportunity.customerId));
    expect(text(order.currency)).toBe(currency);
    expect(text(value(order, 'opportunityId', 'opportunity_id'))).toBe(text(opportunity.id));
    expect(text(value(order, 'orderNumber', 'order_number')), 'Sales Order reference missing').not.toBe('');
    expect(lower(order.status)).toBe('draft');
    assertNoDownstreamEffects(draft);
    expect(draft.items ?? [], 'Sales order must contain a real product/car').toHaveLength(1);
    const item = draft.items![0];
    const itemType = text(value(item, 'itemType', 'item_type')) || 'product';
    const itemId = text(value(item, 'itemId', 'item_id'));
    const orderedQuantity = numberValue(item.quantity);
    expect(['product', 'car']).toContain(itemType);
    expect(itemId, 'Product/car identity missing').not.toBe('');
    expect(orderedQuantity).toBeGreaterThan(0);

    console.log(`[phase2b:${currency}] 2/9 open linked Sales Order and approve only`);
    await page.reload({ waitUntil: 'domcontentloaded' });
    await waitForFlutter(page);
    await enableSemantics(page);
    await expect(page.getByPlaceholder(/Search by opportunity|البحث برقم الفرصة/i)).toBeVisible({ timeout: 30_000 });
    await page.getByPlaceholder(/Search by opportunity|البحث برقم الفرصة/i).fill(marker);
    await clickAction(page, /^(Open sales order|فتح أمر البيع)$/i);
    await clickAction(page, /^(Approve sales order|تصديق أمر البيع)$/i);

    const approved = await expect
      .poll(async () => workflowSnapshot({ ...backend, orderId }), { timeout: 30_000 })
      .toMatchObject({ order: expect.objectContaining({ status: 'approved' }) });
    void approved;
    const afterApproval = await workflowSnapshot({ ...backend, orderId });
    assertNoDownstreamEffects(afterApproval);

    console.log(`[phase2b:${currency}] 3/9 create Delivery draft; inventory must remain unchanged`);
    await clickAction(page, /^(Create warehouse delivery|إنشاء إذن التجهيز المخزني)$/i);
    await clickAction(page, /^(Approve allocation|اعتماد التوزيع)$/i);
    const deliveryDraft = await workflowSnapshot({ ...backend, orderId });
    const delivery = activeRow(deliveryDraft.logistics);
    expect(delivery, 'Delivery draft missing in backend').toBeDefined();
    expect(['draft', 'pending_approval']).toContain(lower(delivery!.status));
    expect(text(value(delivery!, 'deliveryNumber', 'documentNumber', 'document_number')), 'Delivery reference missing').not.toBe('');
    expect(activeRow(deliveryDraft.invoices), 'Delivery draft must not create Invoice').toBeUndefined();
    expect(deliveryDraft.movements ?? [], 'Delivery draft must not move inventory').toHaveLength(0);
    expect(deliveryDraft.journalEntries ?? [], 'Delivery draft must not post accounting').toHaveLength(0);
    expect(deliveryDraft.payments ?? [], 'Delivery draft must not create payment').toHaveLength(0);

    const allocation = allocations(delivery).find(
      (row) => text(value(row, 'itemId', 'item_id')) === itemId,
    );
    expect(allocation, 'Delivery allocation for the exact Sales item is missing').toBeDefined();
    const warehouseId = text(value(allocation!, 'warehouseId', 'warehouse_id'));
    expect(warehouseId, 'Warehouse identity missing from Delivery').not.toBe('');
    const inventoryBeforeDelivery = await readItemState({
      ...backend,
      itemType,
      itemId,
      warehouseId,
    });

    console.log(`[phase2b:${currency}] 4/9 approve Delivery; inventory must change here and only here`);
    await clickAction(page, /^(Approve warehouse delivery|تصديق التجهيز المخزني)$/i);
    const afterDelivery = await workflowSnapshot({ ...backend, orderId });
    expect(['approved', 'posted', 'completed', 'confirmed']).toContain(
      lower(activeRow(afterDelivery.logistics)?.status),
    );
    expect(afterDelivery.movements?.length ?? 0, 'Approved Delivery must create warehouse movement').toBeGreaterThan(0);
    expect(activeRow(afterDelivery.invoices), 'Delivery approval must not create Invoice').toBeUndefined();
    expect(afterDelivery.journalEntries ?? [], 'Delivery approval must not post commercial invoice accounting').toHaveLength(0);
    expect(afterDelivery.payments ?? [], 'Delivery approval must not create Payment').toHaveLength(0);

    const inventoryAfterDelivery = await readItemState({
      ...backend,
      itemType,
      itemId,
      warehouseId,
    });
    if (inventoryBeforeDelivery.kind === 'product' && inventoryAfterDelivery.kind === 'product') {
      expect(inventoryAfterDelivery.quantity).toBe(inventoryBeforeDelivery.quantity - orderedQuantity);
      expect(inventoryBeforeDelivery.value, 'Product selected for Phase 2B has no inventory valuation').toBeGreaterThan(0);
      expect(inventoryAfterDelivery.value, 'Inventory value must fall only on approved Delivery').toBeLessThan(inventoryBeforeDelivery.value);
    } else if (inventoryBeforeDelivery.kind === 'car' && inventoryAfterDelivery.kind === 'car') {
      expect(inventoryBeforeDelivery.itemId).toBe(inventoryAfterDelivery.itemId);
      expect(inventoryAfterDelivery.status, 'Vehicle lifecycle must change on approved Delivery').not.toBe(inventoryBeforeDelivery.status);
      expect(inventoryAfterDelivery.cost, 'Vehicle cost identity must remain valued').toBe(inventoryBeforeDelivery.cost);
    } else {
      throw new Error('Inventory identity changed type during Sales Delivery.');
    }

    console.log(`[phase2b:${currency}] 5/9 create Invoice draft; no posting/payment yet`);
    await clickAction(page, /^(Create sales invoice draft|إنشاء مسودة فاتورة بيع)$/i);
    const invoiceDraftSnapshot = await workflowSnapshot({ ...backend, orderId });
    const invoiceDraft = activeRow(invoiceDraftSnapshot.invoices);
    expect(invoiceDraft, 'Invoice draft missing in backend').toBeDefined();
    expect(['draft', 'pending_approval']).toContain(lower(invoiceDraft!.status));
    expect(text(value(invoiceDraft!, 'invoiceNumber', 'documentNumber', 'document_number')), 'Invoice reference missing').not.toBe('');
    expect(invoiceDraftSnapshot.journalEntries ?? [], 'Invoice creation alone must not post accounting').toHaveLength(0);
    expect(invoiceDraftSnapshot.payments ?? [], 'Invoice creation alone must not create payment').toHaveLength(0);
    const inventoryAtInvoiceDraft = await readItemState({ ...backend, itemType, itemId, warehouseId });
    expect(inventoryAtInvoiceDraft).toEqual(inventoryAfterDelivery);

    console.log(`[phase2b:${currency}] 6/9 approve Invoice; post AR/accounting but not cash`);
    const cashBeforeInvoice = await cashState(backend);
    await clickAction(page, /^(Approve sales invoice|تصديق فاتورة البيع)$/i);
    const invoiced = await workflowSnapshot({ ...backend, orderId });
    const invoice = activeRow(invoiced.invoices)!;
    expect(lower(invoice.status)).toBe('approved');
    expect(invoiced.journalEntries?.length ?? 0, 'Invoice approval must post commercial accounting/AR').toBeGreaterThan(0);
    expect(invoiced.payments ?? [], 'Invoice approval must not create Payment').toHaveLength(0);
    expect(numberValue(value(invoice, 'paidAmount', 'paid_amount'))).toBe(0);
    expect(numberValue(value(invoice, 'remainingAmount', 'remaining_amount')), 'Approved invoice must create customer receivable').toBeGreaterThan(0);
    const cashAfterInvoice = await cashState(backend);
    expect(cashAfterInvoice.transactions.length, 'Invoice approval must not create cash transaction').toBe(cashBeforeInvoice.transactions.length);
    expect(cashBalances(cashAfterInvoice)).toEqual(cashBalances(cashBeforeInvoice));
    const inventoryAfterInvoice = await readItemState({ ...backend, itemType, itemId, warehouseId });
    expect(inventoryAfterInvoice).toEqual(inventoryAfterDelivery);

    console.log(`[phase2b:${currency}] 7/9 record customer Payment through Cashbox UI`);
    await clickAction(page, /^(Record customer payment|تسجيل دفعة عميل)$/i);
    await expect(
      page.getByRole('button', { name: /^(Register all payments|تسجيل جميع الدفعات)$/i }),
    ).toBeVisible({ timeout: 30_000 });
    await page.getByRole('button', { name: /^(Register all payments|تسجيل جميع الدفعات)$/i }).click();

    const paid = await workflowSnapshot({ ...backend, orderId });
    expect(paid.payments?.length ?? 0, 'Payment was not persisted').toBeGreaterThan(0);
    const paidInvoice = activeRow(paid.invoices)!;
    expect(numberValue(value(paidInvoice, 'remainingAmount', 'remaining_amount'))).toBeLessThanOrEqual(0.01);
    expect(numberValue(value(paidInvoice, 'paidAmount', 'paid_amount'))).toBeGreaterThan(0);
    expect(paid.journalEntries?.length ?? 0, 'Payment must keep accounting settlement evidence').toBeGreaterThanOrEqual(invoiced.journalEntries?.length ?? 0);
    const cashAfterPayment = await cashState(backend);
    expect(cashAfterPayment.transactions.length, 'Payment must create a cash transaction').toBeGreaterThan(cashAfterInvoice.transactions.length);
    const beforeBalances = cashBalances(cashAfterInvoice);
    const afterBalances = cashBalances(cashAfterPayment);
    expect(
      [...afterBalances.entries()].some(([id, balance]) => balance !== beforeBalances.get(id)),
      'Payment must change a real cashbox balance',
    ).toBe(true);
    const inventoryAfterPayment = await readItemState({ ...backend, itemType, itemId, warehouseId });
    expect(inventoryAfterPayment).toEqual(inventoryAfterDelivery);

    console.log(`[phase2b:${currency}] 8/9 prove CRM authoritative readback after Payment`);
    const finalOpportunity = await findOpportunityByTitle(backend, marker);
    expect(text(finalOpportunity.salesOrderId)).toBe(orderId);
    expect(text(finalOpportunity.salesOrderNumber)).not.toBe('');
    expect(text(finalOpportunity.deliveryId)).not.toBe('');
    expect(text(finalOpportunity.deliveryNumber)).not.toBe('');
    expect(text(finalOpportunity.invoiceId)).not.toBe('');
    expect(text(finalOpportunity.invoiceNumber)).not.toBe('');
    expect(text(finalOpportunity.invoiceCurrency)).toBe(currency);
    expect(lower(finalOpportunity.paymentStatus)).toBe('paid');
    expect(numberValue(finalOpportunity.remainingAmount)).toBeLessThanOrEqual(0.01);
    expect(finalOpportunity.workflowLinked).toBe(true);
    expect(finalOpportunity.workflowCompleted).toBe(true);

    console.log(`[phase2b:${currency}] 9/9 capture final browser evidence`);
    await page.screenshot({
      path: path.join(artifactRoot, currency, 'final-sales-cycle.png'),
      fullPage: true,
    });
  });
}

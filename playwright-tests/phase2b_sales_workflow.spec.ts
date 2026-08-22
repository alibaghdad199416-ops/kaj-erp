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

type TestContext = { companyId: string; userId: string; userName: string };
type ProductState = {
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
type ItemState = ProductState | CarState;

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

function rows(raw: unknown): Row[] {
  return Array.isArray(raw)
    ? raw.filter((entry): entry is Row => Boolean(entry) && typeof entry === 'object')
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
    throw new Error(`Local RPC ${options.name} failed: HTTP ${response.status()} ${body}`);
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
    throw new Error(`Local REST ${options.table} failed: HTTP ${response.status()} ${body}`);
  }
  return rows(JSON.parse(body));
}

function companyCandidate(payload: Row): string {
  const direct = text(
    payload.companyId ??
      payload.company_id ??
      payload.currentCompanyId ??
      payload.current_company_id,
  );
  if (direct) return direct;
  const company = payload.company;
  return company && typeof company === 'object'
    ? text((company as Row).id ?? (company as Row).companyId)
    : '';
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
  expect(bootstrap.ok).toBe(true);
  const user = (bootstrap.user ?? {}) as Row;
  let companyId =
    process.env.E2E_COMPANY_ID?.trim() ||
    companyCandidate(bootstrap) ||
    companyCandidate(user);
  if (!companyId) {
    const companies = await restRows({
      ...options,
      table: 'companies',
      query: 'select=id,slug&is_active=eq.true&limit=5',
    });
    if (companies.length !== 1) {
      throw new Error(
        `Unable to resolve one local E2E company. Visible active companies=${companies.length}; ` +
          `set E2E_COMPANY_ID for this local runtime.`,
      );
    }
    companyId = text(companies[0].id);
  }
  const userId = text(user.id);
  const userName = text(user.fullName ?? user.full_name ?? user.username);
  if (!companyId || !userId || !userName) {
    throw new Error('Local access bootstrap did not expose required company/user identity.');
  }
  return { companyId, userId, userName };
}

async function waitForFlutter(page: Page): Promise<void> {
  await page
    .waitForSelector('#boot', { state: 'detached', timeout: 90_000 })
    .catch(() => undefined);
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

async function chooseDropdown(page: Page, label: RegExp, option: string): Promise<void> {
  const field = page.getByLabel(label).last();
  await expect(field).toBeVisible({ timeout: 20_000 });
  await field.click();
  const item = page.getByText(option, { exact: true }).last();
  await expect(item).toBeVisible({ timeout: 15_000 });
  await item.click();
}

async function createOpportunityAndSalesDraft(options: {
  page: Page;
  marker: string;
  currency: 'USD' | 'IQD';
  expectedValue: string;
  responsibleUser: string;
}): Promise<void> {
  const { page } = options;
  await page.getByRole('button', { name: /^(New opportunity|فرصة جديدة)$/i }).click();
  await page
    .getByLabel(/^(Customer name|اسم العميل)$/i)
    .fill(`E2E Customer ${options.marker}`);
  await page
    .getByLabel(/^(Opportunity title \(optional\)|عنوان الفرصة \(اختياري\))$/i)
    .fill(options.marker);
  await page
    .getByLabel(/^(Expected value \(optional\)|القيمة المتوقعة \(اختيارية\))$/i)
    .fill(options.expectedValue);
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

async function opportunityByTitle(
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

async function snapshot(options: {
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

async function waitSnapshot(
  load: () => Promise<WorkflowSnapshot>,
  predicate: (value: WorkflowSnapshot) => boolean,
  message: string,
): Promise<WorkflowSnapshot> {
  let current: WorkflowSnapshot = {};
  await expect
    .poll(
      async () => {
        current = await load();
        return predicate(current);
      },
      { timeout: 35_000, message },
    )
    .toBe(true);
  return current;
}

function activeRow(list: Row[] | undefined): Row | undefined {
  return (list ?? []).find(
    (row) => !['cancelled', 'canceled', 'voided', 'deleted'].includes(lower(row.status)),
  );
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
    if (carRows.length !== 1) throw new Error(`Car ${options.itemId} is not readable.`);
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
      text(value(row, 'product_id', 'productId', 'inventory_id', 'inventoryId')) ===
        options.itemId &&
      text(value(row, 'warehouse_id', 'warehouseId')) === options.warehouseId,
  );
  return {
    kind: 'product',
    itemId: options.itemId,
    warehouseId: options.warehouseId,
    quantity: matches.reduce((sum, row) => sum + numberValue(row.quantity), 0),
    value: matches.reduce((sum, row) => {
      const quantity = numberValue(row.quantity);
      const unitCost = numberValue(
        value(row, 'average_unit_cost', 'averageUnitCost', 'unit_cost', 'unitCost'),
      );
      return sum + quantity * unitCost;
    }, 0),
  };
}

async function cashState(options: {
  request: APIRequestContext;
  runtime: LocalSupabaseRuntime;
  accessToken: string;
  companyId: string;
}): Promise<{ accounts: Row[]; transactions: Row[] }> {
  const [accounts, transactions] = await Promise.all([
    restRows({
      ...options,
      table: 'erp_cash_accounts',
      query: `select=*&company_id=eq.${encodeURIComponent(options.companyId)}`,
    }),
    restRows({
      ...options,
      table: 'erp_cash_transactions',
      query: `select=*&company_id=eq.${encodeURIComponent(options.companyId)}`,
    }),
  ]);
  return { accounts, transactions };
}

function cashBalances(state: { accounts: Row[] }): Map<string, number> {
  return new Map(
    state.accounts.map((row) => [
      text(row.id),
      numberValue(value(row, 'balance', 'current_balance', 'currentBalance')),
    ]),
  );
}

function assertNoDownstreamEffects(workflow: WorkflowSnapshot): void {
  expect(activeRow(workflow.logistics), 'Sales Order Approval ≠ Delivery').toBeUndefined();
  expect(activeRow(workflow.invoices), 'Sales Order Approval ≠ Invoice').toBeUndefined();
  expect(workflow.payments ?? [], 'Invoice ≠ Payment').toHaveLength(0);
  expect(workflow.movements ?? [], 'Inventory changes only at approved Sales Delivery').toHaveLength(0);
  expect(workflow.journalEntries ?? [], 'Commercial posting occurs at invoicing').toHaveLength(0);
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
    expect(compiled.ok(), 'Served Flutter build is unavailable').toBeTruthy();

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

    console.log(`[phase2b:${currency}] 1/9 Opportunity → Sales draft`);
    await openCustomerService(page, appUrl);
    await createOpportunityAndSalesDraft({
      page,
      marker,
      currency,
      expectedValue,
      responsibleUser: context.userName,
    });

    const opportunity = await opportunityByTitle(backend, marker);
    expect(text(opportunity.customerId)).not.toBe('');
    expect(text(opportunity.assignedUserId)).toBe(context.userId);
    expect(text(opportunity.currency)).toBe(currency);
    expect(numberValue(opportunity.expectedValue)).toBe(numberValue(expectedValue));
    expect(lower(opportunity.status)).toBe('pending');
    expect(lower(opportunity.stage)).toBe('proposal');
    expect(numberValue(opportunity.probability)).toBeGreaterThanOrEqual(50);
    expect(text(opportunity.salesOrderId), 'Opportunity ↔ Sales linkage missing').not.toBe('');
    expect(text(opportunity.salesOrderNumber), 'Sales business reference missing').not.toBe('');

    const orderId = text(opportunity.salesOrderId);
    const draft = await snapshot({ ...backend, orderId });
    const order = draft.order ?? {};
    expect(text(order.id)).toBe(orderId);
    expect(text(value(order, 'customerId', 'customer_id'))).toBe(text(opportunity.customerId));
    expect(text(order.currency)).toBe(currency);
    expect(text(value(order, 'opportunityId', 'opportunity_id'))).toBe(text(opportunity.id));
    expect(text(value(order, 'orderNumber', 'order_number'))).not.toBe('');
    expect(lower(order.status)).toBe('draft');
    assertNoDownstreamEffects(draft);
    expect(draft.items ?? []).toHaveLength(1);
    const item = draft.items![0];
    const itemType = text(value(item, 'itemType', 'item_type')) || 'product';
    const itemId = text(value(item, 'itemId', 'item_id'));
    const orderedQuantity = numberValue(item.quantity);
    expect(['product', 'car']).toContain(itemType);
    expect(itemId).not.toBe('');
    expect(orderedQuantity).toBeGreaterThan(0);

    console.log(`[phase2b:${currency}] 2/9 Sales Order Approval only`);
    await page.reload({ waitUntil: 'domcontentloaded' });
    await waitForFlutter(page);
    await enableSemantics(page);
    const search = page.getByPlaceholder(/Search by opportunity|البحث برقم الفرصة/i);
    await expect(search).toBeVisible({ timeout: 30_000 });
    await search.fill(marker);
    await clickAction(page, /^(Open sales order|فتح أمر البيع)$/i);
    await clickAction(page, /^(Approve sales order|تصديق أمر البيع)$/i);
    const afterApproval = await waitSnapshot(
      () => snapshot({ ...backend, orderId }),
      (state) => lower(state.order?.status) === 'approved',
      'Sales Order did not become approved in backend',
    );
    assertNoDownstreamEffects(afterApproval);
    const opportunityAfterApproval = await opportunityByTitle(backend, marker);
    expect(lower(opportunityAfterApproval.status)).toBe('pending');
    expect(lower(opportunityAfterApproval.stage)).toBe('negotiation');
    expect(numberValue(opportunityAfterApproval.probability)).toBeGreaterThanOrEqual(70);

    console.log(`[phase2b:${currency}] 3/9 Delivery draft — no inventory delta`);
    await clickAction(page, /^(Create warehouse delivery|إنشاء إذن التجهيز المخزني)$/i);
    await clickAction(page, /^(Approve allocation|اعتماد التوزيع)$/i);
    const deliveryDraft = await waitSnapshot(
      () => snapshot({ ...backend, orderId }),
      (state) => Boolean(activeRow(state.logistics)),
      'Delivery draft was not persisted',
    );
    const delivery = activeRow(deliveryDraft.logistics)!;
    expect(['draft', 'pending_approval']).toContain(lower(delivery.status));
    expect(text(value(delivery, 'deliveryNumber', 'documentNumber', 'document_number'))).not.toBe('');
    expect(activeRow(deliveryDraft.invoices)).toBeUndefined();
    expect(deliveryDraft.movements ?? []).toHaveLength(0);
    expect(deliveryDraft.journalEntries ?? []).toHaveLength(0);
    expect(deliveryDraft.payments ?? []).toHaveLength(0);
    const allocation = allocations(delivery).find(
      (row) => text(value(row, 'itemId', 'item_id')) === itemId,
    );
    expect(allocation).toBeDefined();
    const warehouseId = text(value(allocation!, 'warehouseId', 'warehouse_id'));
    expect(warehouseId).not.toBe('');
    const inventoryBeforeDelivery = await readItemState({
      ...backend,
      itemType,
      itemId,
      warehouseId,
    });

    console.log(`[phase2b:${currency}] 4/9 approve Delivery — inventory changes here`);
    await clickAction(page, /^(Approve warehouse delivery|تصديق التجهيز المخزني)$/i);
    const afterDelivery = await waitSnapshot(
      () => snapshot({ ...backend, orderId }),
      (state) => {
        const status = lower(activeRow(state.logistics)?.status);
        return ['approved', 'posted', 'completed', 'confirmed'].includes(status) &&
          (state.movements?.length ?? 0) > 0;
      },
      'Approved Delivery did not create warehouse movement',
    );
    expect(activeRow(afterDelivery.invoices), 'Delivery ≠ Invoice').toBeUndefined();
    expect(afterDelivery.journalEntries ?? []).toHaveLength(0);
    expect(afterDelivery.payments ?? []).toHaveLength(0);
    const inventoryAfterDelivery = await readItemState({
      ...backend,
      itemType,
      itemId,
      warehouseId,
    });
    if (inventoryBeforeDelivery.kind === 'product' && inventoryAfterDelivery.kind === 'product') {
      expect(inventoryAfterDelivery.quantity).toBe(
        inventoryBeforeDelivery.quantity - orderedQuantity,
      );
      expect(inventoryBeforeDelivery.value, 'Selected product has no inventory valuation').toBeGreaterThan(0);
      expect(inventoryAfterDelivery.value).toBeLessThan(inventoryBeforeDelivery.value);
    } else if (inventoryBeforeDelivery.kind === 'car' && inventoryAfterDelivery.kind === 'car') {
      expect(inventoryAfterDelivery.itemId).toBe(inventoryBeforeDelivery.itemId);
      expect(inventoryAfterDelivery.status).not.toBe(inventoryBeforeDelivery.status);
      expect(inventoryAfterDelivery.cost, 'Vehicle valuation identity changed').toBe(
        inventoryBeforeDelivery.cost,
      );
    } else {
      throw new Error('Product/car identity changed type during Delivery.');
    }
    const opportunityAfterDelivery = await opportunityByTitle(backend, marker);
    expect(lower(opportunityAfterDelivery.stage)).toBe('negotiation');
    expect(numberValue(opportunityAfterDelivery.probability)).toBeGreaterThanOrEqual(80);

    console.log(`[phase2b:${currency}] 5/9 Invoice draft — no journal/cash`);
    await clickAction(page, /^(Create sales invoice draft|إنشاء مسودة فاتورة بيع)$/i);
    const invoiceDraftState = await waitSnapshot(
      () => snapshot({ ...backend, orderId }),
      (state) => Boolean(activeRow(state.invoices)),
      'Invoice draft was not persisted',
    );
    const invoiceDraft = activeRow(invoiceDraftState.invoices)!;
    expect(['draft', 'pending_approval']).toContain(lower(invoiceDraft.status));
    expect(text(value(invoiceDraft, 'invoiceNumber', 'documentNumber', 'document_number'))).not.toBe('');
    expect(invoiceDraftState.journalEntries ?? []).toHaveLength(0);
    expect(invoiceDraftState.payments ?? []).toHaveLength(0);
    expect(await readItemState({ ...backend, itemType, itemId, warehouseId })).toEqual(
      inventoryAfterDelivery,
    );

    console.log(`[phase2b:${currency}] 6/9 approve Invoice — AR/accounting only`);
    const cashBeforeInvoice = await cashState(backend);
    await clickAction(page, /^(Approve sales invoice|تصديق فاتورة البيع)$/i);
    const invoiced = await waitSnapshot(
      () => snapshot({ ...backend, orderId }),
      (state) =>
        lower(activeRow(state.invoices)?.status) === 'approved' &&
        (state.journalEntries?.length ?? 0) > 0,
      'Invoice approval did not post accounting',
    );
    const invoice = activeRow(invoiced.invoices)!;
    expect(invoiced.payments ?? [], 'Invoice ≠ Payment').toHaveLength(0);
    expect(numberValue(value(invoice, 'paidAmount', 'paid_amount'))).toBe(0);
    expect(
      numberValue(value(invoice, 'remainingAmount', 'remaining_amount')),
      'Approved invoice must create customer receivable',
    ).toBeGreaterThan(0);
    const cashAfterInvoice = await cashState(backend);
    expect(cashAfterInvoice.transactions.length).toBe(cashBeforeInvoice.transactions.length);
    expect(cashBalances(cashAfterInvoice)).toEqual(cashBalances(cashBeforeInvoice));
    expect(await readItemState({ ...backend, itemType, itemId, warehouseId })).toEqual(
      inventoryAfterDelivery,
    );
    const opportunityAfterInvoice = await opportunityByTitle(backend, marker);
    expect(lower(opportunityAfterInvoice.status)).toBe('won');
    expect(lower(opportunityAfterInvoice.stage)).toBe('won');
    expect(numberValue(opportunityAfterInvoice.probability)).toBe(100);
    expect(lower(opportunityAfterInvoice.paymentStatus)).toBe('unpaid');

    console.log(`[phase2b:${currency}] 7/9 Payment/Cashbox`);
    await clickAction(page, /^(Record customer payment|تسجيل دفعة عميل)$/i);
    const registerPayments = page.getByRole('button', {
      name: /^(Register all payments|تسجيل جميع الدفعات)$/i,
    });
    await expect(registerPayments).toBeVisible({ timeout: 30_000 });
    await registerPayments.click();
    const paid = await waitSnapshot(
      () => snapshot({ ...backend, orderId }),
      (state) => {
        const currentInvoice = activeRow(state.invoices);
        return (state.payments?.length ?? 0) > 0 &&
          numberValue(value(currentInvoice ?? {}, 'remainingAmount', 'remaining_amount')) <= 0.01;
      },
      'Payment/Cashbox stage did not settle invoice',
    );
    const paidInvoice = activeRow(paid.invoices)!;
    expect(numberValue(value(paidInvoice, 'paidAmount', 'paid_amount'))).toBeGreaterThan(0);
    expect(paid.journalEntries?.length ?? 0).toBeGreaterThanOrEqual(
      invoiced.journalEntries?.length ?? 0,
    );
    const cashAfterPayment = await cashState(backend);
    expect(cashAfterPayment.transactions.length).toBeGreaterThan(
      cashAfterInvoice.transactions.length,
    );
    const beforeBalances = cashBalances(cashAfterInvoice);
    expect(
      [...cashBalances(cashAfterPayment).entries()].some(
        ([id, balance]) => balance !== beforeBalances.get(id),
      ),
      'Payment must change a real cashbox balance',
    ).toBe(true);
    expect(await readItemState({ ...backend, itemType, itemId, warehouseId })).toEqual(
      inventoryAfterDelivery,
    );

    console.log(`[phase2b:${currency}] 8/9 authoritative CRM final readback`);
    const finalOpportunity = await opportunityByTitle(backend, marker);
    expect(text(finalOpportunity.salesOrderId)).toBe(orderId);
    expect(text(finalOpportunity.salesOrderNumber)).not.toBe('');
    expect(text(finalOpportunity.deliveryId)).not.toBe('');
    expect(text(finalOpportunity.deliveryNumber)).not.toBe('');
    expect(text(finalOpportunity.invoiceId)).not.toBe('');
    expect(text(finalOpportunity.invoiceNumber)).not.toBe('');
    expect(text(finalOpportunity.invoiceCurrency)).toBe(currency);
    expect(lower(finalOpportunity.status)).toBe('won');
    expect(lower(finalOpportunity.stage)).toBe('closed');
    expect(numberValue(finalOpportunity.probability)).toBe(100);
    expect(lower(finalOpportunity.paymentStatus)).toBe('paid');
    expect(numberValue(finalOpportunity.remainingAmount)).toBeLessThanOrEqual(0.01);
    expect(finalOpportunity.workflowLinked).toBe(true);
    expect(finalOpportunity.workflowCompleted).toBe(true);

    console.log(`[phase2b:${currency}] 9/9 final browser evidence`);
    await page.screenshot({
      path: path.join(artifactRoot, currency, 'final-sales-cycle.png'),
      fullPage: true,
    });
  });
}

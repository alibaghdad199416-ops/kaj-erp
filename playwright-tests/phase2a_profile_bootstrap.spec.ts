import * as fs from 'node:fs';
import * as path from 'node:path';

import { expect, test, type Page } from '@playwright/test';

import { signInLocalUserAndPrimeBrowser } from './helpers/local_supabase_auth';

test.setTimeout(90_000);

const artifactDir = path.resolve('playwright-artifacts/phase-2a/profile/bootstrap');
const profileBuildMarker = 'quality-line-profile-tooltip-button-v2';

function requiredEnv(name: string): string {
  const value = process.env[name]?.trim() ?? '';
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}

async function enableFlutterSemantics(page: Page): Promise<void> {
  const placeholder = page.locator('flt-semantics-placeholder').first();
  const placeholderCount = await placeholder.count();
  console.log(`[profile-bootstrap] semantics placeholder count=${placeholderCount}`);
  if (placeholderCount > 0) {
    await placeholder.evaluate((element: HTMLElement) => element.click());
  }
  await page.waitForTimeout(500);
}

async function ariaLabels(page: Page): Promise<string[]> {
  return page.locator('[aria-label]').evaluateAll((elements) =>
    elements
      .map((element) => element.getAttribute('aria-label'))
      .filter((value): value is string => Boolean(value))
      .slice(0, 160),
  );
}

async function buttonDiagnostics(page: Page): Promise<Array<{ label: string | null; role: string | null }>> {
  return page.locator('[role="button"]').evaluateAll((elements) =>
    elements.slice(0, 80).map((element) => ({
      label: element.getAttribute('aria-label'),
      role: element.getAttribute('role'),
    })),
  );
}

function profileAction(page: Page) {
  const semanticAction = page
    .locator(
      '[aria-label="Edit profile"], [aria-label="تعديل الملف الشخصي"], [aria-label="User avatar"], [aria-label="صورة المستخدم"]',
    )
    .last();
  return semanticAction.locator('[flt-tappable]');
}

async function waitForStableDashboard(page: Page): Promise<string> {
  await expect
    .poll(
      () => page.url(),
      {
        timeout: 45_000,
        message: 'Protected dashboard did not finish session restoration',
      },
    )
    .toMatch(/#\/dashboard$/);

  let previous = '';
  let stableSamples = 0;
  const deadline = Date.now() + 12_000;
  while (Date.now() < deadline) {
    const current = page.url();
    if (current.includes('#/login')) {
      throw new Error(`Persisted session was rejected and redirected to login: ${current}`);
    }
    if (!/#\/dashboard$/.test(current)) {
      previous = current;
      stableSamples = 0;
    } else if (current === previous) {
      stableSamples += 1;
      if (stableSamples >= 3) return current;
    } else {
      previous = current;
      stableSamples = 0;
    }
    await page.waitForTimeout(750);
  }

  throw new Error(`Authenticated dashboard route did not stabilize. Last URL=${page.url()}`);
}

test('Phase 2A profile bootstrap diagnostic', async ({ page, baseURL, request }) => {
  fs.mkdirSync(artifactDir, { recursive: true });
  const appUrl = baseURL ?? 'http://127.0.0.1:8080';

  console.log('[profile-bootstrap] 1/8 verifying served Flutter build marker');
  const compiledResponse = await request.get(`${appUrl}/main.dart.js`, {
    timeout: 20_000,
  });
  expect(
    compiledResponse.ok(),
    `Unable to read served main.dart.js: HTTP ${compiledResponse.status()}`,
  ).toBeTruthy();
  const compiledJs = await compiledResponse.text();
  expect(
    compiledJs.includes(profileBuildMarker),
    `Served Flutter build is stale. Expected marker ${profileBuildMarker} in main.dart.js. Fetch the current branch, rebuild build\\web, and restart the local server before running E2E.`,
  ).toBeTruthy();
  console.log('[profile-bootstrap] served build marker present=true');

  const email = requiredEnv('E2E_ADMIN_EMAIL');
  const password = requiredEnv('E2E_ADMIN_PASSWORD');

  console.log('[profile-bootstrap] 2/8 obtaining and verifying local Supabase session');
  const { runtime } = await signInLocalUserAndPrimeBrowser({
    request,
    page,
    email,
    password,
  });

  console.log('[profile-bootstrap] 3/8 opening protected Flutter dashboard route');
  await page.goto(`${appUrl}#/dashboard`, {
    waitUntil: 'domcontentloaded',
    timeout: 20_000,
  });

  console.log('[profile-bootstrap] 4/8 waiting for Flutter glass pane');
  await page.waitForSelector('flt-glass-pane', {
    state: 'attached',
    timeout: 45_000,
  });

  const persisted = await page.evaluate((storageKey) => ({
    direct: localStorage.getItem(storageKey),
    flutter: localStorage.getItem(`flutter.${storageKey}`),
  }), runtime.authPersistSessionKey);
  console.log(
    `[profile-bootstrap] storage direct=${persisted.direct !== null} flutter=${persisted.flutter !== null} key=${runtime.authPersistSessionKey}`,
  );
  expect(
    persisted.direct ?? persisted.flutter,
    'Injected Supabase session disappeared from localStorage',
  ).not.toBeNull();

  console.log('[profile-bootstrap] 5/8 waiting for stable authenticated dashboard');
  const stableUrl = await waitForStableDashboard(page);
  console.log(`[profile-bootstrap] stable authenticated url=${stableUrl}`);

  console.log('[profile-bootstrap] 6/8 enabling semantics on the stable dashboard');
  await enableFlutterSemantics(page);

  console.log('[profile-bootstrap] 7/8 locating semantic profile action');
  const action = profileAction(page);
  try {
    await expect(action).toBeVisible({ timeout: 15_000 });
  } catch (error) {
    const labels = await ariaLabels(page);
    const buttons = await buttonDiagnostics(page);
    console.log(
      `[profile-bootstrap] profile semantics missing url=${page.url()} labels=${JSON.stringify(labels)} buttons=${JSON.stringify(buttons)}`,
    );
    throw new Error(
      `Stable authenticated dashboard did not expose the semantic profile action. ` +
        `url=${page.url()}; aria labels=${JSON.stringify(labels)}; buttons=${JSON.stringify(buttons)}; cause=${String(error)}`,
    );
  }

  const labels = await ariaLabels(page);
  console.log(`[profile-bootstrap] first aria labels=${JSON.stringify(labels)}`);
  await page.screenshot({
    path: path.join(artifactDir, '01-workspace.png'),
    fullPage: true,
  });

  console.log('[profile-bootstrap] 8/8 opening and verifying profile dialog');
  await action.click({ timeout: 10_000 });
  const save = page.getByRole('button', {
    name: /^(Save changes|حفظ التغييرات)$/i,
  });
  await expect(save).toBeVisible({ timeout: 15_000 });
  await page.screenshot({
    path: path.join(artifactDir, '02-profile-dialog.png'),
    fullPage: true,
  });
});

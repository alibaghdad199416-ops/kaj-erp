import * as fs from 'node:fs';
import * as path from 'node:path';

import { expect, test } from '@playwright/test';

import { signInLocalUserAndPrimeBrowser } from './helpers/local_supabase_auth';

test.setTimeout(90_000);

const artifactDir = path.resolve('playwright-artifacts/phase-2a/profile/bootstrap');

function requiredEnv(name: string): string {
  const value = process.env[name]?.trim() ?? '';
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}

async function enableFlutterSemantics(page: import('@playwright/test').Page): Promise<void> {
  const placeholder = page.locator('flt-semantics-placeholder').first();
  const placeholderCount = await placeholder.count();
  console.log(`[profile-bootstrap] semantics placeholder count=${placeholderCount}`);
  if (placeholderCount > 0) {
    // Flutter's accessibility placeholder can be intentionally positioned outside
    // the visual viewport. Invoke its native DOM click so the accessibility tree
    // is enabled without relying on pointer geometry.
    await placeholder.evaluate((element: HTMLElement) => element.click());
  }
  await page.waitForTimeout(750);
}

async function ariaLabels(page: import('@playwright/test').Page): Promise<string[]> {
  return page.locator('[aria-label]').evaluateAll((elements) =>
    elements
      .map((element) => element.getAttribute('aria-label'))
      .filter((value): value is string => Boolean(value))
      .slice(0, 80),
  );
}

test('Phase 2A profile bootstrap diagnostic', async ({ page, baseURL, request }) => {
  fs.mkdirSync(artifactDir, { recursive: true });
  const email = requiredEnv('E2E_ADMIN_EMAIL');
  const password = requiredEnv('E2E_ADMIN_PASSWORD');
  const appUrl = baseURL ?? 'http://127.0.0.1:8080';

  console.log('[profile-bootstrap] 1/6 obtaining and verifying local Supabase session');
  const { runtime } = await signInLocalUserAndPrimeBrowser({
    request,
    page,
    email,
    password,
  });

  console.log('[profile-bootstrap] 2/6 opening protected Flutter settings route');
  await page.goto(`${appUrl}#/settings`, {
    waitUntil: 'domcontentloaded',
    timeout: 20_000,
  });

  console.log('[profile-bootstrap] 3/6 waiting for Flutter glass pane');
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

  console.log('[profile-bootstrap] 4/6 enabling Flutter semantics');
  await enableFlutterSemantics(page);

  console.log('[profile-bootstrap] 5/6 waiting for protected-route session restoration');
  const profileAction = page
    .locator(
      '[aria-label="User avatar"], [aria-label="صورة المستخدم"], [aria-label="Edit profile"], [aria-label="تعديل الملف الشخصي"]',
    )
    .last();

  try {
    await expect(profileAction).toBeVisible({ timeout: 45_000 });
  } catch (error) {
    const loginFragment = '#/login';
    const settingsFragment = '#/settings';
    const dashboardFragment = '#/dashboard';
    const currentUrl = () => page.url();
    const labels = await ariaLabels(page);
    console.log(
      `[profile-bootstrap] restore failed url=${currentUrl()} labels=${JSON.stringify(labels)}`,
    );
    throw new Error(
      `Protected-route session restoration did not expose the profile action. ` +
        `url=${currentUrl()} expected route containing ${settingsFragment} or ${dashboardFragment}, ` +
        `not ${loginFragment}; aria labels=${JSON.stringify(labels)}; cause=${String(error)}`,
    );
  }

  const labels = await ariaLabels(page);
  console.log(`[profile-bootstrap] restored url=${page.url()}`);
  console.log(`[profile-bootstrap] first aria labels=${JSON.stringify(labels)}`);

  await page.screenshot({
    path: path.join(artifactDir, '01-workspace.png'),
    fullPage: true,
  });

  console.log('[profile-bootstrap] 6/6 opening and verifying profile dialog');
  await profileAction.click({ timeout: 10_000 });
  const save = page.getByRole('button', {
    name: /^(Save changes|حفظ التغييرات)$/,
  });
  await expect(save).toBeVisible({ timeout: 15_000 });
  await page.screenshot({
    path: path.join(artifactDir, '02-profile-dialog.png'),
    fullPage: true,
  });
});

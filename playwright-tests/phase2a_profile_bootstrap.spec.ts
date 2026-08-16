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

  console.log('[profile-bootstrap] 2/6 opening Flutter settings route');
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
  expect(persisted.direct ?? persisted.flutter, 'Injected Supabase session disappeared from localStorage').not.toBeNull();

  console.log('[profile-bootstrap] 4/6 enabling Flutter semantics');
  const placeholder = page.locator('flt-semantics-placeholder').first();
  const placeholderCount = await placeholder.count();
  console.log(`[profile-bootstrap] semantics placeholder count=${placeholderCount}`);
  if (placeholderCount > 0) await placeholder.click({ timeout: 10_000 });
  await page.waitForTimeout(750);

  const labels = await page.locator('[aria-label]').evaluateAll((elements) =>
    elements
      .map((element) => element.getAttribute('aria-label'))
      .filter((value): value is string => Boolean(value))
      .slice(0, 80),
  );
  console.log(`[profile-bootstrap] first aria labels=${JSON.stringify(labels)}`);

  await page.screenshot({
    path: path.join(artifactDir, '01-workspace.png'),
    fullPage: true,
  });

  console.log('[profile-bootstrap] 5/6 locating profile avatar/action');
  const profileAction = page
    .locator(
      '[aria-label="User avatar"], [aria-label="صورة المستخدم"], [aria-label="Edit profile"], [aria-label="تعديل الملف الشخصي"]',
    )
    .last();
  const count = await profileAction.count();
  console.log(`[profile-bootstrap] profile action count=${count}; url=${page.url()}`);
  expect(
    count,
    `No profile action found. Current URL=${page.url()}; aria labels=${JSON.stringify(labels)}`,
  ).toBeGreaterThan(0);
  await expect(profileAction).toBeVisible({ timeout: 10_000 });
  await profileAction.click({ timeout: 10_000 });

  console.log('[profile-bootstrap] 6/6 verifying profile dialog');
  const save = page.getByRole('button', {
    name: /^(Save changes|حفظ التغييرات)$/,
  });
  await expect(save).toBeVisible({ timeout: 15_000 });
  await page.screenshot({
    path: path.join(artifactDir, '02-profile-dialog.png'),
    fullPage: true,
  });
});

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

test.setTimeout(300_000);

const artifactDir = path.resolve('playwright-artifacts/phase-2a/profile');
const avatar1 = path.resolve('playwright-tests/fixtures/avatar1.png');
const avatar2 = path.resolve('playwright-tests/fixtures/avatar2.png');
const profileBuildMarker = 'quality-line-profile-tooltip-button-v2';

function requiredEnv(name: string): string {
  const value = process.env[name]?.trim() ?? '';
  if (!value) {
    throw new Error(
      `Missing ${name}. Set local E2E credentials in the current shell before running Phase 2A.`,
    );
  }
  return value;
}

function normalizeNullableString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized.length === 0 ? null : normalized;
}

type ProfileSnapshot = {
  fullName: string;
  phone: string;
  avatarBase64: string | null;
};

function profileFromUserPayload(user: Record<string, unknown>): ProfileSnapshot {
  return {
    fullName: String(user.fullName ?? user.full_name ?? '').trim(),
    phone: String(user.phone ?? '').trim(),
    avatarBase64: normalizeNullableString(
      user.avatarBase64 ?? user.avatar_base64 ?? null,
    ),
  };
}

async function verifyServedBuild(options: {
  request: APIRequestContext;
  appUrl: string;
}): Promise<void> {
  const response = await options.request.get(`${options.appUrl}/main.dart.js`, {
    timeout: 20_000,
  });
  expect(
    response.ok(),
    `Unable to read served main.dart.js: HTTP ${response.status()}`,
  ).toBeTruthy();
  const compiledJs = await response.text();
  expect(
    compiledJs.includes(profileBuildMarker),
    `Served Flutter build is stale. Expected marker ${profileBuildMarker} in main.dart.js.`,
  ).toBeTruthy();
}

async function readCurrentProfile(options: {
  request: APIRequestContext;
  runtime: LocalSupabaseRuntime;
  accessToken: string;
}): Promise<ProfileSnapshot> {
  const response = await options.request.post(
    `${options.runtime.supabaseUrl}/rest/v1/rpc/erp_bootstrap_current_user_access`,
    {
      headers: {
        apikey: options.runtime.publishableKey,
        Authorization: `Bearer ${options.accessToken}`,
        'Content-Type': 'application/json',
      },
      data: {},
    },
  );
  const bodyText = await response.text();
  if (!response.ok()) {
    throw new Error(
      `Profile backend read-back failed: HTTP ${response.status()} ${bodyText}`,
    );
  }

  const payload = JSON.parse(bodyText) as Record<string, unknown>;
  if (payload.ok !== true || typeof payload.user !== 'object' || payload.user === null) {
    throw new Error(
      `Profile backend read-back returned an unexpected payload: ${bodyText}`,
    );
  }
  return profileFromUserPayload(payload.user as Record<string, unknown>);
}

async function restoreCurrentProfile(options: {
  request: APIRequestContext;
  runtime: LocalSupabaseRuntime;
  accessToken: string;
  profile: ProfileSnapshot;
}): Promise<void> {
  const response = await options.request.post(
    `${options.runtime.supabaseUrl}/rest/v1/rpc/erp_update_current_user_profile`,
    {
      headers: {
        apikey: options.runtime.publishableKey,
        Authorization: `Bearer ${options.accessToken}`,
        'Content-Type': 'application/json',
      },
      data: {
        p_full_name: options.profile.fullName,
        p_phone: options.profile.phone,
        p_avatar_base64: options.profile.avatarBase64,
      },
    },
  );
  if (!response.ok()) {
    throw new Error(
      `Profile cleanup failed: HTTP ${response.status()} ${await response.text()}`,
    );
  }
}

async function waitForFlutterReady(page: Page): Promise<void> {
  await page.waitForSelector('#boot', { state: 'detached', timeout: 90_000 });
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 30_000 });
}

async function enableFlutterSemantics(page: Page): Promise<void> {
  const placeholder = page.locator('flt-semantics-placeholder').first();
  if ((await placeholder.count()) > 0) {
    await placeholder.evaluate((element: HTMLElement) => element.click());
  }
  await page.waitForTimeout(500);
}

async function waitForStableAuthenticatedWorkspace(page: Page): Promise<void> {
  await expect
    .poll(
      () => page.url(),
      {
        timeout: 45_000,
        message: 'Persisted session did not restore a protected workspace route',
      },
    )
    .toMatch(/#\/(settings|dashboard)$/);

  let previous = '';
  let stableSamples = 0;
  const deadline = Date.now() + 12_000;
  while (Date.now() < deadline) {
    const current = page.url();
    if (current.includes('#/login')) {
      throw new Error(`Persisted session was rejected and redirected to login: ${current}`);
    }
    if (!/#\/(settings|dashboard)$/.test(current)) {
      previous = current;
      stableSamples = 0;
    } else if (current === previous) {
      stableSamples += 1;
      if (stableSamples >= 2) return;
    } else {
      previous = current;
      stableSamples = 0;
    }
    await page.waitForTimeout(750);
  }

  throw new Error(`Authenticated workspace route did not stabilize. Last URL=${page.url()}`);
}

async function waitForRestoredWorkspace(page: Page): Promise<void> {
  await waitForStableAuthenticatedWorkspace(page);
  await enableFlutterSemantics(page);
}

function userAvatar(page: Page) {
  return page
    .locator(
      '[aria-label="Edit profile"], [aria-label="تعديل الملف الشخصي"], [aria-label="User avatar"], [aria-label="صورة المستخدم"]',
    )
    .last();
}

function changePhotoButton(page: Page) {
  return page.getByRole('button', {
    name: /^(Change photo|تغيير الصورة)$/,
  });
}

function removePhotoButton(page: Page) {
  return page.getByRole('button', {
    name: /^(Remove photo|إزالة الصورة)$/,
  });
}

function saveChangesButton(page: Page) {
  return page.getByRole('button', {
    name: /^(Save changes|حفظ التغييرات)$/,
  });
}

async function openProfile(page: Page): Promise<void> {
  const avatar = userAvatar(page);
  await expect(
    avatar,
    'Authenticated workspace did not expose a semantic profile action in the active navigation layout.',
  ).toBeVisible({ timeout: 15_000 });
  await avatar.click({ timeout: 10_000 });
  await expect(saveChangesButton(page)).toBeVisible({ timeout: 20_000 });
}

async function chooseAvatar(page: Page, fixturePath: string): Promise<void> {
  const chooserPromise = page.waitForEvent('filechooser', { timeout: 15_000 });
  await changePhotoButton(page).click();
  const chooser = await chooserPromise;
  await chooser.setFiles(fixturePath);
  await expect(removePhotoButton(page)).toBeVisible({ timeout: 20_000 });
}

async function saveProfile(page: Page): Promise<void> {
  const save = saveChangesButton(page);
  await save.click();
  await expect(save).toBeHidden({ timeout: 20_000 });
}

async function reloadAndOpenProfile(page: Page): Promise<void> {
  await page.reload({ waitUntil: 'domcontentloaded' });
  await waitForFlutterReady(page);
  await waitForRestoredWorkspace(page);
  await openProfile(page);
}

test('Phase 2A profile avatar: add, replace, remove, backend read-back, reload read-back', async ({
  page,
  baseURL,
  request,
}) => {
  fs.mkdirSync(artifactDir, { recursive: true });
  for (const fixture of [avatar1, avatar2]) {
    if (!fs.existsSync(fixture)) {
      throw new Error(`Missing Playwright image fixture: ${fixture}`);
    }
  }

  const email = requiredEnv('E2E_ADMIN_EMAIL');
  const password = requiredEnv('E2E_ADMIN_PASSWORD');
  const appUrl = baseURL ?? 'http://127.0.0.1:8080';

  console.log('[profile] 1/8 verify served build, authenticate and snapshot backend profile');
  await verifyServedBuild({ request, appUrl });
  const { runtime, session } = await signInLocalUserAndPrimeBrowser({
    request,
    page,
    email,
    password,
  });
  const accessToken = session.access_token;
  const originalProfile = await readCurrentProfile({
    request,
    runtime,
    accessToken,
  });

  try {
    console.log('[profile] 2/8 restore stable protected workspace and open profile');
    await page.goto(`${appUrl}#/settings`, { waitUntil: 'domcontentloaded' });
    await waitForFlutterReady(page);
    await waitForRestoredWorkspace(page);
    await openProfile(page);

    console.log('[profile] 3/8 add avatar and prove backend persistence');
    await chooseAvatar(page, avatar1);
    await saveProfile(page);

    const afterAdd = await readCurrentProfile({
      request,
      runtime,
      accessToken,
    });
    expect(afterAdd.avatarBase64, 'Avatar was not persisted after add').not.toBeNull();
    if (originalProfile.avatarBase64 !== null) {
      expect(afterAdd.avatarBase64).not.toBe(originalProfile.avatarBase64);
    }

    console.log('[profile] 4/8 reload and prove add read-back');
    await reloadAndOpenProfile(page);
    await expect(removePhotoButton(page)).toBeVisible();
    await page.screenshot({
      path: path.join(artifactDir, '01-after-add-readback.png'),
      fullPage: true,
    });

    console.log('[profile] 5/8 replace avatar and prove backend persistence');
    await chooseAvatar(page, avatar2);
    await saveProfile(page);

    const afterReplace = await readCurrentProfile({
      request,
      runtime,
      accessToken,
    });
    expect(
      afterReplace.avatarBase64,
      'Avatar was not persisted after replace',
    ).not.toBeNull();
    expect(afterReplace.avatarBase64).not.toBe(afterAdd.avatarBase64);

    console.log('[profile] 6/8 reload and prove replace read-back');
    await reloadAndOpenProfile(page);
    await expect(removePhotoButton(page)).toBeVisible();
    await page.screenshot({
      path: path.join(artifactDir, '02-after-replace-readback.png'),
      fullPage: true,
    });

    console.log('[profile] 7/8 remove avatar and prove backend persistence');
    await removePhotoButton(page).click();
    await expect(removePhotoButton(page)).toBeHidden();
    await saveProfile(page);

    const afterRemove = await readCurrentProfile({
      request,
      runtime,
      accessToken,
    });
    expect(afterRemove.avatarBase64, 'Avatar was not removed in backend').toBeNull();

    await reloadAndOpenProfile(page);
    await expect(removePhotoButton(page)).toBeHidden();
    await page.screenshot({
      path: path.join(artifactDir, '03-after-remove-readback.png'),
      fullPage: true,
    });
  } finally {
    console.log('[profile] 8/8 restore original backend profile');
    await restoreCurrentProfile({
      request,
      runtime,
      accessToken,
      profile: originalProfile,
    });
    const restoredProfile = await readCurrentProfile({
      request,
      runtime,
      accessToken,
    });
    expect(restoredProfile).toEqual(originalProfile);
  }
});

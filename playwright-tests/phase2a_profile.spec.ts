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

test.setTimeout(180_000);

const artifactDir = path.resolve('playwright-artifacts/phase-2a/profile');
const avatar1 = path.resolve('playwright-tests/fixtures/avatar1.png');
const avatar2 = path.resolve('playwright-tests/fixtures/avatar2.png');

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
    await placeholder.click();
  }
  await page.waitForTimeout(250);
}

function userAvatar(page: Page) {
  return page
    .locator('[aria-label="User avatar"], [aria-label="صورة المستخدم"]')
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
    'Authenticated desktop workspace did not expose the user avatar. If the account is using top navigation, profile access is currently missing from that layout and must be fixed instead of bypassed.',
  ).toBeVisible({ timeout: 30_000 });
  await avatar.click();
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
  await enableFlutterSemantics(page);
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
    await page.goto(`${appUrl}#/settings`, { waitUntil: 'domcontentloaded' });
    await waitForFlutterReady(page);
    await enableFlutterSemantics(page);
    await openProfile(page);

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

    await reloadAndOpenProfile(page);
    await expect(removePhotoButton(page)).toBeVisible();
    await page.screenshot({
      path: path.join(artifactDir, '01-after-add-readback.png'),
      fullPage: true,
    });

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

    await reloadAndOpenProfile(page);
    await expect(removePhotoButton(page)).toBeVisible();
    await page.screenshot({
      path: path.join(artifactDir, '02-after-replace-readback.png'),
      fullPage: true,
    });

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

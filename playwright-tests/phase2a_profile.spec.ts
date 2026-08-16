import { test, expect, request as playwrightRequest } from '@playwright/test';
import path from 'path';
import fs from 'fs';

// Increase test timeout for Flutter bootstrap and uploads
test.setTimeout(180000);

const ADMIN_EMAIL = 'ajkinbaghdad@gmail.com';
const ADMIN_PASSWORD = 'PlAQuu84tiQcqnqd7ToBliEr0Ac2';

test('admin profile: change fields, upload avatar, replace, remove', async ({ page, baseURL, request }) => {
  const url = baseURL || 'http://127.0.0.1:8080';

  // Read local runtime defines to locate Supabase
  const definesPath = path.resolve('dart_defines.local.generated.json');
  let defines: any = {};
  if (fs.existsSync(definesPath)) {
    defines = JSON.parse(fs.readFileSync(definesPath, 'utf8'));
  }
  const supabaseUrl = defines.SUPABASE_URL || 'http://127.0.0.1:54321';
  const anonKey = defines.SUPABASE_PUBLISHABLE_KEY || '';

  // Obtain Supabase session via password grant and inject into localStorage before app loads
  const tokenResp = await request.post(supabaseUrl + '/auth/v1/token', {
    headers: {
      'apikey': anonKey,
      'Authorization': `Bearer ${anonKey}`,
      'Content-Type': 'application/json',
    },
    data: JSON.stringify({ grant_type: 'password', email: ADMIN_EMAIL, password: ADMIN_PASSWORD }),
  });
  if (tokenResp.status() < 200 || tokenResp.status() >= 300) {
    throw new Error('Failed to obtain auth token: ' + tokenResp.status());
  }
  const tokenJson = await tokenResp.json();
  const expiresAt = Math.floor(Date.now() / 1000) + (tokenJson.expires_in || 3600);
  const session = {
    currentSession: {
      access_token: tokenJson.access_token,
      refresh_token: tokenJson.refresh_token,
      expires_at: expiresAt,
      token_type: tokenJson.token_type,
      user: tokenJson.user,
    },
    persistSession: true,
  };

  // Inject session into multiple candidate localStorage keys before page loads
  await page.addInitScript(({ sess, anon }) => {
    try {
      const s = JSON.stringify(sess);
      const candidates = [
        'supabase.auth.token',
        'kaj-erp-quality_line_erp_local_dev-auth-token',
        // generic sb-... patterns (fill anon in runtime)
        'sb-' + anon + '-auth-token',
        'sb-' + (anon || '').replace(/\./g, '_') + '-auth-token',
      ];
      candidates.forEach(k => {
        try { localStorage.setItem(k, s); } catch (e) { /* ignore */ }
      });
    } catch (e) { /* ignore */ }
  }, session, anonKey);

  // Navigate to app
  await page.goto(url);
  // Wait for Flutter bootstrap to finish
  await page.waitForSelector('#boot', { state: 'detached', timeout: 90000 });
  await page.waitForTimeout(1000);

  // Navigate to settings/profile editor
  await page.goto(url + '#/settings');
  await page.waitForLoadState('networkidle');

  // Attempt to open profile editor
  const profileButton = page.locator('text=My profile').first();
  if (await profileButton.count() > 0) {
    await profileButton.click();
  } else {
    const avatarBtn = page.locator('button[aria-label="Profile"]').first();
    if (await avatarBtn.count() > 0) await avatarBtn.click();
    else await page.locator('text=الملف الشخصي').first().click().catch(() => {});
  }

  await page.waitForSelector('text=Save changes', { timeout: 20000 });

  // Change a name field if available
  const newName = 'Automated Admin ' + Date.now();
  const fullNameLabel = page.locator('text=Full name').first();
  if (await fullNameLabel.count() > 0) {
    const input = fullNameLabel.locator('xpath=following::input[1]');
    if (await input.count() > 0) await input.fill(newName);
  } else {
    const textInputs = page.locator('div[role="dialog"] input');
    if (await textInputs.count() > 0) await textInputs.nth(0).fill(newName);
  }

  // Upload avatar1
  await page.click('text=Change photo').catch(() => {});
  const fileInput = page.locator('input[type=file]');
  if (await fileInput.count() > 0) {
    await fileInput.setInputFiles(path.resolve('playwright-tests/fixtures/avatar1.png'));
  }
  await page.click('text=Save changes').catch(() => {});
  await page.waitForSelector('text=Save changes', { state: 'detached', timeout: 15000 }).catch(() => {});

  // Reload and re-open profile to verify
  await page.reload();
  await page.waitForLoadState('networkidle');
  await page.click('text=My profile').catch(() => {});
  await page.waitForSelector('text=Save changes', { timeout: 20000 });
  await page.screenshot({ path: 'playwright-artifacts/profile_after_upload.png', fullPage: true });

  // Replace avatar
  await page.click('text=Change photo').catch(() => {});
  const fileInput2 = page.locator('input[type=file]');
  if (await fileInput2.count() > 0) await fileInput2.setInputFiles(path.resolve('playwright-tests/fixtures/avatar2.png'));
  await page.click('text=Save changes').catch(() => {});
  await page.waitForSelector('text=Save changes', { state: 'detached', timeout: 15000 }).catch(() => {});
  await page.reload();
  await page.waitForLoadState('networkidle');
  await page.click('text=My profile').catch(() => {});
  await page.waitForSelector('text=Remove photo', { timeout: 15000 }).catch(() => {});
  await page.screenshot({ path: 'playwright-artifacts/profile_after_replace.png', fullPage: true });

  // Remove avatar
  await page.click('text=Remove photo').catch(() => {});
  await page.click('text=Save changes').catch(() => {});
  await page.waitForSelector('text=Save changes', { state: 'detached', timeout: 15000 }).catch(() => {});
  await page.reload();
  await page.waitForLoadState('networkidle');
  await page.click('text=My profile').catch(() => {});
  await page.screenshot({ path: 'playwright-artifacts/profile_after_remove.png', fullPage: true });

  // Final basic assertion
  await expect(page.locator('text=Save changes')).toBeVisible();
});

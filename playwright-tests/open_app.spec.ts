import { test } from '@playwright/test';
import fs from 'fs';
import path from 'path';

test('open quality line erp and capture screenshot', async ({ page, baseURL }) => {
  await page.goto(baseURL || '/');
  // wait for a likely login element or the app shell
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1500);

  const outDir = path.resolve(process.cwd(), 'playwright-artifacts');
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir);
  const screenshotPath = path.join(outDir, 'home.png');
  await page.screenshot({ path: screenshotPath, fullPage: true });
});

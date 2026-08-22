import { test } from '@playwright/test';

test('dump inputs', async ({ page, baseURL }) => {
  const url = baseURL || 'http://127.0.0.1:8080';
  await page.goto(url);
  await page.waitForLoadState('networkidle');
  // wait an extra bit for Flutter widgets to render
  await page.waitForTimeout(5000);
  const body = await page.evaluate(() => document.body.innerHTML);
  console.log('BODY_HTML_START');
  console.log(body.substring(0, 20000));
  console.log('BODY_HTML_END');
  const inputs = await page.$$eval('input', els => els.map(e => ({outerHTML: e.outerHTML, type: e.type, placeholder: e.getAttribute('placeholder'), ariaLabel: e.getAttribute('aria-label'), name: e.getAttribute('name') }))); 
  console.log(JSON.stringify(inputs, null, 2));
});

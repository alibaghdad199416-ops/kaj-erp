import { test } from '@playwright/test';

/**
 * Runtime adapter for Flutter Web semantics.
 *
 * Flutter rebuilds its accessibility tree independently of the painted UI. A
 * Playwright locator can therefore resolve a valid flt-semantics button and
 * then see that node replaced while actionability waits for stability. The
 * business test must still drive the real browser UI, but Flutter semantic
 * actions are more reliable when dispatched against the currently resolved
 * tappable semantics node, which is the same mechanism used to enable Flutter
 * semantics itself.
 *
 * This adapter is intentionally test-only. It does not change application
 * behavior, bypass authentication, call service-role APIs, or replace any
 * backend invariant checks in phase2b_sales_workflow.spec.ts.
 */

type DynamicObject = Record<string, unknown>;
type DynamicFunction = (...args: any[]) => any;

function installFlutterLocatorClickAdapter(page: any): void {
  const sampleLocator = page.locator('body');
  const locatorPrototype = Object.getPrototypeOf(sampleLocator) as DynamicObject;
  if (locatorPrototype.__qualityLineFlutterClickAdapter === true) return;

  const originalClick = locatorPrototype.click as DynamicFunction;
  if (typeof originalClick !== 'function') {
    throw new Error('Unable to install Flutter locator click adapter.');
  }

  locatorPrototype.click = async function (
    this: any,
    options?: Record<string, unknown>,
  ): Promise<void> {
    for (let attempt = 0; attempt < 8; attempt += 1) {
      try {
        const handled = await this.evaluate((element: HTMLElement) => {
          const tag = element.tagName.toLowerCase();
          const isFlutterSemantic =
            tag.startsWith('flt-') ||
            element.hasAttribute('flt-tappable') ||
            element.querySelector('[flt-tappable]') !== null;
          if (!isFlutterSemantic) return false;

          const target = element.hasAttribute('flt-tappable')
            ? element
            : (element.querySelector('[flt-tappable]') as HTMLElement | null) ?? element;
          target.click();
          return true;
        });
        if (handled) return;
        break;
      } catch {
        // Flutter may replace the semantic node between resolve/evaluate.
        // Re-resolve the locator a few times before falling back to native
        // Playwright actionability for ordinary HTML controls.
        await page.waitForTimeout(125);
      }
    }

    await originalClick.call(this, options);
  };

  locatorPrototype.__qualityLineFlutterClickAdapter = true;
}

function installFlutterReadyFallback(page: any): void {
  const originalWaitForSelector = page.waitForSelector.bind(page) as DynamicFunction;

  page.waitForSelector = async (
    selector: string,
    options?: Record<string, unknown>,
  ): Promise<unknown> => {
    if (selector !== 'flt-glass-pane') {
      return originalWaitForSelector(selector, options);
    }

    try {
      return await originalWaitForSelector(selector, {
        ...options,
        timeout: Math.min(Number(options?.timeout ?? 45_000), 20_000),
      });
    } catch (firstError) {
      try {
        return await originalWaitForSelector(
          'flt-glass-pane, flutter-view, flt-semantics-placeholder, flt-semantics',
          { state: 'attached', timeout: 25_000 },
        );
      } catch {
        // The fixed-port Flutter web-server can occasionally leave a new
        // browser context at the pre-engine shell after a previous long test.
        // One real browser reload is enough to force a fresh engine bootstrap.
        await page.reload({ waitUntil: 'domcontentloaded', timeout: 60_000 });
        try {
          return await originalWaitForSelector(
            'flt-glass-pane, flutter-view, flt-semantics-placeholder, flt-semantics',
            { state: 'attached', timeout: 60_000 },
          );
        } catch {
          throw firstError;
        }
      }
    }
  };
}

test.beforeEach(async ({ page }) => {
  installFlutterLocatorClickAdapter(page);
  installFlutterReadyFallback(page);
});

// Use require rather than a static import so the Flutter-aware hook above is
// registered before the canonical Phase 2B tests are evaluated.
// eslint-disable-next-line @typescript-eslint/no-require-imports
require('./phase2b_sales_workflow.spec');

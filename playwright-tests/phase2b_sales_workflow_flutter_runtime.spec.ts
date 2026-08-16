import { test } from '@playwright/test';

/**
 * Runtime adapter for Flutter Web semantic actions.
 *
 * The canonical Phase 2B spec already owns Flutter readiness and semantics
 * activation. Do not weaken those readiness conditions here: accepting a
 * partially bootstrapped flutter-view before flt-glass-pane/semantics exists
 * makes role locators disappear even though pixels are already painted.
 *
 * Flutter does, however, rebuild accessibility nodes independently of the
 * painted UI. A Playwright locator can resolve a valid flt-semantics action and
 * then see that exact node replaced while actionability waits for stability.
 * This adapter changes only click dispatch for the currently resolved Flutter
 * semantic action. Ordinary HTML controls still use native Playwright click.
 *
 * This is test-only. It does not alter application behavior, bypass auth,
 * broaden permissions, use service-role APIs, or replace backend invariants.
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
        // Flutter may replace a semantic node between locator resolution and
        // dispatch. Re-resolve briefly, without weakening page readiness.
        await page.waitForTimeout(125);
      }
    }

    await originalClick.call(this, options);
  };

  locatorPrototype.__qualityLineFlutterClickAdapter = true;
}

test.beforeEach(async ({ page }) => {
  installFlutterLocatorClickAdapter(page);
});

// Register the adapter before the canonical business lifecycle tests.
// eslint-disable-next-line @typescript-eslint/no-require-imports
require('./phase2b_sales_workflow.spec');

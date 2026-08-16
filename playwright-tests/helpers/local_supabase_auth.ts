import * as fs from 'node:fs';
import * as path from 'node:path';
import type { APIRequestContext, Page } from '@playwright/test';

export type SessionPayload = {
  access_token: string;
  refresh_token: string;
  expires_in?: number;
  expires_at?: number;
  token_type?: string;
  user?: unknown;
  [key: string]: unknown;
};

export type LocalSupabaseRuntime = {
  supabaseUrl: string;
  publishableKey: string;
  localProjectId: string;
  authPersistSessionKey: string;
};

function requiredString(value: unknown, name: string): string {
  const resolved = typeof value === 'string' ? value.trim() : '';
  if (!resolved) {
    throw new Error(`Missing ${name} in dart_defines.local.generated.json`);
  }
  return resolved;
}

function storageNamespace(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]+/g, '_');
}

export function loadLocalSupabaseRuntime(): LocalSupabaseRuntime {
  const definesPath = path.resolve('dart_defines.local.generated.json');
  if (!fs.existsSync(definesPath)) {
    throw new Error(
      `Missing ${definesPath}. Generate the local runtime defines before Playwright.`,
    );
  }

  const defines = JSON.parse(fs.readFileSync(definesPath, 'utf8')) as Record<
    string,
    unknown
  >;
  const supabaseUrl = requiredString(defines.SUPABASE_URL, 'SUPABASE_URL').replace(
    /\/+$/,
    '',
  );
  const publishableKey = requiredString(
    defines.SUPABASE_PUBLISHABLE_KEY ?? defines.SUPABASE_ANON_KEY,
    'SUPABASE_PUBLISHABLE_KEY',
  );
  const localProjectId =
    typeof defines.SUPABASE_LOCAL_PROJECT_ID === 'string'
      ? defines.SUPABASE_LOCAL_PROJECT_ID.trim()
      : '';

  const uri = new URL(supabaseUrl);
  const host = uri.hostname.toLowerCase();
  const isLoopback =
    host === '127.0.0.1' ||
    host === 'localhost' ||
    host === '::1' ||
    host.endsWith('.localhost');

  if (!isLoopback) {
    throw new Error(
      `Phase 2A is local-only. Refusing to authenticate against hosted Supabase: ${supabaseUrl}`,
    );
  }

  const projectRef = localProjectId || 'quality_line_erp_local_dev';
  const authPersistSessionKey = `kaj-erp-${storageNamespace(projectRef)}-auth-token`;

  return {
    supabaseUrl,
    publishableKey,
    localProjectId: projectRef,
    authPersistSessionKey,
  };
}

export async function signInLocalUserAndPrimeBrowser(options: {
  request: APIRequestContext;
  page: Page;
  email: string;
  password: string;
}): Promise<{
  runtime: LocalSupabaseRuntime;
  session: SessionPayload;
}> {
  const runtime = loadLocalSupabaseRuntime();
  const email = options.email.trim().toLowerCase();
  if (!email || !options.password) {
    throw new Error('Local E2E email/password must be supplied.');
  }

  // GoTrue expects the password grant in the query string. Putting
  // grant_type inside the JSON body returns unsupported_grant_type.
  const tokenResponse = await options.request.post(
    `${runtime.supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      headers: {
        apikey: runtime.publishableKey,
        Authorization: `Bearer ${runtime.publishableKey}`,
        'Content-Type': 'application/json',
      },
      data: {
        email,
        password: options.password,
      },
    },
  );

  if (!tokenResponse.ok()) {
    throw new Error(
      `Local Supabase password sign-in failed: HTTP ${tokenResponse.status()} ${await tokenResponse.text()}`,
    );
  }

  const session = (await tokenResponse.json()) as SessionPayload;
  if (!session.access_token || !session.refresh_token) {
    throw new Error('Local Supabase returned an incomplete auth session.');
  }

  // Prove that the token is accepted by Auth before injecting it into Flutter.
  const userResponse = await options.request.get(
    `${runtime.supabaseUrl}/auth/v1/user`,
    {
      headers: {
        apikey: runtime.publishableKey,
        Authorization: `Bearer ${session.access_token}`,
      },
    },
  );
  if (!userResponse.ok()) {
    throw new Error(
      `Local Supabase session read-back failed: HTTP ${userResponse.status()} ${await userResponse.text()}`,
    );
  }

  const expiresAt =
    session.expires_at ??
    Math.floor(Date.now() / 1000) +
      (typeof session.expires_in === 'number' ? session.expires_in : 3600);
  const persistedSession = JSON.stringify({
    ...session,
    expires_at: expiresAt,
  });

  await options.page.addInitScript(
    ({ storageKey, sessionJson }) => {
      // SharedPreferences on Flutter Web stores string values under a
      // flutter.-prefixed key as JSON. Keep the direct key too as a safe
      // compatibility fallback for storage implementations without that prefix.
      localStorage.setItem(`flutter.${storageKey}`, JSON.stringify(sessionJson));
      localStorage.setItem(storageKey, sessionJson);
    },
    {
      storageKey: runtime.authPersistSessionKey,
      sessionJson: persistedSession,
    },
  );

  return { runtime, session };
}

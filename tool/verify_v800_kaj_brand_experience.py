from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = {
    'brand motif': ROOT / 'lib/design_system/kaj_brand_motif.dart',
    'design tokens': ROOT / 'lib/design_system/kaj_design_tokens.dart',
    'job title migration': ROOT / 'supabase/migrations/20260806213000_v800_user_job_title.sql',
}
for label, path in checks.items():
    if not path.exists():
        raise SystemExit(f'FAIL: missing {label}: {path}')

model = (ROOT / 'lib/features/settings/access/models/user_model.dart').read_text(encoding='utf-8')
topbar = (ROOT / 'lib/core/widgets/app_workspace_top_bar.dart').read_text(encoding='utf-8')
dashboard = (ROOT / 'lib/features/dashboard/pages/dashboard_page.dart').read_text(encoding='utf-8')
assert 'final String jobTitle;' in model
assert '_UserIdentity' in topbar and 'Main branch' not in topbar
assert 'KajBrandMotif' in dashboard
print('PASS V8.0.0 KAJ brand experience: identity motif, user job title, and executive dashboard shell.')

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
required = {
    'signature components': ROOT / 'lib/design_system/kaj_signature_components.dart',
    'launch shell': ROOT / 'lib/core/widgets/app_launch_shell.dart',
    'dashboard': ROOT / 'lib/features/dashboard/pages/dashboard_page.dart',
    'notifications': ROOT / 'lib/features/notifications/pages/notification_center_page.dart',
    'global search': ROOT / 'lib/features/global_search/pages/global_search_page.dart',
}
missing = [name for name, path in required.items() if not path.exists()]
if missing:
    raise SystemExit('FAILED V21.1 Phase 2: missing ' + ', '.join(missing))

pubspec = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
release = (ROOT / 'lib/core/release/app_release_info.dart').read_text(encoding='utf-8')
package = (ROOT / 'package.json').read_text(encoding='utf-8')
components = required['signature components'].read_text(encoding='utf-8')
dashboard = required['dashboard'].read_text(encoding='utf-8')
notifications = required['notifications'].read_text(encoding='utf-8')
search = required['global search'].read_text(encoding='utf-8')
splash = (ROOT / 'lib/features/splash/pages/splash_page.dart').read_text(encoding='utf-8')

assert 'version: 21.1.0+211000' in pubspec
assert "version = '21.1.0'" in release
assert 'buildNumber = 211000' in release
assert 'KajSignaturePageHero' in components
assert 'KajSignaturePageHero' in dashboard
assert 'KajSignaturePageHero' in notifications
assert 'KajSignaturePageHero' in search
assert "String _selectedType = '__all__';" in search
assert 'Preparing your secure workspace' in splash
assert '"verify:v2110"' in package

print('PASS V21.1 Phase 2 entry, shell, dashboard, notifications and search verification')

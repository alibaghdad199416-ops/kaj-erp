from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = {
    'entry components': ROOT / 'lib/design_system/kaj_entry_components.dart',
    'shared shell controls': ROOT / 'lib/design_system/kaj_shell_components.dart',
    'splash': ROOT / 'lib/features/splash/pages/splash_page.dart',
    'login': ROOT / 'lib/features/auth/pages/login_page.dart',
    'dashboard': ROOT / 'lib/features/dashboard/pages/dashboard_page.dart',
    'search': ROOT / 'lib/features/global_search/pages/global_search_page.dart',
    'notifications': ROOT / 'lib/features/notifications/pages/notification_center_page.dart',
    'profile': ROOT / 'lib/features/settings/access/pages/current_user_profile_page.dart',
}
for name, path in checks.items():
    if not path.exists():
        raise SystemExit(f'FAIL missing {name}: {path}')

required = {
    checks['entry components']: ['KajEntryPanel', 'KajEntryHeading', 'KajActivitySkeleton', 'KajProfileSummary'],
    checks['splash']: ['KajEntryPanel', 'KajEntryHeading'],
    checks['login']: ['KajField', 'KajPrimaryAction'],
    checks['search']: ['KajActivitySkeleton'],
    checks['notifications']: ['KajActivitySkeleton'],
    checks['profile']: ['KajProfileSummary', 'KajShellSurface', 'KajPrimaryAction', 'KajSecondaryAction'],
}
for path, tokens in required.items():
    text = path.read_text(encoding='utf-8')
    for token in tokens:
        if token not in text:
            raise SystemExit(f'FAIL {token} missing from {path.relative_to(ROOT)}')

release = (ROOT / 'lib/core/release/app_release_info.dart').read_text(encoding='utf-8')
for token in ["22.2.0", '222000', 'full-redesign-stage03']:
    if token not in release:
        raise SystemExit(f'FAIL release token missing: {token}')
print('PASS V22.2 full redesign stage 03 entry and overview verification')
print('PASS splash, login, dashboard, search, notifications and profile contracts')

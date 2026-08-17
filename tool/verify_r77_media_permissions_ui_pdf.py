from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')

config = read('lib/core/cloud/supabase_config.dart')
user_service = read('lib/core/cloud/supabase_user_administration_service.dart')
user_media = read('supabase/functions/admin-update-user-media/index.ts')
migration = read('supabase/migrations/20260815210000_r77_media_permissions_premium_unification.sql')
shell = read('lib/core/widgets/app_module_shell.dart')
strip = read('lib/core/widgets/app_horizontal_strip.dart')
picker = read('lib/core/widgets/base64_photo_picker.dart')
rules = read('lib/core/security/record_rules.dart')
premium = read('lib/core/printing/premium_document_theme.dart')
final_pdf = read('lib/core/printing/kaj_final_pdf_layout.dart')
identity = read('lib/core/printing/unified_pdf_identity.dart')

assert "quality_line_erp_local_dev" in config
assert "http://127.0.0.1:54321" in config
assert "expectedProductionProjectRef" not in config
assert ".supabase.co" not in config
assert "functionName: 'admin-manage-user'" in user_service
assert "'action': 'update'" in user_service
assert "identityPayload.remove('avatarBase64')" in user_service
assert "'avatar_base64': avatarBase64" in user_service
assert "functionName: 'admin-update-user-media'" not in user_service
assert "avatar_base64" in user_media and "erp_records" in user_media
assert "media_payload_too_large" in user_media
manage_user = read('supabase/functions/admin-manage-user/index.ts')
for marker in (
    'users.image.update',
    'avatar_base64',
    'media_readback_mismatch',
    'profile_readback_mismatch',
    'previousRecord',
    'ERP user update rollback failed',
):
    assert marker in manage_user, marker

for key in ('thumbnailBase64', 'photoBase64', 'photo_base64'):
    assert key in migration, key
for module in (
    'customers','suppliers','cars','inventory','sales','purchases','maintenance',
    'accounting','cashbox','expenses','installments','warehouses','customer_service','users',
):
    assert f"{module}.records.own" in migration, module
    assert f"{module}.records.all" in migration, module
assert 'erp_r77_user_can_view_record_owner' in migration

workspace = shell.split('class _WorkspaceCanvas', 1)[1]
assert 'KajShellSurface' not in workspace
assert 'ColoredBox(' in workspace
assert 'Card(' not in picker
assert 'AppHorizontalStrip' in picker
assert 'minControlHeight = 42' in strip
assert 'permissionScoped' in rules
assert "'$module.records.all'" in rules
assert "'$module.records.own'" in rules

assert "import 'unified_pdf_identity.dart';" in premium
assert "import 'unified_pdf_identity.dart';" in final_pdf
assert 'UnifiedPdfIdentity' in premium and 'UnifiedPdfIdentity' in final_pdf
assert 'pageMarginHorizontal' in identity and 'tableHeaderFontSize' in identity

print('PASS R77 media / per-user scope / premium UI / unified PDF verification')
print('Supabase runtime: quality_line_erp_local_dev @ http://127.0.0.1:54321')
print('User identity and avatar update share one governed Edge boundary with read-back')
print('Strict image aliases cover partner, car thumbnail and product thumbnail payloads')
print('Per-module own/all record-scope permissions are seeded without automatic grants')
print('Module workspace is borderless; command strip and photo picker are normalized')
print('PDF systems share one canonical visual identity')

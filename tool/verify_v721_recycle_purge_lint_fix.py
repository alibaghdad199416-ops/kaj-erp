"""V7.2.1 recycle purge linked-lint repair gate."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260804033000_v721_recycle_purge_queue_lint_fix.sql"
text = MIGRATION.read_text(encoding="utf-8")

checks = {
    "forward migration exists after V7.2": MIGRATION.is_file(),
    "purge function is redefined": "create or replace function public.erp_recycle_bin_purge_by_archive" in text,
    "temporary pg_temp queue is removed": "pg_temp.erp_v72_purge_queue" not in text and "create temporary table" not in text,
    "in-memory UUID retry queue is used": all(marker in text for marker in ("v_queue uuid[]", "v_next_queue uuid[]", "foreach v_queue_archive_id in array v_queue")),
    "exact archive and deletion batch are preserved": all(marker in text for marker in ("u.id=v_archive.id", "u.deletion_batch_id=v_batch", "p_archive_id")),
    "foreign-key retry and blocked-state detection remain": all(marker in text for marker in ("foreign_key_violation", "array_append", "permanent_delete_blocked_by_active_relationships")),
    "source rows and archive rows are counted": all(marker in text for marker in ("sourceRowsProcessed", "archiveRowsRemoved", "get diagnostics v_archives=row_count")),
    "permission boundary remains": all(marker in text for marker in ("settings.recycle_bin.purge", "revoke all on function", "grant execute on function")),
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL V7.2.1 recycle purge lint repair:\n  - " + "\n  - ".join(failed))

print("PASS V7.2.1 recycle purge linked-lint repair")
for name in checks:
    print(f"  - {name}")

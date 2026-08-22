R87.1 Legacy Journal Metadata Guard Hotfix

Files:
- supabase/migrations/20260819023000_r87_1_legacy_journal_metadata_guard.sql
- tool/verify_r87_1_legacy_journal_metadata_guard.py

After merging:
1) python -B tool/verify_r87_1_legacy_journal_metadata_guard.py
2) npm run db:local:update
3) python -B tool/verify_r86_complete_linked_financial_deletion.py

The migration is forward-only. Do not run db reset, db push, or supabase link.

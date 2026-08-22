R57 — Inventory Movement / Product Maintenance Card / Arabic PDF / Car Card Fix
Migration count after this package: 271

What this package fixes
=======================

1) Inventory movement semantic source/destination
--------------------------------------------------
The canonical R28 movement read no longer falls back to:
  current warehouse -> current warehouse

It now resolves the business counterparty:

Purchase:
  Supplier -> Warehouse

Purchase reversal/return:
  Warehouse -> Supplier

Sale:
  Warehouse -> Customer

Sale reversal/return/delete:
  Customer -> Warehouse

Maintenance material issue:
  Warehouse -> Customer

Maintenance issue reversal / deleted maintenance order:
  Customer -> Warehouse

Warehouse transfer, including transfers into a scrap/damage-consumption warehouse:
  Source warehouse -> Destination warehouse

The movement rows remain immutable audit rows. This is a read-model correction.

2) Product/material maintenance card
------------------------------------
Adds:
  public.erp_r57_product_maintenance_card(uuid,text)

Product details now load a vehicle-linked maintenance history:
- order number/date/status
- vehicle number/name/chassis/plate
- customer
- requested / issued / reversed / remaining quantity
- warehouse contributions
- stock issue number/status
- invoice number/status
- payment status
- related service names/quantities
- notes/cancellation reason

Deleted orders that actually had material issue events remain visible as history,
with reversed quantities/status.

The printable product maintenance card is privacy-safe and intentionally excludes:
- FIFO / actual / requested internal cost
- labor cost
- parts cost
- total operational maintenance cost
- profit/margin
- vehicle purchase cost
- vehicle maintenance cost
- vehicle total cost

3) Arabic PDF disconnected letters
-----------------------------------
Main PDF surfaces are patched in-place so normal text widgets pass through
PdfTextSupport.text(), which explicitly selects RTL/LTR per string while using
the bundled Arabic fonts.

Patched surfaces:
- Maintenance document PDF
- Enterprise sales/purchase/maintenance PDF
- Warehouse transfer PDF
- Vehicle service card PDF
- Generic PDF export
- Adaptive PDF tables
- New product maintenance card PDF

Local branding/layout changes are preserved because the patch script edits only
the text widget calls and exact requested UI anchors.

4) Yellow/black stripe below vehicle card
-----------------------------------------
This is the Flutter RenderFlex overflow warning stripe caused by the fixed grid
height being too small for the vehicle card at narrow multi-column widths.
The responsive car grid heights are increased, with the narrow 3-column layout
receiving the largest height.

Files in the package
====================
supabase/migrations/
  20260813013000_r57_inventory_movement_product_maintenance_card_semantics.sql

lib/core/printing/
  product_maintenance_card_pdf_service.dart

tool/
  apply_r57_inventory_product_pdf_ui_fix.py
  verify_r57_hosted_accounting_workflow_acceptance.py

Apply
=====
Extract this ZIP into:
C:\Projects\Quality-Line-ERP-R49-FOCUSED-FINAL-COMPLETION

Then run the commands provided in ChatGPT.

Safety
======
- Forward migration only.
- No historical migration is edited.
- No db reset.
- No remote db push.
- No commit/push/deployment.
- The patch script is fail-closed: if an expected source anchor changed, it
  exits before writing any source files.

Browser acceptance after successful verification
=================================================
A) Movement log
- purchase: supplier -> warehouse
- sale: warehouse -> customer
- maintenance issue: warehouse -> customer
- maintenance delete/reversal: customer -> warehouse
- transfer/scrap: source warehouse -> destination warehouse

B) Product card
- open the same material used in maintenance
- maintenance history appears per vehicle
- warehouse contributions and reversal status are correct
- print PDF
- no internal maintenance cost or vehicle cost appears

C) Arabic PDF
- Arabic words render as joined words, not isolated letters
- test Maintenance + Sales/Purchase + Product card PDF

D) Vehicle card
- no yellow/black overflow stripe at normal browser zoom

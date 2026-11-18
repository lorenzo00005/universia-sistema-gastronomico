# Phase 1 — Infrastructure and Base Odoo 17 Configuration (Universia)

Delivered 2026-11-14 · covers weeks 1–4 (tracks A and C) and the audit data design (track B). ⚠ = verify on your installation.
Ready-to-use infrastructure files are in [`/infra`](../infra).

## 1. Assumptions (Phase 0 questions unanswered)
Odoo Community 17.0 · local Windows 11 server with Docker Desktop · 12 tables (Hall T1–T8, Terrace T9–T12) · 4 waiters and 1 register · Epson ePOS network printers (kitchen and bar) · taxes configured together with ARCA (weeks 5–6) · staging kept for tests and NFC.

## 2. Infrastructure
- Server folder: `C:\universia-prod\` with `docker-compose.yml`, `.env`, `config\odoo.conf`, `addons\`, `scripts\backup_prod.ps1`.
- Master password hash (PowerShell, from `C:\universia-prod`):
  ```powershell
  docker compose run --rm --no-deps --entrypoint python3 odoo -c "from passlib.hash import pbkdf2_sha512; import getpass; print(pbkdf2_sha512.hash(getpass.getpass('Master password: ')))"
  ```
- Start: `docker compose up -d` then `docker compose ps`.
- LAN-only firewall rule (admin PowerShell):
  ```powershell
  New-NetFirewallRule -DisplayName "Universia Odoo 8069 (LAN)" -Direction Inbound -Protocol TCP -LocalPort 8069 -RemoteAddress LocalSubnet -Action Allow -Profile Private
  ```
- Fixed IP for the server, no sleep, **never expose port 8069 to the internet**. ⚠ Docker Desktop needs a logged-in user session (alternative: Linux mini-PC).
- Daily backup:
  ```powershell
  schtasks /Create /TN "Universia-Backup" /SC DAILY /ST 04:30 /TR "powershell -NoProfile -ExecutionPolicy Bypass -File C:\universia-prod\scripts\backup_prod.ps1" /RL HIGHEST
  ```
  ⚠ `Compress-Archive` fails on files over 2 GB (switch to 7-Zip if that happens). **Test a restore on staging before week 7.**

## 3. Database and apps
1. With `list_db = True`: create `universia_prod`, demo data off, Spanish (AR), country Argentina. Then set `list_db = False` and run `docker compose restart odoo`.
2. Company: tax ID (CUIT), address, ARS currency, timezone `America/Argentina/Buenos_Aires`.
3. Install apps in order: Inventory, Purchase, Manufacturing (bills of materials only), Employees, Point of Sale, CRM, Email Marketing. ⚠ Verify the `l10n_ar` localization loaded.

## 4. POS Restaurant
Create "Universia – Salón" and enable: bar/restaurant, bill splitting, pre-bill printing, tips (untaxed product), multiple employees per session, price/discount control restricted to managers, order printers. Initial payment methods: Cash, Card, Transfer (Mercado Pago QR and eWallet later). Floors "Salón" and "Terraza", tables T1–T12 with visible numbers. ⚠ Odoo 17 has no course management; orders are sent in batches (custom control in Phase 2).

## 5. Catalog
- POS categories — Kitchen: Platos, Sándwiches · Bar: Café, Bebidas, Licuados, Pastelería.
- Codes: `CAF-001`, `COC-001`, `BEB-001`, `PAS-001`, `INS-001`. Name format: `Name – Size`.
- Sellable item: "Can be sold" + "Available in POS". Ingredient: "Can be purchased", not in POS, with stock and purchase units (create mL).
- Recipe = **Kit**-type bill of materials. Valuation: average cost. POS stock moves are generated when the session closes.

## 6. Roles and permissions
Employees get their own **PIN**. Waiter and Cashier: POS user (cashier can open/close the register). Manager: advanced POS employee (authorizes prices, discounts, voids). Owner: POS and Inventory administrator.
Voiding an item already sent to the kitchen and recording stock adjustments: Manager/Owner only, with **custom control in Phase 2** (today there is no approval or log).

## 7. Station printing
Two Epson printers (Kitchen: Platos, Sándwiches · Bar: Café, Bebidas, Licuados, Pastelería) with ePOS-Print enabled, fixed IPs, and Odoo served over HTTP inside the LAN. ⚠ Non-Epson brands need a custom ESC/POS service (Phase 2).

## 8. Initial SOPs
- **SOP-01 Opening (manager):** power on server, test printers, count the cash float, open the session with own PIN, review minimum stock.
- **SOP-02 Ordering and service (waiter):** own PIN, open table and add notes, send to kitchen, voids only through the manager, pre-bill from the system.
- **SOP-03 Register closing (cashier):** no open tables, count cash by denomination, record any difference, close session, manager reviews and signs.
- Pending: SOP-04 goods receiving, SOP-05 eWallet top-up / lost card, SOP-06 weekly inventory.

## 9. Acceptance tests
1 Ticket prints at the right station · 2 Mixed order = two tickets · 3 Split bill with mixed payment · 4 Merge tables and transfer an order · 5 Two waiters on the same table · 6 Discount asks for manager PIN · 7 Closing with a visible difference · 8 Wi-Fi drop without losing the order · 9 Sale with recipe deducts ingredients · 10 Restore backup on staging.

## 10. Anti-theft audit design (`universia_audit`, Phase 2)
**`universia.audit.event`** (immutable): `event_type` (post-ticket void, discount, pre-bill cancelled, table reopened, reprint, stock adjustment, balance movement, cash difference), `pos_config_id`, `session_id`, `order_id`, `employee_id`, `approver_id`, `amount`, `currency_id`, `reason_code`, `reason_text`, `payload_before/after` (JSON), `device_info`, `hash_prev`, `hash` (hash chain).
**`universia.audit.rule`**: `event_type`, `role`, `threshold_amount`, `require_approval`, `notify_channel` (n8n/WhatsApp alert to the owner).
Suggested retention 24 months, aligned with Argentina's Law 25.326 (personal data protection).

## 11. Risks and next steps
Risks: assumed client data, non-Epson printers, Docker Desktop needing a user session, unvalidated PN532 reader, taxes not yet configured.
**Phase 2 (weeks 3–5):** production eWallet, recipes and purchasing, post-kitchen void approval, cash count with difference reason, ARCA in sandbox.

# Universia (gestión empresarial) — Integrated Restaurant/Café Management System

A complete management and control system for a restaurant/café built on **Odoo 17**, with **NFC cards + eWallet** as its key differentiator versus SaaS tools such as Fudo.

**Status (2026-11-16):** Phase 1 delivered (infrastructure and base configuration). Phase 2 awaits confirmation.

## Core flow (NFC)
`NTAG215 card → USB PN532 reader → Python middleware (Windows 11) → Odoo 17 POS → CRM / Loyalty / Reports`

## Scope
Floor and tables · waiter ordering · kitchen/bar tickets by station · stock with recipes and COGS · payments and cash drawer (cash, card, Mercado Pago QR, transfer, ARCA/AFIP e-invoicing) · employees and permissions · NFC/eWallet/CRM · reports and anti-theft auditing · offline operation.

## Phase status
| Phase | Content | Status |
|---|---|---|
| 0 | Discovery and assumptions | Done (default assumptions) |
| 1 | Local server, `universia_prod` database, POS Restaurant, catalog, employees, station printing, backups | **Delivered 2026-11-14** |
| 2 | Production eWallet, recipes and purchasing, post-kitchen void approval (`universia_audit`), cash count, ARCA in sandbox | Pending confirmation |
| 3+ | Reservations, delivery, advanced CRM, reports | Weeks 9–12 |

## Current decisions
- Odoo **Community 17.0** on Docker (`odoo:17.0` + `postgres:15.8`), local Windows 11 server with Docker Desktop, LAN only.
- Clean `universia_prod` database, daily backup with rotation and off-site copy; restore must be tested on staging before week 7.
- NFC middleware: Python 3.12, `pyscard` + `pyserial`, Win32 SendInput typing, `.exe` via PyInstaller, scheduled task at logon (`UniversiaNFC`). Barcode prefix `042` + card UID.
- eWallet: 25 % bonus on every top-up (`loyalty.rule` id=2, 1.25), balance never expires.
- Taxes and ARCA invoicing: weeks 5–6.

## Repository layout
```
README.md
docs/
  phase1-infrastructure-and-configuration.md   # Phase 1 summary (English)
  fase1-roadmap-y-configuracion.md             # Phase 1 full document (Spanish: SOPs, tests, permissions, audit design)
  context/                                     # Reference only; separate projects, not part of Universia
    nfc-green-mug.md                           # Green Mug NFC card project (eWallet pilot)
    nfc-business.md                            # B2B NFC card business and clients
infra/
  docker-compose.yml
  .env.example
  config/odoo.conf
  scripts/backup_prod.ps1
```

## Quick start (Windows 11)
1. Copy `infra/` to `C:\universia-prod\`.
2. Copy `.env.example` to `.env` and set the PostgreSQL password.
3. Generate the `admin_passwd` hash (see `docs/phase1-...md`, section 2) and paste it into `config/odoo.conf`.
4. Run `docker compose up -d`, create the `universia_prod` database, then set `list_db = False`.
5. Schedule `scripts/backup_prod.ps1` with `schtasks`.

> Never commit `.env` or real credentials.

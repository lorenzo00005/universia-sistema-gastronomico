# Universia NFC — eWallet and Odoo POS Integration

**Client:** Green Mug Coffee (Mar del Plata) · **Stage:** 50-card pilot · **Reference date:** 2026-09-30

**Goal:** eWallet and loyalty using NFC cards (NTAG215) natively integrated with the Odoo 17 POS. The card is only an identity token; balance, accounting and loyalty live in Odoo.
**Anchor use case:** a parent tops up ARS 200,000 per month and their daughter spends against that balance daily.
**Flow:** NFC card → USB reader (PN532) → Python middleware on Windows 11 → Odoo 17 POS.

## Current decisions
- **Environment:** Odoo 17 on Docker (`odoo:17.0` + `postgres:15.8`), `greenmug_staging` database without demo data (legacy name; staging keeps it, the scheduled task is recreated as `UniversiaNFC`); `backup.ps1` / `restore.ps1` scripts.
- **Middleware:** Python 3.12, `pyscard` (PC/SC), `pyserial` (PN532 over COM), `python-dotenv`. Typing via Win32 SendInput. No `nfcpy` or `keyboard`. Shipped as a standalone `.exe` (PyInstaller, `BUILD_EXE.bat`).
- **Execution:** scheduled task at logon (`UniversiaNFC`), not a service, because services (session 0) cannot type into the browser.
- **Identification:** the middleware prepends `BARCODE_PREFIX=042` to the UID. The contact barcode must be `042` + UID (e.g. `04204A3B2C1`).
- **5 % cashback:** not natively possible in the same wallet. Replaced by a 25 % bonus on every top-up (`loyalty.rule` id=2, `reward_point_amount = 1.25`): paying 100,000 credits 125,000.
- **eWallet payment discount:** option 1 (implicit), no custom development. **Balance never expires.**

## Budget and timeline
USD 2,550: cards 250 · design/printing 350 · integration and middleware 1,800 · 2 readers 150.
8 weeks: Odoo setup (1–2) · middleware and hardware (3–4) · QA and training (5) · commercial pilot (6–8).

## Pending (requires the physical reader)
1. Top up 20,000 in the POS → balance must become 25,000.
2. Tap the card with the POS open → customer must be selected automatically.
3. Pay with eWallet balance (needs a test product) and verify the balance drops.
4. Rebuild the `.exe` and set `READER` (`pcsc` or `pn532_serial`).
5. Load `042` + UID into each real card's contact.
6. Accounting setup (liability account for eWallet balance).
7. Production migration and loading of the 50 cards.

# Implementation Checklist — Personal Finance Manager

Voice-first personal finance manager for Android (Bangladesh).
Currency: BDT (৳). Monetary values stored as **integer poisha** (1 BDT = 100 poisha).

> Status of this document: **complete**. See `README.md` for the full description,
> and the "Implemented features" / "Tested workflows" / "Known limitations"
> sections there for the authoritative record.

## Phase 1 — Inspect & initialise
- [x] Inspect workspace (was empty)
- [x] Detect toolchain (Flutter not installed → installed locally in `/home/groot/development/flutter`)
- [x] Install JDK 17 + Android cmdline-tools locally (no sudo available)
- [x] Flutter scaffold + dependency resolution (`flutter pub get`, ~151 deps)
- [x] Establish architecture + design system plan (README + this document)

## Phase 2 — Financial foundations
- [x] Drift schema: wallets, categories, transactions, budgets, budget alerts,
      savings goals, goal contributions, recurring rules, reminders, loans,
      loan payments, app settings, audit log (13 tables)
- [x] Migration strategy (`schemaVersion = 1`, forward-only `MigrationStrategy`)
- [x] Repositories (10: wallet, transaction, category, budget, goal, recurring,
      reminder, loan, settings + aggregates)
- [x] Money value object + BDT formatter (integer poisha, Bangladeshi grouping)
- [x] `ReportService`, `BudgetService`, `GoalService`, `LoanService`,
      `RecurringService`, `UndoService`
- [x] Atomic transfer (`TransactionService`, the only ledger write path)
- [x] Unit + integration tests for all balance invariants

## Phase 3 — Interface
- [x] Material 3 theme (light + dark), typography, spacing tokens
- [x] GoRouter + bottom navigation shell (Dashboard · History · Voice · More)
- [x] Onboarding / first-run wallet setup
- [x] Dashboard (real DB aggregates, date range, empty states)
- [x] Wallet list, wallet detail, create/edit wallet
- [x] Income / Expense / Transfer forms (shared services + validation)
- [x] Transaction history, filters, search, detail, edit, delete, undo
- [x] Reusable widgets + loading/empty/error states

## Phase 4 — Voice entry (primary feature)
- [x] `SpeechRecognizer` seam; native provider via `speech_to_text`
- [x] Optional online interpreter via a user-controlled endpoint (no embedded secrets;
      text only, strictly additive)
- [x] Bengali/Banglish text normaliser
- [x] Bengali word-number parser (`দেড় হাজার`, `আড়াইশো`, `দুই হাজার পাঁচশো` …)
- [x] Banglish number parser (`dher hazar`, `arai sho`, `2k`, `1.5 thousand`)
- [x] Wallet alias matcher (incl. নগদ cash/Nagad ambiguity resolution)
- [x] Category keyword matcher
- [x] Relative date parser (আজ / গতকাল / আজ নয়, গতকাল …)
- [x] Rule-based type classifier (income / expense / transfer / unknown) + confidence
- [x] Resolution against real wallets/categories + default-wallet policy
- [x] Confirmation & correction UI; never save below confidence threshold
- [x] Duplicate-submission prevention; cancel never mutates balances
- [x] Undo after save
- [x] Versioned parser test corpus (bn / banglish / en)

## Phase 5 — Secondary features
- [x] Budgets with thresholds + non-repeating local notifications
- [x] Reports: income vs expense, net flow, category breakdown, wallet balances,
      trends, budget performance, drill-down
- [x] Savings goals + contributions
- [x] Recurring rules (explicit schedule, never silently double-posted)
- [x] Bill reminders
- [x] Lending / borrowing with outstanding balances
- [x] Tags, notes, merchant, global search, sorting
- [x] CSV export, versioned JSON backup, validated restore, merge/replace preview
- [x] Optional password-encrypted backup (AES-256-GCM)
- [x] PIN + biometric app lock, auto-lock, secure storage
- [x] Data clearing with confirmation
- [x] Offline / online capability explanation in-app

## Phase 6 — Verify & package
- [x] `flutter pub get`
- [x] `dart format`
- [x] `flutter analyze` (0 issues)
- [x] `flutter test` (117 tests green)
- [x] `flutter build apk --debug`
- [x] `flutter build apk --release` (debug-signed, documented)
- [x] README with setup, commands, limitations
- [x] `.env.example`, `.gitignore`
- [x] Feature / tested-workflow / limitation summary

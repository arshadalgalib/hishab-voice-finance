# Contributing to Hishab

Thanks for wanting to help! This is a **local-first, privacy-respecting** personal
finance app for Android. Two rules matter above all others:

1. **Money is never a floating-point number.** Every amount is stored and passed
   around as an integer number of **poisha** (1 BDT = 100 poisha). If your change
   touches money, keep it integer all the way through.
2. **Nothing is silently saved.** A voice result, a duplicate, or a low-confidence
   parse is always confirmed by the user. Do not add a path that writes to the
   ledger without an explicit confirmation.

Please also read [`SECURITY.md`](SECURITY.md) before touching security, the
backup format or the voice pipeline.

## Getting set up

You need Flutter (`>=3.10.0` Dart), a JDK 17 and the Android SDK to build the APK.
To run the tests you only need Flutter.

```bash
flutter pub get

# Only needed after changing anything under lib/data/local/ (Drift tables):
dart run build_runner build --delete-conflicting-outputs

flutter analyze   # must be clean
flutter test      # must be green
```

If you develop in the same environment this project shipped with, `source` the
toolchain first:

```bash
source /home/groot/development/env.sh
```

## Before you open a pull request

Run all three and make sure they pass:

```bash
dart format lib test                                # keep it formatted
flutter analyze                                     # zero issues
flutter test                                        # zero failures
```

Continuous integration runs exactly these checks (see
`.github/workflows/ci.yml`), so a red CI run means the PR needs work.

## Where things live

```
lib/core        money, security, errors, constants, utils
lib/data        Drift database, repositories, services (notifications, backup, CSV)
lib/domain      business logic: TransactionService, ReportService, … and models
lib/features    one folder per feature (voice/, dashboard/, wallets/, …)
test/           unit/, integration/, voice/, helpers/
```

- **`lib/domain/services/transaction_service.dart` is the only code path that
  writes to the ledger.** Add new writing behaviour there, not in a screen or a
  repository.
- **Dependency direction is `features → domain → data → core`.** Don't import
  `features` from `domain`/`data`.
- Models and Riverpod providers are **hand-written** on purpose (only `drift_dev`
  + `build_runner` are used). Please keep it that way unless there's a strong
  reason.

## Common tasks

### Adding a voice test case

The parser has a **versioned corpus** in `test/voice/voice_parser_test.dart` and
an end-to-end widget suite in `test/voice/voice_flow_widget_test.dart`. If you
teach the parser a new phrasing (or fix a mis-hearing), add a case that would
have failed before. Include Bengali, Banglish and English where relevant.

Never assert a *recognition accuracy percentage* — that depends on the phone's
engine and cannot be measured from these tests. Confidence values are internal
signals only.

### Changing the database schema

Bump `schemaVersion` in `lib/data/local/app_database.dart` and add a **forward-only**
step in `MigrationStrategy.onUpgrade`. In Drift 2.31 the `.references(...)`
builder silently emits nothing, so foreign keys must be written as explicit
`.customConstraint('... REFERENCES ...')`. After editing, regenerate and verify:

```bash
dart run build_runner build --delete-conflicting-outputs
grep -c REFERENCES lib/data/local/app_database.g.dart   # expect 14
```

### Adding a dependency

Keep the surface small, and do **not** upgrade `drift` past `2.31.0` without
reading the rationale in `README.md` ("Dependency notes").

## Never commit secrets

There is no API key, token, password or keystore in this repository, and there
must never be one. Specifically:

- Do **not** put a token in `--dart-define`, source, docs, or a test fixture.
- `.env` is git-ignored; only `.env.example` (non-secret) is committed.
- The online-interpretation token is entered by the user at runtime and lives
  only in platform secure storage.

If you spot a secret anywhere, please follow [`SECURITY.md`](SECURITY.md).

## Commit and PR style

- Keep commits focused and describe *why*, not just *what*.
- Reference the issue you're fixing (`Fixes #123`) when there is one.
- For UI changes, a screenshot or short screen recording helps a lot.
- Be kind and constructive in reviews.

By contributing you agree that your contribution is licensed under the
project's [MIT License](LICENSE).

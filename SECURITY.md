# Security Policy

Hishab is a **local-first** personal finance app. Your financial data lives in a
SQLite database on your device and is never uploaded. This document explains what
we protect, how, and how to report a problem.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

- Use GitHub's **private vulnerability reporting**: *Security → Report a
  vulnerability* on the repository page.
- If that is unavailable, open a minimal public issue asking a maintainer to
  contact you, without disclosing details.

Please include: what you found, how to reproduce it, the impact you think it has,
and the app version / Android version. We aim to acknowledge within a few days.

## What the app protects, and how

- **Data at rest.** The SQLite database is app-private storage. Secrets are never
  written to it.
- **PIN / app lock.** The PIN itself is never stored. A random 16-byte salt and a
  PBKDF2-HMAC-SHA256 verifier (**120,000 iterations**) live in the platform
  keystore via `flutter_secure_storage`; comparison is constant-time.
- **Encrypted backups.** Optionally wrapped in an **AES-256-GCM** envelope keyed
  with **PBKDF2-HMAC-SHA256** (**150,000 iterations**, random 16-byte salt,
  random 12-byte nonce). Authenticated encryption: a wrong password or a tampered
  file fails cleanly.
- **Online interpretation (optional, off by default).** Only the recognised
  **text** is sent to an endpoint the user configures — never audio. The bearer
  token is entered by the user and kept only in secure storage. The online result
  is **strictly additive**: it can only fill fields the on-device parser left
  empty, so a malicious or buggy server cannot silently change an amount or
  wallet the user actually spoke.
- **No telemetry.** No analytics, crash reporting or ads. Network access happens
  only when the user turns on online interpretation.

## The "no secrets" rule

The repository contains **no credentials** of any kind, including in the build
output. In particular:

- A `--dart-define` value is compiled into the APK and is trivially extractable,
  so **tokens must never be passed that way.** Only non-secret defaults (an
  endpoint URL and a language code) are supported at build time.
- `.env` is git-ignored; only `.env.example` (non-secret) is committed.
- Test fixtures use obvious dummy values (e.g. a test backup password), never
  anything real.

If you find a credential committed to this repository, please report it privately
as above so it can be rotated and removed from history.

## Scope

In scope: the app's Dart/Kotlin code, the PIN/backup crypto, the voice pipeline,
and the in-app online-interpretation request format.

Out of scope: the Android OS speech engine itself, third-party packages (report
those upstream), and anything that requires a rooted device or physical access to
an unlocked phone.

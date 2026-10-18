#!/usr/bin/env bash
#
# Build the smallest possible release artifacts.
#
#   ./tool/build_release.sh          # App Bundle + per-ABI APKs
#   ./tool/build_release.sh bundle   # Android App Bundle only (Play Store)
#   ./tool/build_release.sh apk      # per-ABI APKs only
#
# Why these flags:
#   * `appbundle`     – what the Play Store wants. Play then serves each device
#                       only the slice it needs (~24 MB instead of ~50 MB).
#   * `--split-per-abi` – for sideloading. Produces one APK per CPU
#                       architecture so nobody downloads the other ABIs.
#   * `--target-platform` – builds only the two ABIs real phones use. x86_64 is
#                       emulator-only, so a release artifact for it would be
#                       dead weight.
#   * `--obfuscate --split-debug-info` – shortens Dart symbol names in
#                       `libapp.so` (smaller download) and writes the mapping
#                       needed to de-obfuscate crashes to `build/symbols/`.
#                       Keep that folder with the release; never delete it.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SYMBOLS_DIR="build/symbols"
TARGET="${1:-all}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found on PATH — run: source /home/groot/development/env.sh" >&2
  exit 1
fi

flutter pub get

common=(
  --release
  --obfuscate
  --split-debug-info="$SYMBOLS_DIR"
  --target-platform android-arm,android-arm64
)

if [[ "$TARGET" == "all" || "$TARGET" == "bundle" ]]; then
  echo "==> Building Android App Bundle (Play Store split delivery)"
  flutter build appbundle "${common[@]}"
fi

if [[ "$TARGET" == "all" || "$TARGET" == "apk" ]]; then
  echo "==> Building per-ABI release APKs"
  flutter build apk "${common[@]}" --split-per-abi
fi

echo
echo "Artifacts:"
find build/app/outputs -name '*.aab' -o -name '*.apk' 2>/dev/null |
  while read -r artifact; do
    printf '  %6s  %s\n' "$(du -h "$artifact" | cut -f1)" "$artifact"
  done

echo
echo "De-obfuscation symbols: $SYMBOLS_DIR (keep, do not ship in the app)"

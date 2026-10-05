#!/usr/bin/env bash
set -euo pipefail
repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repository_root"
if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  echo "This script requires Linux x64." >&2
  exit 1
fi
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets --locked -- -D warnings
cargo test --manifest-path rust/Cargo.toml --locked
cd flutter
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build linux --release
bundle="$repository_root/flutter/build/linux/x64/release/bundle"
for required in pouch lib/libpouch_core.so lib/libflutter_linux_gtk.so data/flutter_assets; do
  if [[ ! -e "$bundle/$required" ]]; then
    echo "The Linux bundle is missing $required." >&2
    exit 1
  fi
done
cp "$repository_root/LICENSE" "$bundle/LICENSE"
cp "$repository_root/THIRD_PARTY_NOTICES.md" "$bundle/THIRD_PARTY_NOTICES.md"
cp "$repository_root/flutter/assets/fonts/OFL.txt" "$bundle/Amiri-LICENSE.txt"
version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"
mkdir -p "$repository_root/dist"
archive="$repository_root/dist/pouch-$version-linux-x64.tar.gz"
tar -czf "$archive" -C "$bundle" .
sha256sum "$archive"
echo "Linux bundle prepared. Test the extracted archive before publishing: $archive"

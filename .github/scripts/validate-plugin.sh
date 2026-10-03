#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT_DIR/manifest.json"

echo "=== 1. Validating Required Files ==="
REQUIRED_FILES=(
  "manifest.json"
  "README.md"
  "LICENSE"
  "preview.png"
  "Panel.qml"
  "bin/azurevpn"
  "libexec/azurevpn-helper"
  "libexec/azurevpn-sudo"
  "tests/test_helper.py"
  "tests/test_sudoers.py"
)

for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "$ROOT_DIR/$file" ]]; then
    echo "::error::Missing required file: $file"
    exit 1
  fi
  echo "✓ Found $file"
done

if [[ ! -x "$ROOT_DIR/bin/azurevpn" ]]; then
  echo "::error::bin/azurevpn is not executable"
  exit 1
fi
echo "✓ bin/azurevpn is executable"

echo ""
echo "=== 2. Validating Python Syntax ==="
for f in bin/azurevpn libexec/azurevpn-helper libexec/azurevpn-sudo; do
  python3 - "$ROOT_DIR/$f" <<'PY'
import sys
compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")
PY
  echo "✓ $f compiled cleanly"
done

echo ""
echo "=== 2b. Running Unit Tests ==="
(cd "$ROOT_DIR" && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -t . -v)
echo "✓ Unit tests passed"

echo ""
echo "=== 3. Validating manifest.json ==="
jq -e . "$MANIFEST" >/dev/null || {
  echo "::error::manifest.json is not valid JSON"
  exit 1
}

# schemaVersion must be 1
jq -e '.schemaVersion == 1' "$MANIFEST" >/dev/null || {
  echo "::error::schemaVersion must be 1"
  exit 1
}

# Required fields
for field in id name version author license description kinds entryPoints; do
  jq -e --arg f "$field" 'has($f) and (.[$f] | tostring | length > 0)' "$MANIFEST" >/dev/null || {
    echo "::error::manifest missing non-empty field '$field'"
    exit 1
  }
done

ID=$(jq -r '.id' "$MANIFEST")
if [[ ! "$ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ || "$ID" == *".."* || "$ID" == omarchy.* ]]; then
  echo "::error::Invalid plugin id: $ID"
  exit 1
fi
echo "✓ ID is valid: $ID"

VERSION=$(jq -r '.version' "$MANIFEST")
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
  echo "::error::Version '$VERSION' is not valid semantic versioning (expected X.Y.Z)"
  exit 1
fi
echo "✓ Version is semver: $VERSION"

# Entrypoints check
while IFS= read -r ep; do
  [[ -n "$ep" ]] || continue
  if [[ "$ep" == /* || "$ep" == *".."* ]]; then
    echo "::error::Entry point must be a safe relative path: $ep"
    exit 1
  fi
  if [[ ! -f "$ROOT_DIR/$ep" ]]; then
    echo "::error::Entry point file not found: $ep"
    exit 1
  fi
  echo "✓ Entry point exists: $ep"
done < <(jq -r '.entryPoints | to_entries[] | .value' "$MANIFEST")

echo ""
echo "✓ All plugin validations passed successfully!"

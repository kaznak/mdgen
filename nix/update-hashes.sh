#!/usr/bin/env bash
set -euo pipefail

# Update nix/toolchain-hashes.json based on the current lean-toolchain version.
# Requires: nix, curl
# Usage: bash nix/update-hashes.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LEAN_TOOLCHAIN=$(cat "$ROOT_DIR/lean-toolchain")
LEAN_VERSION=${LEAN_TOOLCHAIN#leanprover/lean4:v}

echo "Lean version: $LEAN_VERSION"

compute_sri_hash() {
  local suffix=$1
  local url="https://github.com/leanprover/lean4/releases/download/v${LEAN_VERSION}/lean-${LEAN_VERSION}-${suffix}.tar.zst"
  echo "Fetching $url ..." >&2
  local store_path
  store_path=$(nix-prefetch-url "$url" 2>/dev/null)
  nix hash convert --hash-algo sha256 --to sri "$store_path"
}

LINUX_HASH=$(compute_sri_hash "linux")
LINUX_ARM_HASH=$(compute_sri_hash "linux_aarch64")
DARWIN_HASH=$(compute_sri_hash "darwin")
DARWIN_ARM_HASH=$(compute_sri_hash "darwin_aarch64")

cat > "$ROOT_DIR/nix/toolchain-hashes.json" <<EOF
{
  "linux": "$LINUX_HASH",
  "linux_aarch64": "$LINUX_ARM_HASH",
  "darwin": "$DARWIN_HASH",
  "darwin_aarch64": "$DARWIN_ARM_HASH"
}
EOF

echo "Updated nix/toolchain-hashes.json"

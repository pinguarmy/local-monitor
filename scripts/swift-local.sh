#!/bin/bash
# Keep compiler and SwiftPM caches inside this project's authorized workspace.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
mkdir -p "$ROOT/.build/module-cache" "$ROOT/.build/spm-cache" "$ROOT/.build/spm-config" "$ROOT/.build/spm-security"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
SUBCOMMAND="${1:-build}"
if [ "$#" -gt 0 ]; then shift; fi
exec swift "$SUBCOMMAND" --package-path "$ROOT" --cache-path "$ROOT/.build/spm-cache" --config-path "$ROOT/.build/spm-config" --security-path "$ROOT/.build/spm-security" --manifest-cache local "$@"

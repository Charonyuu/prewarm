#!/bin/bash
# Checks the schedule maths, settings migration and every usage parser.
# For a live read of the CLIs on this Mac, build and run:
#   swift build && ./.build/debug/ClaudePrewarm --probe            (reads only)
#   ./.build/debug/ClaudePrewarm --probe claude agyGemini           (also warms those)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Sources/ClaudePrewarm"
OUT="$(mktemp -d)"
swiftc -o "$OUT/verify" "$ROOT/Tools/Verify/main.swift" \
    "$SRC"/Models/*.swift \
    "$SRC"/Utilities/*.swift \
    "$SRC/Services/UsageParsers.swift" \
    "$SRC/Services/ProcessRunner.swift"
"$OUT/verify"

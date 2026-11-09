#!/bin/bash
# Ships a version end to end:
#   build → sign → notarize → staple → GitHub release → Homebrew cask
#
#   ./release.sh 1.0.1
#   ./release.sh 1.0.1 --dry-run     everything local, nothing published
set -euo pipefail

VERSION="${1:-}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

REPO="Charonyuu/prewarm"
TAP_REPO="Charonyuu/homebrew-tap"
CASK_PATH="Casks/prewarm.rb"
APP_NAME="Prewarm"
ROOT="$(cd "$(dirname "$0")" && pwd)"

die() { echo "✗ $1" >&2; exit 1; }

# ---- checks ----------------------------------------------------------------
[[ -n "$VERSION" ]] || die "Usage: ./release.sh <version> [--dry-run]   e.g. ./release.sh 1.0.1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version must look like 1.0.1, got '$VERSION'"

cd "$ROOT"
[[ -z "$(git status --porcelain)" ]] || die "Working tree is dirty. Commit or stash first."

if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    die "Tag v$VERSION already exists."
fi

CURRENT="$(grep -m1 '^VERSION=' build.sh | cut -d'"' -f2)"
echo "→ $CURRENT → $VERSION"

command -v gh >/dev/null || die "gh is not installed."
gh auth status >/dev/null 2>&1 || die "gh is not logged in."

# ---- build, sign, notarize -------------------------------------------------
sed -i '' "s/^VERSION=\".*\"/VERSION=\"$VERSION\"/" build.sh
DMG="$ROOT/build/$APP_NAME $VERSION.dmg"

if ! ./build.sh --release; then
    git checkout -- build.sh
    die "Release build failed. build.sh restored."
fi
[[ -f "$DMG" ]] || { git checkout -- build.sh; die "No dmg at $DMG"; }

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "→ sha256 $SHA"

if $DRY_RUN; then
    git checkout -- build.sh
    echo
    echo "✓ Dry run. Built and notarized, nothing published:"
    echo "  $DMG"
    exit 0
fi

# ---- publish ---------------------------------------------------------------
echo "→ Committing the version bump…"
git add build.sh
git commit -q -m "Release $VERSION"
git push -q origin HEAD

echo "→ Creating the GitHub release…"
gh release create "v$VERSION" --title "$APP_NAME $VERSION" --generate-notes "$DMG"

echo "→ Updating the Homebrew cask…"
TAP_DIR="$(mktemp -d)"
gh repo clone "$TAP_REPO" "$TAP_DIR" -- --quiet
sed -i '' "s/^  version \".*\"/  version \"$VERSION\"/" "$TAP_DIR/$CASK_PATH"
sed -i '' "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP_DIR/$CASK_PATH"
git -C "$TAP_DIR" add "$CASK_PATH"
git -C "$TAP_DIR" commit -q -m "prewarm $VERSION"
git -C "$TAP_DIR" push -q origin HEAD
rm -rf "$TAP_DIR"

cat <<DONE

✓ Shipped $VERSION

  Release   https://github.com/$REPO/releases/tag/v$VERSION
  Cask      https://github.com/$TAP_REPO/blob/main/$CASK_PATH

Anyone on it already updates with:

  brew update && brew upgrade --cask prewarm
DONE

#!/usr/bin/env bash
set -euo pipefail

TEX="${1:?tex required}"
IMAGES_DIR="${2:-}"
OUT_MD="${3:-}"
DO_PRETTIER="${4:-false}"
DO_MARKDOWNLINT="${5:-false}"
DO_TEXTLINT="${6:-false}"

ACTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTERS="$ACTION_DIR/filters"
POST="$ACTION_DIR/scripts/postformat-md.pl"

if [ -z "$OUT_MD" ]; then
  OUT_MD="${TEX%.tex}.md"
fi

# Always run from the repository root (important for container/composite action)
if [ -n "${GITHUB_WORKSPACE:-}" ] && [ -d "$GITHUB_WORKSPACE" ]; then
  cd "$GITHUB_WORKSPACE"
fi

is_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Normalize IMAGES_DIR (strip trailing slash)
IMAGES_DIR="${IMAGES_DIR%/}"

# 0) Export changed PDFs -> SVG (push only, and only inside IMAGES_DIR)
if [ -n "$IMAGES_DIR" ] && [ "${GITHUB_EVENT_NAME:-}" = "push" ]; then
  if ! is_git_repo; then
    echo "warning: not in a git repository; skipping PDF->SVG export."
  else
    BEFORE="${GITHUB_EVENT_BEFORE:-}"
    SHA="${GITHUB_SHA:-}"

    if [ -n "$SHA" ]; then
      if [ -z "$BEFORE" ] || [ "$BEFORE" = "0000000000000000000000000000000000000000" ]; then
        # First push / unusual event: list files from the commit itself
        changed_pdfs="$(git diff-tree --no-commit-id --name-only -r "$SHA" -- '*.pdf' || true)"
      else
        changed_pdfs="$(git diff --name-only "$BEFORE" "$SHA" -- '*.pdf' || true)"
      fi

      while IFS= read -r pdf; do
        [ -n "$pdf" ] || continue
        # Only export PDFs under IMAGES_DIR
        case "$pdf" in
          "$IMAGES_DIR"/*)
            [ -f "$pdf" ] || continue
            svg="${pdf%.pdf}.svg"
            echo "Inkscape: $pdf -> $svg"
            inkscape "$pdf" --export-type=svg --export-plain-svg --export-filename="$svg"
            ;;
        esac
      done <<< "$changed_pdfs"
    fi
  fi
fi

# 1) tex -> md
pandoc "$TEX" \
  --from=latex+raw_tex \
  --to=gfm+tex_math_dollars+hard_line_breaks \
  --wrap=none \
  --lua-filter="$FILTERS/title-and-levels.lua" \
  -o "${OUT_MD}.tmp"

mv "${OUT_MD}.tmp" "$OUT_MD"

# 2) md -> md normalize
pandoc "$OUT_MD" \
  --from=gfm+tex_math_dollars+hard_line_breaks \
  --to=gfm+tex_math_dollars+hard_line_breaks \
  --wrap=none \
  --lua-filter="$FILTERS/force-fenced-codeblocks.lua" \
  --lua-filter="$FILTERS/figure-html-to-md.lua" \
  --lua-filter="$FILTERS/normalize-spaces.lua" \
  -o "${OUT_MD}.tmp"

perl "$POST" "${OUT_MD}.tmp" > "$OUT_MD"
rm -f "${OUT_MD}.tmp"

# 3) Optional formatters (require tools installed by caller workflow)
if [ "$DO_PRETTIER" = "true" ]; then
  prettier --write "$OUT_MD"
fi
if [ "$DO_MARKDOWNLINT" = "true" ]; then
  markdownlint "$OUT_MD" --fix --output /dev/null || true
fi
if [ "$DO_TEXTLINT" = "true" ] && [ -f .textlintrc ]; then
  textlint --fix "$OUT_MD" || true
fi

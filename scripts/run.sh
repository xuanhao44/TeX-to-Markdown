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

# 0) Export changed PDFs -> SVG (push only, and only inside IMAGES_DIR)
if [ -n "$IMAGES_DIR" ] && [ "${GITHUB_EVENT_NAME:-}" = "push" ]; then
  BEFORE="${GITHUB_EVENT_BEFORE:-}"
  SHA="${GITHUB_SHA:-}"
  if [ -n "$BEFORE" ] && [ -n "$SHA" ]; then
    changed_pdfs="$(git diff --name-only "$BEFORE" "$SHA" -- '*.pdf' || true)"
    while IFS= read -r pdf; do
      [ -n "$pdf" ] || continue
      case "$pdf" in
        "$IMAGES_DIR"/*)
          svg="${pdf%.pdf}.svg"
          inkscape "$pdf" --export-type=svg --export-plain-svg --export-filename="$svg"
          ;;
      esac
    done <<< "$changed_pdfs"
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

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

# ---------- helpers ----------
log()  { echo "[tex-to-md] $*"; }
group(){ echo "::group::$*"; }
endgroup(){ echo "::endgroup::"; }

have() { command -v "$1" >/dev/null 2>&1; }

filesize_bytes() {
  # portable-ish: prefer wc -c
  wc -c < "$1" 2>/dev/null | tr -d ' ' || echo "?"
}

lines_count() {
  wc -l < "$1" 2>/dev/null | tr -d ' ' || echo "?"
}

is_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Normalize IMAGES_DIR (strip trailing slash)
IMAGES_DIR="${IMAGES_DIR%/}"

if [ -z "$OUT_MD" ]; then
  OUT_MD="${TEX%.tex}.md"
fi

# Expose outputs
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "out_md=$OUT_MD" >> "$GITHUB_OUTPUT"
fi

group "Inputs & environment"
log "TEX=$TEX"
log "IMAGES_DIR=${IMAGES_DIR:-<empty>}"
log "OUT_MD=$OUT_MD"
log "Formatters: prettier=$DO_PRETTIER markdownlint=$DO_MARKDOWNLINT textlint=$DO_TEXTLINT"
log "GITHUB_EVENT_NAME=${GITHUB_EVENT_NAME:-<unset>}"
log "GITHUB_SHA=${GITHUB_SHA:-<unset>}"
log "GITHUB_EVENT_BEFORE=${GITHUB_EVENT_BEFORE:-<unset>}"
log "GITHUB_WORKSPACE=${GITHUB_WORKSPACE:-<unset>}"
log "ACTION_DIR=$ACTION_DIR"
endgroup

# Always run from the repository root
if [ -n "${GITHUB_WORKSPACE:-}" ] && [ -d "$GITHUB_WORKSPACE" ]; then
  cd "$GITHUB_WORKSPACE"
fi

group "Working directory"
log "pwd=$(pwd)"
if [ -d .git ]; then
  log ".git directory exists"
else
  log ".git directory not found (may still be a git worktree/submodule, checking...)"
fi
if is_git_repo; then
  log "git repo detected: $(git rev-parse --show-toplevel 2>/dev/null || true)"
else
  log "not a git repo"
fi
endgroup

# 0) Export changed PDFs -> SVG
exported_svgs=0
group "Step 0: PDF -> SVG export (changed PDFs only)"
if [ -z "$IMAGES_DIR" ]; then
  log "IMAGES_DIR is empty; skip PDF->SVG."
elif [ "${GITHUB_EVENT_NAME:-}" != "push" ]; then
  log "Event is not push; skip PDF->SVG (current behavior)."
elif ! is_git_repo; then
  log "warning: not in a git repository; skipping PDF->SVG export."
else
  BEFORE="${GITHUB_EVENT_BEFORE:-}"
  SHA="${GITHUB_SHA:-}"

  if [ -z "$SHA" ]; then
    log "GITHUB_SHA is empty; skip diff."
  else
    if [ -z "$BEFORE" ] || [ "$BEFORE" = "0000000000000000000000000000000000000000" ]; then
      log "Using git diff-tree (first push / unusual event)"
      changed_pdfs="$(git diff-tree --no-commit-id --name-only -r "$SHA" -- '*.pdf' || true)"
    else
      log "Using git diff ($BEFORE -> $SHA)"
      changed_pdfs="$(git diff --name-only "$BEFORE" "$SHA" -- '*.pdf' || true)"
    fi

    if [ -z "$changed_pdfs" ]; then
      log "No changed PDFs detected."
    else
      log "Changed PDFs detected (showing up to 20):"
      echo "$changed_pdfs" | head -n 20 | sed 's/^/[tex-to-md]   - /'
      if [ "$(echo "$changed_pdfs" | wc -l | tr -d ' ')" -gt 20 ]; then
        log "… (truncated)"
      fi

      while IFS= read -r pdf; do
        [ -n "$pdf" ] || continue
        case "$pdf" in
          "$IMAGES_DIR"/*)
            if [ ! -f "$pdf" ]; then
              log "Skip (missing file): $pdf"
              continue
            fi
            svg="${pdf%.pdf}.svg"
            log "Inkscape: $pdf -> $svg"
            inkscape "$pdf" --export-type=svg --export-plain-svg --export-filename="$svg"
            exported_svgs=$((exported_svgs + 1))
            ;;
          *)
            : # not under images dir
            ;;
        esac
      done <<< "$changed_pdfs"

      log "Exported SVGs: $exported_svgs"
    fi
  fi
fi
endgroup

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "exported_svgs=$exported_svgs" >> "$GITHUB_OUTPUT"
fi

# 1) tex -> md
group "Step 1: Pandoc TeX -> MD"
log "Running pandoc on: $TEX"
log "Filters: $FILTERS/title-and-levels.lua"
pandoc "$TEX" \
  --from=latex+raw_tex \
  --to=gfm+tex_math_dollars+hard_line_breaks \
  --wrap=none \
  --lua-filter="$FILTERS/title-and-levels.lua" \
  -o "${OUT_MD}.tmp"

mv "${OUT_MD}.tmp" "$OUT_MD"
log "Generated: $OUT_MD (bytes=$(filesize_bytes "$OUT_MD"), lines=$(lines_count "$OUT_MD"))"
endgroup

# 2) md -> md normalize
group "Step 2: Pandoc MD -> MD normalize"
log "Input:  $OUT_MD"
log "Output: ${OUT_MD}.tmp"
log "Filters:"
log "  - $FILTERS/force-fenced-codeblocks.lua"
log "  - $FILTERS/figure-html-to-md.lua"
log "  - $FILTERS/normalize-spaces.lua"
pandoc "$OUT_MD" \
  --from=gfm+tex_math_dollars+hard_line_breaks \
  --to=gfm+tex_math_dollars+hard_line_breaks \
  --wrap=none \
  --lua-filter="$FILTERS/force-fenced-codeblocks.lua" \
  --lua-filter="$FILTERS/figure-html-to-md.lua" \
  --lua-filter="$FILTERS/normalize-spaces.lua" \
  -o "${OUT_MD}.tmp"

log "Normalized temp: ${OUT_MD}.tmp (bytes=$(filesize_bytes "${OUT_MD}.tmp"), lines=$(lines_count "${OUT_MD}.tmp"))"
endgroup

# postformat
group "Step 2b: Post-format (perl)"
before_bytes="$(filesize_bytes "${OUT_MD}.tmp")"
perl "$POST" "${OUT_MD}.tmp" > "$OUT_MD"
after_bytes="$(filesize_bytes "$OUT_MD")"
rm -f "${OUT_MD}.tmp"
log "Postformat: ${before_bytes} bytes -> ${after_bytes} bytes"
endgroup

# 3) Optional formatters
group "Step 3: Optional formatters"
if [ "$DO_PRETTIER" = "true" ]; then
  if have prettier; then
    log "Prettier: enabled ($(prettier --version 2>/dev/null || echo unknown))"
    prettier --write "$OUT_MD"
  else
    log "warning: prettier not found; skipping."
  fi
else
  log "Prettier: disabled"
fi

if [ "$DO_MARKDOWNLINT" = "true" ]; then
  if have markdownlint; then
    log "Markdownlint: enabled"
    markdownlint "$OUT_MD" --fix --output /dev/null || true
  else
    log "warning: markdownlint not found; skipping."
  fi
else
  log "Markdownlint: disabled"
fi

if [ "$DO_TEXTLINT" = "true" ]; then
  if [ -f .textlintrc ]; then
    if have textlint; then
      log "Textlint: enabled"
      textlint --fix "$OUT_MD" || true
    else
      log "warning: textlint not found; skipping."
    fi
  else
    log "Textlint: .textlintrc not found; skipping."
  fi
else
  log "Textlint: disabled"
fi

log "Final: $OUT_MD (bytes=$(filesize_bytes "$OUT_MD"), lines=$(lines_count "$OUT_MD"))"
endgroup

log "Done."

# TeX-to-Markdown

## Use Sample

Generate md files and add, commit, push to your repo.

Need give Workflow permissions - Read and write permissions.

```yaml
jobs:
  tex_to_md:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/xuanhao44/tex-to-md-tools:latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: TeX -> MD pipeline
        uses: xuanhao44/TeX-to-Markdown@v0.0.3
        env:
          GITHUB_EVENT_BEFORE: ${{ github.event.before }}
        with:
          tex: main.tex
          images_dir: figs
          prettier: "false"
          markdownlint: "false"
          textlint: "false"

      - name: Mark repository as safe
        run: git config --global --add safe.directory "$GITHUB_WORKSPACE"

      - name: Commit and Push changes
        if: ${{ github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'workflow_dispatch') }}
        shell: bash
        run: |
          set -euo pipefail
          git config --global user.name "github-actions[bot]"
          git config --global user.email "github-actions[bot]@users.noreply.github.com"

          git add main.md

          if [ "${{ github.event_name }}" = "push" ]; then
            BEFORE="${{ github.event.before }}"
            SHA="${{ github.sha }}"

            if [ "$BEFORE" = "0000000000000000000000000000000000000000" ]; then
              changed_pdfs=$(git diff-tree --no-commit-id --name-only -r "$SHA" -- '*.pdf' || true)
            else
              changed_pdfs=$(git diff --name-only "$BEFORE" "$SHA" -- '*.pdf' || true)
            fi

            while IFS= read -r pdf; do
              [ -n "$pdf" ] || continue
              svg="${pdf%.pdf}.svg"
              [ -f "$svg" ] && git add "$svg" || true
            done <<< "$changed_pdfs"
          fi

          if git diff --cached --quiet; then
            echo "No changes to commit."
            exit 0
          fi

          git commit -m "Automated tex to md conversion and formatting"
          git push
```

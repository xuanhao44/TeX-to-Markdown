# TeX-to-Markdown

## 在“别的仓库”里怎么用（最小调用示例）

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
        uses: xuanhao44/TeX-to-Markdown@v0.0.1
        env:
          GITHUB_EVENT_BEFORE: ${{ github.event.before }}
        with:
          tex: main.tex
          images_dir: figs
          prettier: "false"
          markdownlint: "false"
          textlint: "false"

      # commit/push 仍然放在调用方 workflow 里（因为每个仓库策略不同）
      - name: Mark repository as safe
        run: git config --global --add safe.directory "$GITHUB_WORKSPACE"

      - name: Commit and Push changes
        if: ${{ github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'workflow_dispatch') }}
        shell: bash
        run: |
          set -euo pipefail
          git config --global user.name "github-actions[bot]"
          git config --global user.email "github-actions[bot]@users.noreply.github.com"

          # always only commit the generated main.md
          git add main.md

          # only add the svg files corresponding to changed pdfs in this push to the staging area
          if [ "${{ github.event_name }}" = "push" ]; then
            changed_pdfs=$(git diff --name-only "${{ github.event.before }}" "${{ github.sha }}" -- '*.pdf' || true)
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

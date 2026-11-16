#!/usr/bin/env bash
# Downloads the pinned web assets used to style and highlight rendered Markdown.
# Output is committed, so this only needs re-running when bumping versions.
set -euo pipefail

HLJS=11.11.1
GHCSS=5.8.1
EXTRA_LANGS=(dockerfile powershell nginx protobuf dart scala)

CDN=https://cdnjs.cloudflare.com/ajax/libs
OUT="$(cd "$(dirname "$0")/.." && pwd)/Shared/Resources"
mkdir -p "$OUT"

fetch() { curl -fsSL --retry 2 "$1" -o "$2"; echo "  $2"; }

echo "highlight.js $HLJS"
fetch "$CDN/highlight.js/$HLJS/highlight.min.js" "$OUT/highlight.min.js"
for lang in "${EXTRA_LANGS[@]}"; do
  curl -fsSL --retry 2 "$CDN/highlight.js/$HLJS/languages/$lang.min.js" >> "$OUT/highlight.min.js"
  printf '\n' >> "$OUT/highlight.min.js"
  echo "  + $lang"
done
fetch "$CDN/highlight.js/$HLJS/styles/github.min.css"      "$OUT/hljs-github.css"
fetch "$CDN/highlight.js/$HLJS/styles/github-dark.min.css" "$OUT/hljs-github-dark.css"

echo "github-markdown-css $GHCSS"
fetch "$CDN/github-markdown-css/$GHCSS/github-markdown-light.min.css" "$OUT/github-markdown-light.css"
fetch "$CDN/github-markdown-css/$GHCSS/github-markdown-dark.min.css"  "$OUT/github-markdown-dark.css"

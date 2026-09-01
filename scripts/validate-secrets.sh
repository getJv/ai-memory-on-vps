#!/bin/sh
set -eu
dir=${1:-secrets}
for file in ai-memory-auth-token ai-memory-token-pepper openrouter-api-key; do
  path="$dir/$file"
  [ -s "$path" ] || { echo "Missing or empty secret: $path" >&2; exit 1; }
  mode=$(stat -c '%a' "$path")
  [ "$mode" = 600 ] || { echo "$path must have mode 0600, got $mode" >&2; exit 1; }
done
echo "Secret files are present and private."

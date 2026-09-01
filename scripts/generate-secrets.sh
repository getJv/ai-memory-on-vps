#!/bin/sh
set -eu
umask 077
out=${1:-secrets}
mkdir -p "$out"
[ -e "$out/ai-memory-auth-token" ] || openssl rand -hex 32 > "$out/ai-memory-auth-token"
[ -e "$out/ai-memory-token-pepper" ] || openssl rand -hex 32 > "$out/ai-memory-token-pepper"
chmod 600 "$out/ai-memory-auth-token" "$out/ai-memory-token-pepper"
echo "Created missing secrets. Add $out/openrouter-api-key with mode 0600."

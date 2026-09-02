#!/bin/sh
set -eu

VERSION=${AI_MEMORY_VERSION:-1.21.0}
DEFAULT_TOKEN_FILE="$(pwd)/secrets/ai-memory-auth-token"
CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/ai-memory
ENV_FILE="$CONFIG_DIR/client.env"
FISH_ENV_FILE="$CONFIG_DIR/client.fish"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

case "$(uname -s):$(uname -m)" in
  Linux:x86_64|Linux:amd64) ARTIFACT=ai-memory-linux-x86_64.tar.gz ;;
  Linux:aarch64|Linux:arm64) ARTIFACT=ai-memory-linux-aarch64.tar.gz ;;
  *) echo "Unsupported platform. This installer supports Linux x86_64 and aarch64." >&2; exit 1 ;;
esac

printf 'Remote ai-memory server URL (without /mcp): '
read -r SERVER_URL
[ -n "$SERVER_URL" ] || { echo "Server URL is required." >&2; exit 1; }
SERVER_URL=${SERVER_URL%/}
case "$SERVER_URL" in
  */mcp) SERVER_URL=${SERVER_URL%/mcp} ;;
esac

TOKEN_FILE=${AI_MEMORY_TOKEN_FILE:-$DEFAULT_TOKEN_FILE}
if [ ! -r "$TOKEN_FILE" ]; then
  printf 'Path to the ai-memory auth token file [%s]: ' "$TOKEN_FILE"
  read -r requested_token_file
  TOKEN_FILE=${requested_token_file:-$TOKEN_FILE}
fi
[ -s "$TOKEN_FILE" ] || { echo "Token file not found or empty: $TOKEN_FILE" >&2; exit 1; }

mkdir -p "$HOME/.local/bin" "$HOME/.ai-memory/hooks/codex" "$HOME/.agents/skills" "$HOME/.codex" "$CONFIG_DIR"

BASE_URL="https://github.com/akitaonrails/ai-memory/releases/download/v${VERSION}"
ARCHIVE="$TMP_DIR/$ARTIFACT"
CHECKSUM="$TMP_DIR/$ARTIFACT.sha256"
echo "Downloading ai-memory ${VERSION} for $(uname -m)..."
curl -fL "$BASE_URL/$ARTIFACT" -o "$ARCHIVE"
curl -fL "$BASE_URL/$ARTIFACT.sha256" -o "$CHECKSUM"
(
  cd "$TMP_DIR"
  sha256sum -c "$ARTIFACT.sha256"
)

tar -xzf "$ARCHIVE" -C "$TMP_DIR"
BINARY=$(find "$TMP_DIR" -type f -name ai-memory -perm -u+x | head -n 1)
[ -n "$BINARY" ] || { echo "The release archive did not contain an executable ai-memory binary." >&2; exit 1; }
install -m 0755 "$BINARY" "$HOME/.local/bin/ai-memory"

export PATH="$HOME/.local/bin:$PATH"
export AI_MEMORY_SERVER_URL="$SERVER_URL"
export AI_MEMORY_AUTH_TOKEN=$(cat "$TOKEN_FILE")

printf '%s\n' "Installing global Codex hooks..."
ai-memory setup-agent \
  --agent codex \
  --to "$HOME/.ai-memory/hooks/codex" \
  --host-prefix "$HOME/.ai-memory/hooks/codex" \
  --source "$TMP_DIR/hooks" \
  --server-url "$SERVER_URL" \
  --auth-token "$AI_MEMORY_AUTH_TOKEN" \
  >/dev/null

ai-memory install-hooks \
  --agent codex \
  --hooks-dir "$HOME/.ai-memory/hooks" \
  --server-url "$SERVER_URL" \
  --auth-token "$AI_MEMORY_AUTH_TOKEN" \
  --apply

printf '%s\n' "Installing global Agent Skills and AGENTS.md..."
ai-memory install-instructions \
  --target "$HOME/.codex/AGENTS.md" \
  --skills-scope global \
  --skills-agent agents \
  --skills-target-dir "$HOME/.agents/skills"

umask 077
{
  printf 'export AI_MEMORY_SERVER_URL=%s\n' "$(printf '%s' "$SERVER_URL" | sed "s/'/'\\''/g; s/^/'/; s/$/'/")"
  printf 'export AI_MEMORY_AUTH_TOKEN=$(cat %s)\n' "$(printf '%s' "$TOKEN_FILE" | sed "s/'/'\\''/g; s/^/'/; s/$/'/")"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

umask 077
{
  printf "set -gx AI_MEMORY_SERVER_URL '%s'\n" "$(printf '%s' "$SERVER_URL" | sed "s/'/'\\''/g")"
  printf "set -gx AI_MEMORY_AUTH_TOKEN (cat '%s')\n" "$(printf '%s' "$TOKEN_FILE" | sed "s/'/'\\''/g")"
} > "$FISH_ENV_FILE"
chmod 600 "$FISH_ENV_FILE"

add_once() {
  rc_file=$1
  source_line=$2
  mkdir -p "$(dirname "$rc_file")"
  touch "$rc_file"
  grep -Fqx "$source_line" "$rc_file" 2>/dev/null || printf '%s\n' "$source_line" >> "$rc_file"
}

add_once "$HOME/.config/fish/config.fish" "test -f '$FISH_ENV_FILE'; and source '$FISH_ENV_FILE'"
add_once "$HOME/.bashrc" "[ -f '$ENV_FILE' ] && . '$ENV_FILE'"
add_once "$HOME/.zshrc" "[ -f '$ENV_FILE' ] && . '$ENV_FILE'"

echo
echo "Local ai-memory client installation completed."
echo "Binary: $HOME/.local/bin/ai-memory"
echo "Hooks:  $HOME/.ai-memory/hooks"
echo "Skills: $HOME/.agents/skills"
echo "Rules:  $HOME/.codex/AGENTS.md"
echo
echo "If ~/.local/bin is not already in PATH, run:"
echo "export PATH=\"\$HOME/.local/bin:\$PATH\""
echo "To load the server settings in a shell: source \"$ENV_FILE\""
echo "Fish users: source \"$FISH_ENV_FILE\" (it will be loaded automatically in new shells)."

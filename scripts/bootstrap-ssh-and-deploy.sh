#!/bin/sh
set -eu

if [ "$#" -gt 0 ]; then
  server=$1
else
  [ -f ansible/inventory/hosts.yml ] || {
    echo "Missing ansible/inventory/hosts.yml. Create it from the example first." >&2
    exit 1
  }
  server=$(awk '/^[[:space:]]*ansible_host:/ {print $2; exit}' ansible/inventory/hosts.yml)
  [ -n "$server" ] || {
    echo "Could not find ansible_host in ansible/inventory/hosts.yml." >&2
    exit 1
  }
fi
remote_user=${REMOTE_USER:-root}
key_path=${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}
pub_path="$key_path.pub"

printf '%s\n' "SSH bootstrap target: $remote_user@$server"

# If the default or explicitly selected key already works, do not prompt for
# a password or offer to create another key.
key_ready=0
if [ -r "$key_path" ] && [ -r "$pub_path" ] && \
  ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$key_path" "$remote_user@$server" true 2>/dev/null; then
  echo "The selected SSH key already works on the server. No password or new key is needed."
  key_ready=1
fi

if [ "$key_ready" -eq 0 ]; then
  printf '%s\n' "1) Use existing public key: $pub_path"
  printf '%s\n' "2) Generate a new ED25519 key pair"
  printf 'Choose [1]: '
  read -r choice
  choice=${choice:-1}

  case "$choice" in
    1)
      [ -r "$pub_path" ] || { echo "Public key not found: $pub_path" >&2; exit 1; }
      ;;
    2)
      printf 'New private key path [%s]: ' "$key_path"
      read -r requested_path
      key_path=${requested_path:-$key_path}
      pub_path="$key_path.pub"
      if [ -e "$key_path" ] || [ -e "$pub_path" ]; then
        echo "Refusing to overwrite an existing key: $key_path" >&2
        exit 1
      fi
      mkdir -p "$(dirname "$key_path")"
      ssh-keygen -t ed25519 -f "$key_path" -C "ai-memory-$(date +%Y%m%d)"
      ;;
    *) echo "Invalid choice" >&2; exit 1 ;;
  esac

  echo "The next command may ask for the VPS root password or console-created password."
  ssh-copy-id -i "$pub_path" "$remote_user@$server"
  ssh -o BatchMode=yes -i "$key_path" "$remote_user@$server" true
fi

echo "SSH access is ready. Starting the Ansible deployment..."
[ -x "$(command -v ansible-playbook 2>/dev/null || true)" ] || { echo "ansible-playbook is not installed or is not in PATH." >&2; exit 1; }
[ -x "$(command -v python3 2>/dev/null || true)" ] || { echo "python3 is required to create the temporary Ansible variables file." >&2; exit 1; }
[ -f ansible/inventory/hosts.yml ] || { echo "Missing ansible/inventory/hosts.yml" >&2; exit 1; }
[ -f ansible/group_vars/all.yml ] || { echo "Missing ansible/group_vars/all.yml" >&2; exit 1; }
./scripts/validate-secrets.sh

# Keep secret values out of the process list. mktemp creates this file with mode
# 0600, and the trap removes it when Ansible exits or the script is interrupted.
vars_file=$(mktemp "${TMPDIR:-/tmp}/ai-memory-ansible-vars.XXXXXX")
trap 'rm -f "$vars_file"' EXIT HUP INT TERM
python3 - "$vars_file" "$pub_path" <<'PY'
import json
import pathlib
import sys

destination = pathlib.Path(sys.argv[1])
public_key = pathlib.Path(sys.argv[2]).read_text().strip()
values = {
    "ssh_public_key": public_key,
    "ai_memory_auth_token": pathlib.Path("secrets/ai-memory-auth-token").read_text().strip(),
    "ai_memory_token_pepper": pathlib.Path("secrets/ai-memory-token-pepper").read_text().strip(),
    "openrouter_api_key": pathlib.Path("secrets/openrouter-api-key").read_text().strip(),
}
destination.write_text(json.dumps(values))
PY

ansible-playbook -i ansible/inventory/hosts.yml ansible/site.yml \
  --private-key "$key_path" \
  -e "@$vars_file"

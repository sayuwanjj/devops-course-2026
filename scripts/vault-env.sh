#!/usr/bin/env bash
# Формирует файл переменных окружения приложения из секрета Vault.
# Вход выполняется по AppRole: VAULT_ROLE_ID и VAULT_SECRET_ID передаются через окружение.
# Использование: VAULT_ROLE_ID=... VAULT_SECRET_ID=... scripts/vault-env.sh [файл]
set -euo pipefail
: "${VAULT_ROLE_ID:?не задан VAULT_ROLE_ID}" "${VAULT_SECRET_ID:?не задан VAULT_SECRET_ID}"
OUT="${1:-$HOME/app/.env.vault}"
SECRET_PATH="secret/devops-app/db"

vlt() { docker exec -i -e VAULT_TOKEN="${TOKEN:-}" vault-dev vault "$@"; }

# 1. Вход по AppRole: получаем токен с политикой app-read
TOKEN="$(vlt write -field=token auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")"

# 2. Чтение секрета и запись файла с правами 600
umask 077
vlt kv get -format=json "$SECRET_PATH" | jq -r '.data.data | to_entries[] | "\(.key)=\(.value)"' > "$OUT"
chmod 600 "$OUT"

# 3. Отзыв токена: он больше не нужен
vlt token revoke -self >/dev/null
echo "vault-env: из ${SECRET_PATH} записано переменных: $(wc -l < "$OUT"), файл ${OUT}"

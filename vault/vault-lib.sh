# Окружение для работы с Vault на devops-vm (подключается командой source)
# Клиент vault запускается внутри контейнера vault-dev; токен берётся из файла с правами 600
export VAULT_TOKEN="$(cat ~/.vault-root 2>/dev/null)"
vault() { docker exec -i -e VAULT_TOKEN="$VAULT_TOKEN" vault-dev vault "$@"; }

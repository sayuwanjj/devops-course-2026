#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel)"      # требование 2: работает из любого каталога репозитория
cd "$REPO_ROOT"                                   # в Git Bash путь вида C:/... rsync принял бы за удалённый
LOCAL_DIR="site/"

err() { echo "deploy: $*" >&2; }

# 1. Разбор аргумента --dry-run
DRY_RUN=""
case "${1:-}" in
  "")        ;;
  --dry-run) DRY_RUN="--dry-run" ;;
  *)         err "неизвестный параметр: $1 (допустимо: --dry-run)"; exit 1 ;;
esac

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
  err "нет файла site/index.html — доставка отменена (иначе --delete удалит главную страницу)"
  exit 1
fi
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
  err "в репозитории есть незафиксированные изменения — доставка отменена:"
  git -C "$REPO_ROOT" status --short >&2
  exit 1
fi
COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

# 3. Синхронизация: точная копия site/ с правами 755/644, одно SSH-соединение,
#    без интерактивного запроса пароля (BatchMode) и с ограничением ожидания
rsync -avz --delete --chmod=D755,F644 ${DRY_RUN} \
  -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
  "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 4. При --dry-run — завершение без проверки доступности
if [[ -n "$DRY_RUN" ]]; then
  echo "deploy: пробный запуск, сервер не изменён (коммит ${COMMIT})"
  exit 0
fi

# 5. Проверка доступности с проверкой сертификата (без -k)
if ! curl -fsS --max-time 10 --cacert "$CA_CERT" -o /dev/null "$SITE_URL/"; then
  err "ресурс ${SITE_URL} недоступен после доставки"
  exit 1
fi
echo "deploy: успешно, доставлен коммит ${COMMIT}"
exit 0

#!/usr/bin/env bash
# Аудит конфигурации devops-vm. Запуск на сервере: sudo bash scripts/audit.sh [дней_до_истечения_сертификата]
set -uo pipefail

PASS=0; FAIL=0
CERT_DAYS="${1:-30}"

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
# TODO 1: порт службы отличен от 22
SSH_PORT="$(sudo sshd -T | awk '/^port /{print $2; exit}')"
check "Порт SSH отличен от 22"             "yes" "$([[ -n "$SSH_PORT" && "$SSH_PORT" != "22" ]] && echo yes || echo "no ($SSH_PORT)")"
# TODO 2: MaxAuthTries равно 3
check "MaxAuthTries равно 3"               "3"  "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
# TODO 3: политика по умолчанию для входящего трафика — deny
check "Политика входящего трафика deny" "deny" "$(sudo ufw status verbose | awk -F'[ :(,]+' '/^Default:/{print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "         %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
check "Конфигурация nginx корректна" "0" "$(sudo nginx -t >/dev/null 2>&1; echo $?)"
check "Сертификат действует ещё не менее ${CERT_DAYS} дн." "0" \
      "$(openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend $((CERT_DAYS*86400)) >/dev/null; echo $?)"
check "Нет файлов ресурса с правом записи для всех" "" "$(sudo find /var/www/devops-site -perm -o+w)"
check "Права закрытого ключа TLS равны 600" "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key)"

echo "[5] Контейнеризация"
APP_ENV="/home/${SUDO_USER:-$USER}/app/.env"
check "Служба docker активна" "active" "$(systemctl is-active docker)"
check "Контейнер СУБД в состоянии healthy" "healthy" \
      "$(sudo docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null)"
check "Порты 5000 и 5432 прослушиваются только на 127.0.0.1" "" \
      "$(ss -tlnH | awk '{print $4}' | grep -E ':(5000|5432)$' | grep -v '^127\.0\.0\.1:' | tr '\n' ' ' | sed 's/ $//')"
check "Права файла ~/app/.env равны 600" "600" "$(stat -c '%a' "$APP_ENV" 2>/dev/null)"

echo "[6] Хранилище секретов"
check "Контейнер vault-dev запущен" "true" "$(sudo docker inspect -f '{{.State.Running}}' vault-dev 2>/dev/null)"
check "Vault распечатан (sealed=false)" "false" \
      "$(sudo docker exec vault-dev vault status -format=json 2>/dev/null | jq -r .sealed)"
check "Порт 8200 прослушивается только на 127.0.0.1" "" \
      "$(ss -tlnH | awk '{print $4}' | grep -E ':8200$' | grep -v '^127\.0\.0\.1:' | tr '\n' ' ' | sed 's/ $//')"
check "Файл с корневым токеном имеет права 600" "600" "$(stat -c '%a' "/home/${SUDO_USER:-$USER}/.vault-root" 2>/dev/null)"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

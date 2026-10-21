# Конфигурация виртуальной машины devops-vm

Документ позволяет восстановить конфигурацию со снимка `01-clean-install`.
Команды с пометкой **[Хост]** выполняются в Git Bash на ноутбуке (Windows), **[VM]** — на сервере.

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Средство виртуализации | Oracle VirtualBox 7.x (Windows, работает поверх Hyper-V) |
| Имя ВМ | devops-vm |
| Гостевая ОС | Ubuntu Server 24.04 LTS (официальный образ `noble-server-cloudimg-amd64.ova`), тип Linux / Ubuntu (64-bit) |
| Оперативная память | 2048 МБ |
| Процессор | 2 ядра |
| Диск | 25 ГБ, VDI, динамически расширяемый (`E:\devops-vm\devops-vm\devops-vm.vdi`) |
| Первичная настройка | cloud-init (NoCloud, `seed.iso`): имя узла `devops-vm`, пользователь `student` (группа sudo, пароль), часовой пояс Europe/Moscow |

## 2. Сетевые интерфейсы

| Адаптер | Тип | Адрес в ВМ | Назначение |
|---|---|---|---|
| 1 | NAT | 10.0.2.15/24 (шлюз 10.0.2.2) | доступ в Интернет (apt), вход по SSH и доступ к веб-серверу через проброс портов |
| 2 | отключён | — | адаптер Host-only в Windows не запустился (`VERR_INTNET_FLT_IF_NOT_FOUND`, VirtualBox работает поверх Hyper-V); вместо прямого доступа по адресу 192.168.56.x используется проброс портов NAT на 127.0.0.1 |

## 3. Правила проброса портов (адаптер 1, NAT)

| Правило | Протокол | Адрес:порт хоста | Порт гостя | Назначение |
|---|---|---|---|---|
| ssh | TCP | 127.0.0.1:2222 | 2222 (до усиления SSH — 22) | SSH |
| http | TCP | 127.0.0.1:80 | 80 | HTTP (ПР № 6) |
| https | TCP | 127.0.0.1:443 | 443 | HTTPS (ПР № 6) |
| test8080 | TCP | 127.0.0.1:8080 | 8080 | проверка блокировки UFW (задание 3.4) |

Порты хоста совпадают с портами гостя, поэтому перенаправление `return 301 https://$host$request_uri` в ПР № 6 работает без указания порта.

```bash
# [Хост], ВМ выключена
VBoxManage modifyvm devops-vm --nic1 nat --nic2 none
VBoxManage modifyvm devops-vm --natpf1 "ssh,tcp,127.0.0.1,2222,,22"
VBoxManage modifyvm devops-vm --natpf1 "http,tcp,127.0.0.1,80,,80" --natpf1 "https,tcp,127.0.0.1,443,,443" --natpf1 "test8080,tcp,127.0.0.1,8080,,8080"
# [Хост] после переноса SSH на порт 2222 (задание 2), ВМ работает
VBoxManage controlvm devops-vm natpf1 delete ssh
VBoxManage controlvm devops-vm natpf1 "ssh,tcp,127.0.0.1,2222,,2222"
```

## 4. Учётные записи

| Имя | Группы | Аутентификация по SSH |
|---|---|---|
| student | student, sudo | вход по SSH запрещён (`AllowUsers devops`); используется в консоли |
| devops | devops, sudo | только по ключу `~/.ssh/devops_vm` (ed25519), пароль — для sudo |

```bash
# [VM] от имени student
sudo adduser devops
sudo usermod -aG sudo devops
# [Хост]
ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm
ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1
# права на сервере: ~/.ssh — 700, ~/.ssh/authorized_keys — 600
```

Клиентский файл `~/.ssh/config` на хосте:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

Основной файл `/etc/ssh/sshd_config` не изменяется (копия — `/etc/ssh/sshd_config.backup`).
Настройки — в дополняющем файле `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Строки `PasswordAuthentication yes` в других файлах `/etc/ssh/sshd_config.d/*.conf` (создаются cloud-init)
закомментированы — иначе они действуют раньше файла `99-`.

```bash
# [VM]
sudo sed -i 's/^PasswordAuthentication yes/#&/' /etc/ssh/sshd_config.d/50-cloud-init.conf
sudo sshd -t && sudo sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)"
sudo systemctl disable --now ssh.socket      # иначе порт задаёт ssh.socket (22)
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd                    # 0.0.0.0:2222
```

Проверка выполняется в новом терминале, не закрывая старую сессию.

## 6. Правила межсетевого экрана

Политики по умолчанию: `deny (incoming)`, `allow (outgoing)`. Журналирование: `medium`.

| Порт | Действие | Комментарий |
|---|---|---|
| 2222/tcp | LIMIT IN | SSH rate-limited (≥ 6 соединений за 30 с — блокировка) |
| 80/tcp | ALLOW IN | HTTP |
| 443/tcp | ALLOW IN | HTTPS |

```bash
# [VM] — правило для SSH создаётся ДО включения
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw logging medium
```

Имя узла: `sudo hostnamectl set-hostname devops-vm`, в `/etc/hosts` строка
`127.0.1.1 devops-vm.devops.local devops-vm` (`hostname -f` → `devops-vm.devops.local`).
На хосте в `C:\Windows\System32\drivers\etc\hosts`: `127.0.0.1    devops.local` (доступ через проброс портов NAT).

## 7. Снимки состояния

| Снимок | Момент создания |
|---|---|
| 01-clean-install | после первой загрузки и `apt update && apt upgrade`, ВМ выключена |
| 02-keys-configured | после создания devops, размещения ключа и `~/.ssh/config` (задание 1) |
| 03-ssh-hardened | после усиления SSH и смены проброса порта (задание 2) |

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Пакет | `nginx` (Ubuntu 24.04, `sudo apt install -y nginx`) |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, ссылка в `/etc/nginx/sites-enabled/`; стандартный ресурс `default` отключён (ссылка удалена) |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, права каталогов 755, файлов 644 (модель «владелец пишет, веб-сервер читает») |
| Сертификат | `/etc/ssl/certs/devops.crt`, `root:root`, 644, самоподписанный, CN и SAN `DNS:devops.local`, срок 365 дней |
| Закрытый ключ | `/etc/ssl/private/devops.key`, `root:root`, 600 |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |
| Доставка содержимого | `scripts/deploy.sh` (rsync `--delete --chmod=D755,F644` через псевдоним `devops`) |

```bash
# [VM]
sudo apt install -y nginx
sudo mkdir -p /var/www/devops-site && sudo chown -R devops:devops /var/www/devops-site
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
# [Хост]
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
scripts/deploy.sh
```

Конфигурация `/etc/nginx/sites-available/devops-site`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;

    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;

    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

Снимок состояния `04-nginx-https` — после перевода ресурса на HTTPS (задание 2).

## 9. Контейнеризация

| Параметр | Значение |
|---|---|
| Установка Docker Engine | официальный репозиторий Docker (https://download.docker.com), пакеты `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`; пакет `docker.io` не используется |
| Версия | Docker Engine 29.9.2, Docker Compose 5.6.1 |
| Реестр образов | Docker Hub (без зеркала) |
| Участники группы `docker` | `devops` (имеет право sudo; участие в группе `docker` равносильно правам root) |
| Расположение проекта | `/home/devops/app` (доставляется с хоста: `rsync -avz --delete --exclude=.env app/ devops:app/`) |
| Файл секретов | `/home/devops/app/.env`, владелец `devops`, права `600`; создаётся только на сервере из `.env.example`, пароль — `openssl rand -hex 16`; в репозиторий и на хост не копируется |
| Сервисы | `app` (образ `devops-app:1.0`, пользователь `app`, gunicorn на порту 5000), `db` (`postgres:16-alpine`, проверка `pg_isready`) |
| Публикуемые порты | `127.0.0.1:5000 → app:5000`; порт СУБД 5432 не публикуется |
| Сеть | пользовательская сеть `app_backend` (bridge), СУБД доступна приложению по имени `db` |
| Именованные тома | `app_db_data` → `/var/lib/postgresql/data` |
| Обратный прокси-сервер | Nginx, `location /app/` в блоке HTTPS, `proxy_pass http://127.0.0.1:5000/` |

Развёртывание проекта:

```bash
# [Хост] из корня репозитория
rsync -avz --delete --exclude=.env app/ devops:app/
# [VM] однократно — секреты
cd ~/app && cp .env.example .env && chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
# [VM] запуск и проверка
docker compose up -d --build
docker compose ps
curl -s http://127.0.0.1:5000/
```

Фрагмент блока HTTPS `/etc/nginx/sites-available/devops-site`:

```nginx
    location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

Публиковать порт контейнера на `0.0.0.0` нельзя: правила Docker в iptables обрабатывают пакет раньше UFW, и порт становится доступен из сети без разрешающего правила (проверено на порту 5001, шаг 3.1 ПР № 7).

Снимок состояния `05-docker-compose` — после запуска конфигурации «приложение + СУБД» (задание 2 ПР № 7).


## 10. Хранилище секретов (HashiCorp Vault)

| Параметр | Значение |
|---|---|
| Режим | dev-сервер Vault в контейнере `vault-dev` (образ `hashicorp/vault:1.20`, версия v1.20.4) — учебный стенд: хранилище в памяти, автоматически распечатано, данные теряются при перезапуске |
| Запуск | `docker run -d --name vault-dev --cap-add=IPC_LOCK -p 127.0.0.1:8200:8200 -e VAULT_DEV_ROOT_TOKEN_ID -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 -e VAULT_ADDR=http://127.0.0.1:8200 hashicorp/vault:1.20` |
| Адрес API | `http://127.0.0.1:8200` (только локальный адрес сервера; из сети недоступен) |
| Корневой токен | случайный (`openssl rand -hex 16`), файл `~/.vault-root`, права `600`; в репозиторий и отчёт не попадает |
| Клиент | функция `vault()` из `~/vault/vault-lib.sh` — вызывает `vault` внутри контейнера через `docker exec` |
| Механизмы секретов | `secret/` — KV версии 2; `database/` — динамические учётные записи PostgreSQL; `transit/` — шифрование как сервис |
| Методы аутентификации | `token`, `approle` (роль `devops-app`) |
| Политики | `app-read` — чтение `secret/data/devops-app/*` (файл `vault/policies/app-read.hcl`) |
| Секрет приложения | `secret/devops-app/db` — переменные `POSTGRES_*` и `DB_HOST` из `~/app/.env` |
| Получение секрета приложением | `scripts/vault-env.sh`: вход по AppRole → чтение `secret/devops-app/db` → файл с правами 600 → отзыв токена |
| Динамические учётные записи БД | подключение `database/config/app-db` (контейнер подключён к сети `app_backend`), роль `readonly` (`SELECT`, TTL 1 ч, максимум 24 ч) |
| Журнал аудита | файловое устройство аудита `/tmp/vault-audit.log` внутри контейнера |

Запуск и первичная настройка:

```bash
# [VM]
umask 077; openssl rand -hex 16 > ~/.vault-root; umask 022
export VAULT_DEV_ROOT_TOKEN_ID="$(cat ~/.vault-root)"
docker run -d --name vault-dev --cap-add=IPC_LOCK -p 127.0.0.1:8200:8200 \
  -e VAULT_DEV_ROOT_TOKEN_ID -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  -e VAULT_ADDR=http://127.0.0.1:8200 hashicorp/vault:1.20
source ~/vault/vault-lib.sh
vault policy write app-read - < ~/vault/app-read.hcl
vault auth enable approle
vault write auth/approle/role/devops-app token_policies=app-read token_ttl=1h secret_id_ttl=24h
vault kv put secret/devops-app/db $(grep -v '^#' ~/app/.env | xargs)
```

Ограничение учебного стенда: dev-сервер хранит данные в памяти. Для эксплуатации требуется сервер с постоянным хранилищем (`storage "raft"`), TLS, распечатыванием по ключам Шамира или auto-unseal и отказом от корневого токена после настройки.

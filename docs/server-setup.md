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

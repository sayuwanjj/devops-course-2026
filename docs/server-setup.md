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
| 1 | NAT | 10.0.2.15/24 | доступ в Интернет (apt), вход по SSH через проброс порта |
| 2 | Host-only (VirtualBox Host-Only Ethernet Adapter) | 127.0.0.1/24 (DHCP) | прямой доступ с хоста: веб-сервер, имя `devops.local` |

## 3. Правило проброса портов

Адаптер 1 (NAT), правило `ssh`: TCP, адрес хоста `127.0.0.1`, **порт хоста 2222 → порт гостя 2222**
(до усиления SSH гостевой порт был 22).

```bash
# [Хост]
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
На хосте в `C:\Windows\System32\drivers\etc\hosts`: `127.0.0.1    devops.local`.

## 7. Снимки состояния

| Снимок | Момент создания |
|---|---|
| 01-clean-install | после первой загрузки и `apt update && apt upgrade`, ВМ выключена |
| 02-keys-configured | после создания devops, размещения ключа и `~/.ssh/config` (задание 1) |
| 03-ssh-hardened | после усиления SSH и смены проброса порта (задание 2) |

# GemoniCLIonVPS

> **Gemini CLI в Docker-контейнере на VPS** — безопасный, изолированный доступ через SSH.

**Стабильная версия: `v1.0.0`** — проверена в боевых условиях на Ubuntu VPS 1GB RAM.

---

## Архитектура

```
Локальная машина
    │
    └─ SSH ──► VPS (gemini-vps@host)
                    │
                    └─ docker exec ──► gemini-cli-service (контейнер)
                                            │
                                            ├─ Gemini CLI (interactive TUI)
                                            ├─ tmux
                                            └─ /workspace (volume)
```

**Ключевые решения:**
- Нет открытых портов контейнера — доступ только через `docker exec`
- Контейнер работает от непривилегированного пользователя `gemini` (UID 1001)
- `gosu` для безопасного сброса привилегий из entrypoint
- OAuth-токены хранятся в именованном volume — переживают пересборку образа

---

## Быстрый старт (чистая VPS)

### 1. Добавь SSH-ключ до запуска скрипта

```bash
# На локальной машине:
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@YOUR_VPS_IP
```

### 2. Запусти скрипт установки

```bash
ssh root@YOUR_VPS_IP
curl -fsSL https://raw.githubusercontent.com/Demonhmr/GemoniCLIonVPS/main/scripts/setup-vps.sh \
    -o /tmp/setup-vps.sh
cat /tmp/setup-vps.sh    # ← прочитай перед запуском
bash /tmp/setup-vps.sh
```

### 3. Если скрипт не сделал git clone (первый деплой)

```bash
git clone https://github.com/Demonhmr/GemoniCLIonVPS.git /opt/gemini-cli
cd /opt/gemini-cli
chown -R gemini-vps:gemini-vps /opt/gemini-cli
docker compose up -d --build
```

### 4. Подключись как gemini-vps и добавь SSH-ключ

```bash
# В консоли VPS-провайдера (если SSH по паролю уже отключён):
mkdir -p /home/gemini-vps/.ssh
echo "YOUR_PUBLIC_KEY" >> /home/gemini-vps/.ssh/authorized_keys
chmod 700 /home/gemini-vps/.ssh
chmod 600 /home/gemini-vps/.ssh/authorized_keys
chown -R gemini-vps:gemini-vps /home/gemini-vps/.ssh
```

---

## Использование

### Подключиться к VPS

```bash
ssh gemini-vps@YOUR_VPS_IP
cd /opt/gemini-cli
```

### Запустить интерактивный Gemini CLI

```bash
make gemini
```

> ⚠️ Первый запуск выведет URL для Google OAuth-авторизации.
> Открой ссылку в браузере → войди через Google → вернись в терминал.
> Токены сохранятся в volume и больше не потребуются при пересборке.

### Быстрый запрос без интерактивного режима

```bash
make ask Q="Напиши bash скрипт для бэкапа директории"
```

### Все доступные команды

```bash
make help
```

| Команда | Описание |
|---|---|
| `make gemini` | Интерактивный TUI Gemini CLI |
| `make ask Q="..."` | Одиночный запрос |
| `make attach` | Войти в tmux-сессию контейнера |
| `make shell` | Bash внутри контейнера |
| `make status` | Статус контейнера |
| `make logs` | Логи контейнера |
| `make update` | Пересобрать и перезапустить |
| `make down` | Остановить контейнер |

---

## Технические решения (lessons learned)

### PTY и интерактивный TUI

Gemini CLI использует библиотеку **Ink (React для терминала)**. Через цепочку SSH→`docker exec -it` TUI рендерится, но не принимает ввод.

**Решение:** `script -q -c "gemini" /dev/null` внутри `docker exec` создаёт нативный PTY, который корректно передаёт ввод в Ink. Именно это использует `make gemini`.

### Права на Docker volumes

Docker создаёт именованные volumes с владельцем `root`. Процесс в контейнере работает от `gemini:1001`.

**Решение:** `entrypoint.sh` запускается от root, исправляет права (`chown`), затем передаёт управление `gosu gemini`.

### Имя SSH-сервиса в Ubuntu

На Ubuntu 22.04+ сервис называется `ssh.service`, а не `sshd.service`.

**Решение:** скрипт определяет имя автоматически через `systemctl list-units`.

### machine-id внутри контейнера

Gemini CLI использует `libsecret` для хранения ключей. Без `/etc/machine-id` выводит предупреждение и падает в FileKeychain fallback.

**Решение:** `entrypoint.sh` генерирует `machine-id` при старте контейнера.

---

## Безопасность

- SSH: только ключевая аутентификация, root-логин отключён
- `fail2ban`: блокировка после 3 неудачных попыток на 1 час
- UFW: открыты только порты 22, 80, 443
- Контейнер: `cap_drop: ALL`, `no-new-privileges`, `mem_limit: 512m`
- `cap_add`: только `CHOWN`, `SETUID`, `SETGID` — нужны для entrypoint

---

## Обновление

```bash
cd /opt/gemini-cli
git pull
make update
```

OAuth-токены **не слетают** при обновлении — хранятся в volume `gemini-cli_gemini-config`.

---

## Откат к стабильной версии

```bash
cd /opt/gemini-cli
git checkout v1.0.0
make update
```

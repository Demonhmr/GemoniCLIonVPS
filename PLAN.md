# 🚀 Gemini CLI on VPS — Docker Deployment Plan
> **v2.0 — Security-hardened edition** | Проверен на технические и логические коллизии

## Утверждённые параметры

| Параметр | Значение |
|---|---|
| **Аутентификация** | OAuth через Google (`gemini login`) — токены в Docker volume |
| **Работа с файлами** | Да — `/workspace` как named volume |
| **Пользователи** | Один — одна tmux-сессия |
| **VPS** | Ubuntu, 1 GB RAM |

---

## 🏗️ Архитектура решения

```
[Клиент]
    │
    │  SSH (порт 22, только по ключу)
    │
[VPS Host — Ubuntu 22.04 LTS]
 ├── UFW: 22/tcp only
 ├── fail2ban (защита от брутфорса)
 ├── Docker Engine (rootless mode)
 └── [Container: gemini-cli-service]
          ├── Node.js 20-slim
          ├── @google/gemini-cli
          ├── tmux
          └── /workspace
               │
          [Volume: gemini-config] → ~/.config/gemini (OAuth токены)
          [Volume: workspace]     → /workspace (проекты)
```

### Схема доступа

```
ssh -i ~/.ssh/vps_key user@vps-ip  ← только по ключу, не по паролю
     │
     cd /opt/gemini-cli && make attach
     │
     docker exec -it gemini-cli-service tmux attach -t main
     │
     [tmux: Gemini CLI]   ← Ctrl+A, D чтобы отсоединиться
```

---

## ⚠️ Выявленные коллизии и исправления

### 🔴 Критические

**1. `setup-vps.sh` скачивает и исполняет скрипт через `curl | bash` — это RCE-риск**
> Если GitHub-аккаунт или CDN скомпрометированы, атакующий получает root.

```diff
- bash <(curl -fsSL https://raw.githubusercontent.com/.../setup-vps.sh)
+ # Безопасный вариант: скачать, проверить, потом запустить
+ curl -fsSL https://raw.githubusercontent.com/.../setup-vps.sh -o setup-vps.sh
+ cat setup-vps.sh   # вручную проверить содержимое!
+ bash setup-vps.sh
```

**2. `make login` вызывает `gemini auth login` — команды нет в Gemini CLI**
> Реальная команда инициализации: просто `gemini` при первом запуске (CLI сам предложит auth flow).
> Или настройка через `~/.config/gemini/` вручную.

```diff
- login:
-     docker exec -it gemini-cli-service gemini auth login
+ login:
+     @echo "=== First-time OAuth Setup ==="
+     @echo "Run: make attach → then type: gemini"
+     @echo "CLI will prompt you to open a browser URL for Google OAuth."
+     docker exec -it gemini-cli-service bash
```

**3. `deploy.resources.limits` в `docker-compose.yml v3.9` работает только в Swarm-режиме**
> В обычном `docker compose up` эти лимиты игнорируются — контейнер может съесть всю RAM.

```diff
- deploy:
-   resources:
-     limits:
-       memory: 512M
+ # Прямые ограничения (работают без Swarm)
+ mem_limit: 512m
+ mem_reservation: 128m
+ oom_kill_disable: false
```

---

### 🟡 Важные улучшения безопасности

**4. Нет hardening SSH на хосте VPS**
> В `setup-vps.sh` не настраивается `/etc/ssh/sshd_config`. Парольная аутентификация остаётся включённой.

Добавить в скрипт:
```bash
# Hardening SSH
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
echo "AllowUsers gemini-vps" >> /etc/ssh/sshd_config  # только один юзер
systemctl reload sshd
```

**5. Нет `fail2ban` — SSH открыт для брутфорса**
```bash
apt-get install -y fail2ban
systemctl enable fail2ban --now
```

**6. Контейнер запускается с полными capabilities Docker по умолчанию**
> Добавить явное ограничение:
```yaml
# в docker-compose.yml
security_opt:
  - no-new-privileges:true    # запрет эскалации привилегий
cap_drop:
  - ALL                       # убрать все Linux capabilities
cap_add:
  - CHOWN                     # только необходимые
  - SETUID
  - SETGID
```

**7. `CMD ["tail", "-f", "/dev/null"]` — неэлегантный способ держать контейнер живым**
> Лучше использовать `sleep infinity` — он не читает файл и потребляет меньше ресурсов.
```diff
- CMD ["tail", "-f", "/dev/null"]
+ CMD ["sleep", "infinity"]
```

---

### 🟢 Логические коллизии

**8. В схеме доступа используется `root@YOUR_VPS_IP`**
> Выше же запрещён `PermitRootLogin`. Противоречие.
```diff
- ssh root@YOUR_VPS_IP
+ ssh gemini-vps@YOUR_VPS_IP  # непривилегированный пользователь хоста
```

**9. `make update` вызывает `docker compose pull` перед `--build`**
> `pull` тянет образы из registry (их там нет — образ собирается локально через `build:`). Команда упадёт с ошибкой.
```diff
- update:
-     docker compose pull && docker compose up -d --build
+ update:
+     docker compose up -d --build --force-recreate
```

---

## 📁 Структура репозитория

```
GemoniCLIonVPS/
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── .gitignore
├── .tmux.conf
├── Makefile
├── README.md
└── scripts/
    └── setup-vps.sh
```

---

## 📄 Финальные конфигурации (после исправлений)

### `Dockerfile`

```dockerfile
FROM node:20-slim

LABEL description="Gemini CLI — hardened container"

RUN apt-get update && apt-get install -y --no-install-recommends \
        tmux git curl bash jq less ca-certificates \
    && npm install -g @google/gemini-cli \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Непривилегированный пользователь с фиксированным UID
RUN useradd -m -u 1001 -s /bin/bash gemini

COPY --chown=gemini:gemini .tmux.conf /home/gemini/.tmux.conf

RUN mkdir -p /workspace && chown gemini:gemini /workspace

USER gemini
WORKDIR /workspace

# sleep infinity — меньше ресурсов, чем tail -f /dev/null
CMD ["sleep", "infinity"]
```

---

### `docker-compose.yml`

```yaml
version: '3.9'

# Access: SSH → VPS host → docker exec → tmux
# Auth:   Google OAuth — tokens in named volume

services:
  gemini-cli:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: gemini-cli-service
    restart: unless-stopped

    # Явные лимиты RAM (работают без Swarm)
    mem_limit: 512m
    mem_reservation: 128m
    oom_kill_disable: false

    # Security hardening
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETUID
      - SETGID

    # Нет открытых портов — доступ только через docker exec
    volumes:
      - gemini-config:/home/gemini/.config/gemini
      - workspace:/workspace

    environment:
      - TERM=xterm-256color
      - LANG=C.UTF-8

volumes:
  gemini-config:
    driver: local
  workspace:
    driver: local
```

---

### `Makefile`

```makefile
.PHONY: up down attach shell logs update status version

# Запуск (пересборка образа)
up:
	docker compose up -d --build

# Остановка
down:
	docker compose down

# Подключиться к tmux-сессии (основная команда)
attach:
	docker exec -it gemini-cli-service tmux attach -t main 2>/dev/null || \
	docker exec -it gemini-cli-service tmux new-session -s main -n gemini

# Оболочка bash внутри контейнера (для диагностики)
shell:
	docker exec -it gemini-cli-service bash

# Запустить Gemini CLI напрямую (без tmux)
gemini:
	docker exec -it gemini-cli-service gemini

# Логи
logs:
	docker compose logs -f

# Обновление ТОЛЬКО через --build (pull не нужен — образ локальный)
update:
	docker compose up -d --build --force-recreate

# Статус
status:
	docker compose ps

# Версия
version:
	docker exec gemini-cli-service gemini --version
```

---

### `scripts/setup-vps.sh`

```bash
#!/bin/bash
# =============================================================================
# VPS setup: Docker + UFW + fail2ban + SSH hardening
# Run as root. Read this script before running!
# =============================================================================
set -euo pipefail

DEPLOY_USER="gemini-vps"
REPO_DIR="/opt/gemini-cli"
REPO_URL="https://github.com/YOUR_USERNAME/GemoniCLIonVPS.git"  # ← заменить

# ---------------------------------------------------------------------------
echo "=== [1/6] Обновление системы ==="
apt-get update && apt-get upgrade -y

# ---------------------------------------------------------------------------
echo "=== [2/6] Установка Docker ==="
curl -fsSL https://get.docker.com | sh
systemctl enable docker --now

# ---------------------------------------------------------------------------
echo "=== [3/6] Установка fail2ban ==="
apt-get install -y ufw fail2ban
systemctl enable fail2ban --now

# ---------------------------------------------------------------------------
echo "=== [4/6] Создание непривилегированного пользователя ==="
if ! id "$DEPLOY_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$DEPLOY_USER"
    usermod -aG docker "$DEPLOY_USER"
fi

# ---------------------------------------------------------------------------
echo "=== [5/6] Hardening SSH ==="
# Перед этим шагом убедитесь, что SSH-ключ добавлен в authorized_keys!
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
grep -qxF "AllowUsers $DEPLOY_USER" /etc/ssh/sshd_config || \
    echo "AllowUsers $DEPLOY_USER" >> /etc/ssh/sshd_config
systemctl reload sshd
echo "⚠️  SSH: парольный вход ОТКЛЮЧЁН. Подключение только по ключу!"

# ---------------------------------------------------------------------------
echo "=== [5.5/6] Настройка UFW Firewall ==="
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH only'
ufw --force enable
echo "Открыт только порт 22. Остальные закрыты."

# ---------------------------------------------------------------------------
echo "=== [6/6] Клонирование и запуск ==="
git clone "$REPO_URL" "$REPO_DIR"
chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$REPO_DIR"
cd "$REPO_DIR"
docker compose up -d --build

echo ""
echo "✅ VPS готов!"
echo ""
echo "⚠️  СЛЕДУЮЩИЙ ШАГ — первичная авторизация Gemini CLI:"
echo "  ssh $DEPLOY_USER@$(hostname -I | awk '{print $1}')"
echo "  cd $REPO_DIR && make attach"
echo "  # Внутри tmux запустите: gemini"
echo "  # CLI предложит перейти по ссылке для Google OAuth"
```

---

## 🔒 Итоговая таблица угроз и защит

| # | Угроза | Уровень | Защита |
|---|---|---|---|
| 1 | Брутфорс SSH | 🔴 Критический | `fail2ban` + отключение парольного входа |
| 2 | Вход от root по SSH | 🔴 Критический | `PermitRootLogin no` в sshd_config |
| 3 | Эскалация привилегий в контейнере | 🔴 Критический | `no-new-privileges:true` + `cap_drop: ALL` |
| 4 | Компрометация OAuth токенов | 🟠 Высокий | Named volume (не в образе, не в репо) |
| 5 | Утечка секретов в Git | 🟠 Высокий | `.gitignore` + `.env` вне репо |
| 6 | Побег из контейнера | 🟠 Высокий | Нет `--privileged`, нет `docker.sock` |
| 7 | Открытые сетевые порты | 🟠 Высокий | UFW: только 22/tcp; контейнер без портов |
| 8 | Устаревшие зависимости | 🟡 Средний | `make update` → `--build --force-recreate` |
| 9 | OOM — контейнер убивает VPS | 🟡 Средний | `mem_limit: 512m` (прямые лимиты, не Swarm) |
| 10 | RCE через curl\|bash | 🟡 Средний | Скрипт скачивается и проверяется вручную |

---

## 🚀 Процесс развёртывания (финальный)

```bash
# ШАГ 0: Добавить SSH ключ ЗАРАНЕЕ (до hardening!)
ssh-copy-id -i ~/.ssh/vps_key.pub root@YOUR_VPS_IP

# ШАГ 1: Подключиться и скачать скрипт
ssh root@YOUR_VPS_IP
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/GemoniCLIonVPS/main/scripts/setup-vps.sh \
    -o /tmp/setup-vps.sh
cat /tmp/setup-vps.sh   # ← обязательно проверить!
bash /tmp/setup-vps.sh

# ШАГ 2: Подключиться уже как непривилегированный пользователь
ssh -i ~/.ssh/vps_key gemini-vps@YOUR_VPS_IP

# ШАГ 3: Первичная авторизация Google OAuth
cd /opt/gemini-cli
make attach
# Внутри tmux: gemini → открыть ссылку в браузере → авторизоваться
# Токены сохранятся в volume 'gemini-config'

# ШАГ 4: Отсоединиться и переподключаться когда угодно
# Ctrl+A, D  ← выйти из tmux (сессия живёт!)
make attach  ← вернуться
```

---

## ✅ Чеклист проверки после deploy

```bash
make status          # контейнер Up?
make version         # gemini доступен?
docker exec gemini-cli-service id   # убедиться что NOT root
docker exec gemini-cli-service cat /proc/1/status | grep Cap  # capabilities срезаны?
make attach          # tmux открывается?
# Reboot VPS → контейнер автоматически поднялся?
ssh root@vps → должен отказать  # PermitRootLogin работает?
```

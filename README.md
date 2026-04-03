# Gemini CLI on VPS

> Запуск [Gemini CLI](https://github.com/google-gemini/gemini-cli) в изолированном Docker-контейнере на VPS.  
> Доступ через SSH → `docker exec` → tmux. Без открытых портов. Без root.

---

## Архитектура

```
[Клиент]
    │  SSH (порт 22, только по ключу)
[VPS: Ubuntu 22.04, 1GB RAM]
    │  UFW + fail2ban
[Docker Container: gemini-cli-service]
    │  node:20-slim + @google/gemini-cli + tmux
    │  cap_drop: ALL │ no-new-privileges │ mem_limit: 512m
[Volumes]
    gemini-config → OAuth токены
    workspace     → рабочие файлы
```

---

## Быстрый старт

### 1. Подготовка SSH-ключа (на локальной машине)

```bash
# Сгенерировать ключ если нет
ssh-keygen -t ed25519 -C "gemini-vps" -f ~/.ssh/vps_key

# Скопировать публичный ключ на VPS (пока ещё работает вход по паролю)
ssh-copy-id -i ~/.ssh/vps_key.pub root@YOUR_VPS_IP
```

### 2. Настройка VPS

```bash
ssh root@YOUR_VPS_IP

# Скачать скрипт, проверить, запустить
curl -fsSL https://raw.githubusercontent.com/Demonhmr/GemoniCLIonVPS/main/scripts/setup-vps.sh \
    -o /tmp/setup-vps.sh
cat /tmp/setup-vps.sh    # ← обязательно прочитать перед запуском
bash /tmp/setup-vps.sh
```

Скрипт сделает:
- ✅ Обновит систему
- ✅ Установит Docker
- ✅ Установит `fail2ban`
- ✅ Создаст пользователя `gemini-vps`, скопирует SSH-ключ
- ✅ Отключит парольный вход и вход от root
- ✅ Настроит UFW (только порт 22)
- ✅ Запустит контейнер

### 3. Первичная OAuth авторизация (один раз)

```bash
# Подключиться уже как непривилегированный пользователь
ssh -i ~/.ssh/vps_key gemini-vps@YOUR_VPS_IP

cd /opt/gemini-cli
make attach          # открывает tmux-сессию

# Внутри tmux:
gemini               # CLI выведет ссылку для Google OAuth
# Открыть ссылку в браузере → авторизоваться → токены сохранятся в volume
```

### 4. Ежедневная работа

```bash
ssh -i ~/.ssh/vps_key gemini-vps@YOUR_VPS_IP
cd /opt/gemini-cli
make attach
```

| Действие | Команда |
|---|---|
| Подключиться к сессии | `make attach` |
| Отсоединиться (сессия живёт) | `Ctrl+A, D` |
| Запустить Gemini напрямую | `make gemini` |
| Открыть bash в контейнере | `make shell` |
| Посмотреть логи | `make logs` |
| Статус контейнера | `make status` |
| Обновить Gemini CLI | `make update` |

---

## Структура проекта

```
.
├── Dockerfile              # node:20-slim + gemini-cli + tmux, user UID 1001
├── docker-compose.yml      # mem_limit, cap_drop, security_opt, named volumes
├── .tmux.conf              # mouse, Ctrl+A prefix, Alt+Arrows navigation
├── .env.example            # шаблон (OAuth не требует API ключа)
├── .gitignore
├── Makefile                # make help — список команд
├── README.md
└── scripts/
    └── setup-vps.sh        # полная автоматизация настройки VPS
```

---

## Безопасность

| Угроза | Защита |
|---|---|
| Брутфорс SSH | `fail2ban`, `MaxAuthTries 3` |
| Вход от root | `PermitRootLogin no` |
| Парольный вход | `PasswordAuthentication no` |
| Эскалация привилегий | `no-new-privileges:true`, `cap_drop: ALL` |
| Утечка OAuth токенов | Named volume (не в образе, не в репо) |
| Открытые порты | UFW: только 22; контейнер без публичных портов |
| OOM контейнера | `mem_limit: 512m` (прямой синтаксис, без Swarm) |

---

## tmux: горячие клавиши

| Действие | Комбинация |
|---|---|
| Prefix | `Ctrl+A` |
| Отсоединиться | `Ctrl+A, D` |
| Новая панель (вертикально) | `Ctrl+A, \|` |
| Новая панель (горизонтально) | `Ctrl+A, -` |
| Переключение панелей | `Alt+Стрелки` |
| Перезагрузить конфиг | `Ctrl+A, R` |

---

## Обновление Gemini CLI

```bash
ssh -i ~/.ssh/vps_key gemini-vps@YOUR_VPS_IP
cd /opt/gemini-cli
make update
```

Пересобирает образ с последней версией `@google/gemini-cli`. OAuth токены и файлы в `/workspace` сохраняются (они в named volumes).

---

## Решение проблем

**Контейнер не запускается**
```bash
make logs
```

**OAuth слетел (редко)**
```bash
make attach
# Внутри tmux: gemini  → повторить авторизацию
```

**Нет доступа по SSH после setup**
```bash
# Проверить что ключ был скопирован ДО запуска скрипта
# Подключиться через консоль VPS-провайдера и проверить /etc/ssh/sshd_config
```

**Посмотреть capabilities контейнера**
```bash
docker exec gemini-cli-service cat /proc/1/status | grep -i cap
```

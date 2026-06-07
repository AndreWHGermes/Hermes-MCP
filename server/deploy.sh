#!/bin/bash
# ───────────────────────────────────────────────────────────────
# Деплой Hermes Voice API на сервер gptconnect.tw1.ru
# ───────────────────────────────────────────────────────────────
# Требования:
#   1. SSH-доступ к серверу с паролем или ключом
#   2. Права на запись в /var/www/html/ или другой DocumentRoot
#
# Использование:
#   ./deploy.sh [server_path]
#
# Пример:
#   ./deploy.sh /var/www/html/
# ───────────────────────────────────────────────────────────────

set -e

SERVER="root@91.132.57.16"
PORT="22"
REMOTE_PATH="${1:-/var/www/html/}"
LOCAL_FILE="$(dirname "$0")/hermes-api.php"

if [ ! -f "$LOCAL_FILE" ]; then
    echo "❌ Файл $LOCAL_FILE не найден"
    echo "   Запускай из папки server/"
    exit 1
fi

echo "🚀 Деплой Hermes Voice API на $SERVER:$REMOTE_PATH"
echo "   Файл: $LOCAL_FILE"
echo ""

# Копируем PHP-скрипт на сервер
echo "📤 Копирую PHP-скрипт..."
scp -P "$PORT" "$LOCAL_FILE" "$SERVER:${REMOTE_PATH}hermes-api.php"

if [ $? -eq 0 ]; then
    echo "✅ PHP-скрипт скопирован"
else
    echo "❌ Ошибка копирования"
    exit 1
fi

# Устанавливаем права
echo "🔧 Устанавливаю права..."
ssh -p "$PORT" "$SERVER" "chmod 755 ${REMOTE_PATH}hermes-api.php"

# Проверяем работу
echo ""
echo "🔍 Проверяю endpoint..."
sleep 1
curl -s "https://gptconnect.tw1.ru/hermes-api/ping" | python3 -m json.tool 2>/dev/null || echo "   (проверь в браузере https://gptconnect.tw1.ru/hermes-api/ping)"

echo ""
echo "✅ Деплой завершён!"
echo "   Endpoint: https://gptconnect.tw1.ru/hermes-api/"
echo "   Ping:     https://gptconnect.tw1.ru/hermes-api/ping"

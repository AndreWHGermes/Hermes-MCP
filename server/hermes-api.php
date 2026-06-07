<?php
/**
 * Hermes Voice API — Прокси-сервер для голосового приложения
 * 
 * Заменяет прямую связь с Telegram Bot API из APK.
 * Токен бота хранится ТОЛЬКО на сервере.
 * 
 * Эндпоинты:
 *   POST /hermes-api/voice     — принять голосовое (WAV/multipart) и отправить в Telegram
 *   POST /hermes-api/text      — принять текст и отправить в Telegram
 *   POST /hermes-api/respond   — ответить голосовым OGG (сервер → app)
 *   GET  /hermes-api/respond   — получить последний голосовой ответ (poll)
 *   GET  /hermes-api/ping      — проверка здоровья
 *   GET  /hermes-api/status    — статус и статистика
 */

// ── Конфигурация ──────────────────────────────────────────────
define('BOT_TOKEN', '8751647587:***');
define('CHAT_ID', '399924132');
define('TELEGRAM_API', 'https://api.telegram.org/bot' . BOT_TOKEN);
define('TEMP_DIR', __DIR__ . '/hermes-temp');
define('RESPONSE_DIR', __DIR__ . '/hermes-responses');
define('MAX_FILE_SIZE', 50 * 1024 * 1024); // 50 MB
define('ALLOWED_ORIGINS', '*');

// ── CORS ───────────────────────────────────────────────────────
header('Access-Control-Allow-Origin: ' . ALLOWED_ORIGINS);
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, multipart/form-data');
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

// ── Создание директорий ───────────────────────────────────────
if (!is_dir(TEMP_DIR)) mkdir(TEMP_DIR, 0755, true);
if (!is_dir(RESPONSE_DIR)) mkdir(RESPONSE_DIR, 0755, true);

// ── Логирование ───────────────────────────────────────────────
function log_msg(string $msg): void {
    $logFile = __DIR__ . '/hermes-api.log';
    $line = date('Y-m-d H:i:s') . ' | ' . $msg . PHP_EOL;
    file_put_contents($logFile, $line, FILE_APPEND | LOCK_EX);
}

// ── Ответ JSON ────────────────────────────────────────────────
function json_response(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function error(string $msg, int $code = 400): void {
    log_msg("ERROR [$code]: $msg");
    json_response(['ok' => false, 'error' => $msg], $code);
}

// ── Отправка в Telegram ───────────────────────────────────────
function send_to_telegram(string $endpoint, array $fields, array $file = []): array {
    $url = TELEGRAM_API . '/' . $endpoint;
    
    if (!empty($file)) {
        // Multipart-запрос с файлом
        $multipart = [];
        foreach ($fields as $key => $val) {
            $multipart[] = ['name' => $key, 'contents' => $val];
        }
        $multipart[] = [
            'name' => $file['field'],
            'contents' => $file['contents'],
            'filename' => $file['filename'],
        ];

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $multipart,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 35,
            CURLOPT_CONNECTTIMEOUT => 10,
        ]);
    } else {
        // JSON-запрос
        $json = json_encode($fields, JSON_UNESCAPED_UNICODE);
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $json,
            CURLOPT_HTTPHEADER => ['Content-Type: application/json; charset=utf-8'],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 15,
            CURLOPT_CONNECTTIMEOUT => 10,
        ]);
    }

    $result = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $errno = curl_errno($ch);
    $error = curl_error($ch);
    curl_close($ch);

    if ($errno) {
        log_msg("CURL error $errno: $error");
        return ['ok' => false, 'error' => "CURL: $error", 'http_code' => 0];
    }

    $data = json_decode($result, true);
    
    if ($httpCode !== 200) {
        log_msg("Telegram HTTP $httpCode: " . substr($result, 0, 500));
        return ['ok' => false, 'error' => "Telegram HTTP $httpCode", 'http_code' => $httpCode, 'body' => $result];
    }

    if (!($data['ok'] ?? false)) {
        log_msg("Telegram ok=false: " . substr($result, 0, 500));
        return ['ok' => false, 'error' => 'Telegram API error', 'body' => $result];
    }

    return ['ok' => true, 'result' => $data['result'], 'http_code' => $httpCode];
}

// ── Отправка голосового сообщения в Telegram ──────────────────
function send_voice_to_telegram(string $filePath, string $filename): array {
    $ext = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
    $isVoice = in_array($ext, ['ogg', 'oga']);
    $endpoint = $isVoice ? 'sendVoice' : 'sendAudio';
    $fieldName = $isVoice ? 'voice' : 'audio';

    $fields = ['chat_id' => CHAT_ID];
    $file = [
        'field' => $fieldName,
        'contents' => file_get_contents($filePath),
        'filename' => $filename,
    ];

    return send_to_telegram($endpoint, $fields, $file);
}

// ── Отправка текста в Telegram ────────────────────────────────
function send_text_to_telegram(string $text): array {
    return send_to_telegram('sendMessage', [
        'chat_id' => CHAT_ID,
        'text' => $text,
    ]);
}

// ── Получение последних голосовых ответов от Hermes через Telegram ──
function poll_telegram_responses(int $limit = 5): array {
    // Получаем последние сообщения из чата
    $result = send_to_telegram('getUpdates', [
        'chat_id' => CHAT_ID,
        'timeout' => 0,
        'limit' => $limit,
        'allowed_updates' => ['message'],
    ]);

    if (!$result['ok']) {
        return ['ok' => false, 'error' => $result['error'] ?? 'Poll failed'];
    }

    $updates = $result['result'] ?? [];
    $voiceMessages = [];

    foreach ($updates as $update) {
        $msg = $update['message'] ?? null;
        if (!$msg) continue;
        
        $msgChatId = $msg['chat']['id'] ?? 0;
        if ((string)$msgChatId !== CHAT_ID) continue;

        // Ищем голосовые сообщения (ответы от Hermes)
        if (isset($msg['voice'])) {
            $fileId = $msg['voice']['file_id'];
            $duration = $msg['voice']['duration'] ?? 0;
            
            // Получаем file_path
            $fileInfo = send_to_telegram('getFile', [
                'file_id' => $fileId,
            ]);

            $downloadUrl = null;
            if ($fileInfo['ok']) {
                $filePath = $fileInfo['result']['file_path'] ?? null;
                if ($filePath) {
                    $downloadUrl = 'https://api.telegram.org/file/bot' . BOT_TOKEN . '/' . $filePath;
                }
            }

            $voiceMessages[] = [
                'type' => 'voice',
                'file_id' => $fileId,
                'duration' => $duration,
                'url' => $downloadUrl,
                'message_id' => $msg['message_id'],
            ];
        }

        // Текстовые ответы
        if (isset($msg['text'])) {
            $voiceMessages[] = [
                'type' => 'text',
                'text' => $msg['text'],
                'message_id' => $msg['message_id'],
            ];
        }
    }

    return [
        'ok' => true,
        'messages' => $voiceMessages,
    ];
}

// ── Маршрутизация ─────────────────────────────────────────────
$requestUri = $_SERVER['REQUEST_URI'] ?? '';
$parsedUrl = parse_url($requestUri);
$path = rtrim($parsedUrl['path'] ?? '', '/');

log_msg("REQUEST: $requestUri");

try {
    switch (true) {
        // ── POST /voice — принять голосовое ──────────────────────
        case $path === '/hermes-api/voice' && $_SERVER['REQUEST_METHOD'] === 'POST':
            if (empty($_FILES) || empty($_FILES['voice'])) {
                // Try reading raw body as multipart
                $raw = file_get_contents('php://input');
                if (empty($raw)) {
                    error('No file uploaded. Send as multipart/form-data with field "voice"');
                }
                // Сохраняем сырые данные как WAV
                $tmpPath = TEMP_DIR . '/voice_' . time() . '_' . bin2hex(random_bytes(4)) . '.wav';
                file_put_contents($tmpPath, $raw);
                
                $result = send_voice_to_telegram($tmpPath, 'voice.wav');
                $msgId = $result['ok'] ? ($result['result']['message_id'] ?? null) : null;
                
                unlink($tmpPath);
                
                if ($result['ok']) {
                    json_response([
                        'ok' => true,
                        'message' => 'Voice sent to Telegram',
                        'message_id' => $msgId,
                    ]);
                } else {
                    error($result['error'] ?? 'Failed to send', 502);
                }
                break;
            }

            $file = $_FILES['voice'];
            if ($file['error'] !== UPLOAD_ERR_OK) {
                error('Upload error code: ' . $file['error']);
            }
            if ($file['size'] > MAX_FILE_SIZE) {
                error('File too large: ' . $file['size'] . ' bytes (max ' . MAX_FILE_SIZE . ')');
            }

            $tmpPath = $file['tmp_name'];
            $origName = $file['name'] ?: 'voice.wav';

            $result = send_voice_to_telegram($tmpPath, $origName);
            $msgId = $result['ok'] ? ($result['result']['message_id'] ?? null) : null;

            if ($result['ok']) {
                json_response([
                    'ok' => true,
                    'message' => 'Voice sent to Telegram',
                    'message_id' => $msgId,
                ]);
            } else {
                error($result['error'] ?? 'Failed to send', 502);
            }
            break;

        // ── POST /text — принять текст ───────────────────────────
        case $path === '/hermes-api/text' && $_SERVER['REQUEST_METHOD'] === 'POST':
            $input = json_decode(file_get_contents('php://input'), true);
            if (!$input || empty($input['text'])) {
                error('Missing "text" field in JSON body');
            }

            $result = send_text_to_telegram($input['text']);
            if ($result['ok']) {
                json_response([
                    'ok' => true,
                    'message' => 'Text sent to Telegram',
                ]);
            } else {
                error($result['error'] ?? 'Failed to send text', 502);
            }
            break;

        // ── POST /respond — ответить голосовым (от Hermes через сервер) ──
        case $path === '/hermes-api/respond' && $_SERVER['REQUEST_METHOD'] === 'POST':
            // Сервер получает OGG-файл и сохраняет для приложения
            $raw = file_get_contents('php://input');
            if (empty($raw)) {
                error('No audio data received');
            }

            $responseId = time() . '_' . bin2hex(random_bytes(4));
            $outPath = RESPONSE_DIR . '/response_' . $responseId . '.ogg';
            file_put_contents($outPath, $raw);

            // Чистим старые ответы (старше 5 минут)
            $files = glob(RESPONSE_DIR . '/response_*.ogg');
            $cutoff = time() - 300;
            foreach ($files as $f) {
                if (filemtime($f) < $cutoff) {
                    unlink($f);
                }
            }

            json_response([
                'ok' => true,
                'response_id' => $responseId,
                'url' => '/hermes-api/respond?id=' . $responseId,
            ]);
            break;

        // ── GET /respond?id=X — получить голосовой ответ ─────────
        case $path === '/hermes-api/respond' && $_SERVER['REQUEST_METHOD'] === 'GET':
            $reqId = $_GET['id'] ?? null;
            if ($reqId) {
                $filePath = RESPONSE_DIR . '/response_' . preg_replace('/[^a-zA-Z0-9_]/', '', $reqId) . '.ogg';
                if (file_exists($filePath)) {
                    header('Content-Type: audio/ogg');
                    header('Content-Length: ' . filesize($filePath));
                    readfile($filePath);
                    exit;
                }
                error('Response not found', 404);
            }

            // Без id — возвращаем список доступных ответов или последний
            $files = glob(RESPONSE_DIR . '/response_*.ogg');
            if (empty($files)) {
                json_response([
                    'ok' => true,
                    'message' => 'No responses available',
                    'count' => 0,
                    'responses' => [],
                ]);
            }

            // Сортируем по времени (свежие первые)
            usort($files, function($a, $b) {
                return filemtime($b) - filemtime($a);
            });

            $responses = [];
            foreach ($files as $f) {
                $id = str_replace(['response_', '.ogg'], '', basename($f));
                $responses[] = [
                    'id' => $id,
                    'url' => '/hermes-api/respond?id=' . $id,
                    'size' => filesize($f),
                    'created' => date('c', filemtime($f)),
                ];
            }

            json_response([
                'ok' => true,
                'count' => count($responses),
                'responses' => $responses,
            ]);
            break;

        // ── GET /poll — получить обновления из Telegram ───────────
        case $path === '/hermes-api/poll' && $_SERVER['REQUEST_METHOD'] === 'GET':
            $result = poll_telegram_responses();
            json_response($result);
            break;

        // ── GET /ping — проверка здоровья ────────────────────────
        case $path === '/hermes-api/ping':
            $telegramOk = false;
            $test = send_to_telegram('getMe', []);
            if ($test['ok']) {
                $telegramOk = true;
            }

            json_response([
                'ok' => true,
                'service' => 'Hermes Voice API',
                'version' => '7.0.0',
                'telegram' => $telegramOk ? 'connected' : 'disconnected',
                'time' => date('c'),
                'php_version' => phpversion(),
            ]);
            break;

        // ── GET /status — статистика ─────────────────────────────
        case $path === '/hermes-api/status':
            $logSize = file_exists(__DIR__ . '/hermes-api.log') 
                ? filesize(__DIR__ . '/hermes-api.log') : 0;
            $responseCount = count(glob(RESPONSE_DIR . '/response_*.ogg'));
            $diskFree = disk_free_space(__DIR__);
            $diskTotal = disk_total_space(__DIR__);

            json_response([
                'ok' => true,
                'uptime' => filemtime(__FILE__) ? (time() - filemtime(__FILE__)) . 's' : 'unknown',
                'responses_stored' => $responseCount,
                'log_size_bytes' => $logSize,
                'disk_free_gb' => round($diskFree / 1073741824, 2),
                'disk_total_gb' => round($diskTotal / 1073741824, 2),
            ]);
            break;

        // ── GET / — корень API ───────────────────────────────────
        case $path === '/hermes-api' || $path === '':
            json_response([
                'ok' => true,
                'service' => 'Hermes Voice API',
                'endpoints' => [
                    'POST /hermes-api/voice' => 'Send voice (multipart/form-data, field: "voice")',
                    'POST /hermes-api/text' => 'Send text (JSON: {"text": "..."})',
                    'POST /hermes-api/respond' => 'Upload response audio (raw OGG body)',
                    'GET /hermes-api/respond' => 'Get response audio',
                    'GET /hermes-api/poll' => 'Poll new messages from Telegram',
                    'GET /hermes-api/ping' => 'Health check',
                    'GET /hermes-api/status' => 'Server status',
                ],
            ]);
            break;

        default:
            error('Not found: ' . $requestUri, 404);
    }
} catch (Throwable $e) {
    log_msg("EXCEPTION: " . $e->getMessage() . " in " . $e->getFile() . ":" . $e->getLine());
    error('Internal server error: ' . $e->getMessage(), 500);
}

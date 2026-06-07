#!/usr/bin/env python3
"""
Hermes Voice — Backend Proxy v3.0
Запуск: uvicorn proxy:app --host 0.0.0.0 --port 8765

Токен бота хранится ТОЛЬКО на сервере в .env
Приложение НЕ ЗНАЕТ токен.

Установка зависимостей:
  pip install fastapi uvicorn python-multipart aiohttp python-dotenv
"""

import asyncio
import logging
import os
from collections import deque
from pathlib import Path
from typing import Optional

import aiohttp
from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel

load_dotenv()

# ── Конфиг ────────────────────────────────────────────────────
BOT_TOKEN = os.getenv("BOT_TOKEN")
if not BOT_TOKEN:
    raise RuntimeError(
        "Нет BOT_TOKEN в .env! "
        "Создай .env с BOT_TOKEN=8887199277:***"
    )

TELEGRAM_API = f"https://api.telegram.org/bot{BOT_TOKEN}"
ALLOWED_CHAT_IDS = set(os.getenv("ALLOWED_CHAT_IDS", "399924132").split(","))

# Буфер последних обновлений
_updates_buffer: deque = deque(maxlen=100)
_last_update_id = 0

logging.basicConfig(level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("hermes-proxy")

app = FastAPI(title="Hermes Voice Proxy", version="3.0.0")


# ── Telegram Polling (фоновая задача) ─────────────────────────
async def telegram_poller():
    global _last_update_id

    async with aiohttp.ClientSession() as session:
        while True:
            try:
                url = (
                    f"{TELEGRAM_API}/getUpdates"
                    f"?offset={_last_update_id}"
                    f"&timeout=25"
                    f"&allowed_updates=%5B%22message%22%5D"
                )
                async with session.get(
                    url, timeout=aiohttp.ClientTimeout(total=35)
                ) as resp:
                    if resp.status == 409:
                        log.warning("409 Conflict — другой клиент!")
                        await asyncio.sleep(30)
                        continue

                    if resp.status != 200:
                        log.warning(f"Telegram HTTP {resp.status}")
                        await asyncio.sleep(10)
                        continue

                    data = await resp.json()
                    if not data.get("ok"):
                        log.error(f"Telegram ok=false: {data}")
                        await asyncio.sleep(5)
                        continue

                    for update in data.get("result", []):
                        _last_update_id = update["update_id"] + 1

                        msg = update.get("message", {})
                        chat_id = str(msg.get("chat", {}).get("id", ""))

                        if chat_id not in ALLOWED_CHAT_IDS:
                            continue

                        processed = {"update_id": update["update_id"]}

                        if voice := msg.get("voice"):
                            file_url = await get_file_url(session, voice["file_id"])
                            if file_url:
                                processed["voice_url"] = file_url

                        elif audio := msg.get("audio"):
                            file_url = await get_file_url(session, audio["file_id"])
                            if file_url:
                                processed["voice_url"] = file_url

                        elif text := msg.get("text"):
                            processed["text"] = text

                        if len(processed) > 1:
                            _updates_buffer.append(processed)
                            log.info(f"Новое от {chat_id}: {list(processed.keys())}")

            except asyncio.TimeoutError:
                pass  # нормально для long polling
            except Exception as e:
                log.error(f"Polling error: {e}")
                await asyncio.sleep(5)


async def get_file_url(session, file_id: str) -> Optional[str]:
    try:
        async with session.get(
            f"{TELEGRAM_API}/getFile?file_id={file_id}",
            timeout=aiohttp.ClientTimeout(total=10)
        ) as resp:
            data = await resp.json()
            if data.get("ok"):
                fp = data["result"]["file_path"]
                return f"https://api.telegram.org/file/bot{BOT_TOKEN}/{fp}"
    except Exception as e:
        log.error(f"getFile error: {e}")
    return None


@app.on_event("startup")
async def startup():
    asyncio.create_task(telegram_poller())
    log.info("Hermes Proxy запущен. Telegram polling активен.")


# ── Endpoints ─────────────────────────────────────────────────

@app.get("/api/get_updates")
async def get_updates(offset: int = 0):
    """Приложение забирает новые сообщения через прокси."""
    result = [u for u in _updates_buffer if u["update_id"] >= offset]
    return {"ok": True, "updates": result}


@app.post("/api/send_voice")
async def send_voice(
    chat_id: str = Form(...),
    voice: UploadFile = File(...)
):
    """WAV от приложения → Telegram Bot API."""
    if chat_id not in ALLOWED_CHAT_IDS:
        raise HTTPException(status_code=403, detail="Forbidden chat_id")

    audio_bytes = await voice.read()

    async with aiohttp.ClientSession() as session:
        form = aiohttp.FormData()
        form.add_field("chat_id", chat_id)
        form.add_field(
            "voice",
            audio_bytes,
            filename="voice.ogg",
            content_type="audio/ogg"
        )

        async with session.post(
            f"{TELEGRAM_API}/sendVoice",
            data=form,
            timeout=aiohttp.ClientTimeout(total=30)
        ) as resp:
            result = await resp.json()
            if result.get("ok"):
                log.info(f"Voice sent ({len(audio_bytes)} bytes)")
                return {"ok": True}
            else:
                log.error(f"sendVoice failed: {result}")
                return await _send_as_document(session, chat_id, audio_bytes)


async def _send_as_document(session, chat_id: str, audio_bytes: bytes):
    form = aiohttp.FormData()
    form.add_field("chat_id", chat_id)
    form.add_field(
        "document", audio_bytes, filename="voice.wav",
        content_type="audio/wav"
    )
    async with session.post(
        f"{TELEGRAM_API}/sendDocument", data=form,
        timeout=aiohttp.ClientTimeout(total=30)
    ) as resp:
        result = await resp.json()
        return {"ok": result.get("ok", False)}


class TextMessage(BaseModel):
    chat_id: str
    text: str


@app.post("/api/send_text")
async def send_text(msg: TextMessage):
    if msg.chat_id not in ALLOWED_CHAT_IDS:
        raise HTTPException(status_code=403, detail="Forbidden chat_id")

    async with aiohttp.ClientSession() as session:
        async with session.post(
            f"{TELEGRAM_API}/sendMessage",
            json={"chat_id": msg.chat_id, "text": msg.text},
            timeout=aiohttp.ClientTimeout(total=10)
        ) as resp:
            result = await resp.json()
            return {"ok": result.get("ok", False)}


@app.get("/health")
async def health():
    return {
        "ok": True,
        "buffered_updates": len(_updates_buffer),
        "last_update_id": _last_update_id
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("proxy:app", host="0.0.0.0", port=8765, reload=False)

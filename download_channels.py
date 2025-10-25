#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import asyncio
import os
import re
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import yaml
from telethon import TelegramClient
from telethon.errors import ChannelPrivateError, UsernameInvalidError
from telethon.tl.functions.channels import GetFullChannelRequest
from telethon.tl.types import MessageService

CONFIG_FILE = "config.yaml"

def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)  # безопасный парсинг
    # Значения по умолчанию
    cfg.setdefault("output", {})
    out = cfg["output"]
    out.setdefault("dir", "channels")
    out.setdefault("timezone", "UTC")
    out.setdefault("date_format", "%Y-%m-%d %H:%M")
    out.setdefault("include_service_messages", False)
    out.setdefault("reverse_order", False)
    out.setdefault("link_to_messages", True)
    cfg.setdefault("channels", [])
    return cfg

def ensure_dir(path: str):
    os.makedirs(path, exist_ok=True)

def slugify(name: str) -> str:
    # простой безопасный слагификатор для имени файла
    name = name.strip().lower()
    name = re.sub(r"[^\w\.-]+", "-", name, flags=re.UNICODE)
    name = re.sub(r"-{2,}", "-", name).strip("-")
    return name or "channel"

def parse_date_iso(s: str | None, tz_fallback: str) -> datetime | None:
    if not s:
        return None
    # Разрешаем "YYYY-MM-DD" и полные ISO-варианты; при отсутствии tz считаем в tz_fallback
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=ZoneInfo(tz_fallback))
    # Переводим в UTC для корректного сравнения с message.date (UTC)
    return dt.astimezone(timezone.utc)

def format_dt(dt: datetime, tzname: str, fmt: str) -> str:
    # message.date приходит в UTC; отобразим в желаемой таймзоне
    local = dt.astimezone(ZoneInfo(tzname))
    return local.strftime(fmt)

async def fetch_channel_meta(client: TelegramClient, entity):
    # Заголовок и описание канала
    title = getattr(entity, "title", None) or getattr(entity, "name", None) or str(entity)
    username = getattr(entity, "username", None)
    about = ""
    try:
        full = await client(GetFullChannelRequest(entity))
        # full.full_chat.about — текст описания
        about = getattr(full.full_chat, "about", "") or ""
    except Exception:
        # для чатов/супергрупп без full_chat или если нет прав — оставим пусто
        about = ""
    return title, username, about

def build_header_markdown(title: str, about: str, username: str | None, link_to_messages: bool) -> str:
    lines = [f"# {title}\n"]
    if about.strip():
        # Короткий блок-цитата описания
        lines.append("> " + about.strip().replace("\n", "\n> ") + "\n")
    if link_to_messages and username:
        lines.append(f"Источник: https://t.me/{username}\n")
    lines.append("\n---\n")
    return "\n".join(lines)

def build_message_block(msg, tzname: str, fmt: str, username: str | None, add_link: bool) -> str:
    # Пропускаем полностью пустые тексты (без медиа) — сохраняем только текстовые сообщения
    text = (msg.message or "").rstrip()
    # Дата и заголовок блока
    dt_str = format_dt(msg.date, tzname, fmt)
    title = f"### {dt_str} — Сообщение #{msg.id}"
    if add_link and username:
        title += f" ([ссылка](https://t.me/{username}/{msg.id}))"
    body = text if text else ""
    if body:
        return f"{title}\n\n{body}\n"
    else:
        return f"{title}\n"

async def export_channel(client: TelegramClient, chan_cfg: dict, global_cfg: dict):
    out_dir = global_cfg["output"]["dir"]
    tzname = global_cfg["output"]["timezone"]
    date_fmt = global_cfg["output"]["date_format"]
    include_service = global_cfg["output"]["include_service_messages"]
    reverse = bool(global_cfg["output"]["reverse_order"])
    link_to_messages = bool(global_cfg["output"]["link_to_messages"])

    identifier = chan_cfg.get("id") or chan_cfg.get("url")
    if not identifier:
        print("Пропуск канала без поля id/url в config.yaml")
        return

    limit = chan_cfg.get("limit") or None
    if isinstance(limit, int) and limit <= 0:
        limit = None

    oldest = parse_date_iso(chan_cfg.get("oldest_date"), tzname)
    newest = parse_date_iso(chan_cfg.get("newest_date"), tzname)

    try:
        entity = await client.get_entity(identifier)
    except (UsernameInvalidError, ValueError) as e:
        print(f"[WARN] Не удалось получить сущность канала '{identifier}': {e}")
        return
    except ChannelPrivateError as e:
        print(f"[WARN] Приватный канал '{identifier}', нет доступа: {e}")
        return

    title, username, about = await fetch_channel_meta(client, entity)

    # Имя файла
    fname = chan_cfg.get("filename")
    if not fname:
        if username:
            fname = slugify(username)
        else:
            fname = slugify(title)
    ensure_dir(out_dir)
    out_path = os.path.join(out_dir, f"{fname}.md")

    # Шапка
    header = build_header_markdown(title, about, username, link_to_messages)

    # Сбор сообщений
    chunks: list[str] = [header]
    async for msg in client.iter_messages(entity, limit=limit, reverse=reverse):
        # Фильтр системных сообщений
        if isinstance(msg, MessageService) and not include_service:
            continue
        # Фильтр дат
        msg_dt_utc = msg.date  # уже UTC
        if oldest and msg_dt_utc < oldest:
            # если идем от новых к старым и дата стала меньше минимальной — можно ускориться
            if not reverse:
                # дальше будут только более старые — прекращаем
                break
            else:
                continue
        if newest and msg_dt_utc > newest:
            # слишком новые — пропускаем (актуально при reverse=True)
            continue

        block = build_message_block(msg, tzname, date_fmt, username, link_to_messages)
        chunks.append(block + "\n")

    # Запись на диск
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(chunks))

    print(f"[OK] Экспортировано: {title} -> {out_path}")

async def main():
    cfg = load_config(CONFIG_FILE)
    api_id = cfg["telegram"]["api_id"]
    api_hash = cfg["telegram"]["api_hash"]
    session_name = cfg["telegram"].get("session", "tg_session")

    async with TelegramClient(session_name, api_id, api_hash) as client:
        # При первом запуске Telethon попросит код из Telegram и (если есть) пароль 2FA
        tasks = [export_channel(client, ch, cfg) for ch in cfg["channels"]]
        await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())

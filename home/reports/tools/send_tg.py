#!/usr/bin/env python3
"""Отправка готового отчёта в Telegram.

Токен берётся из ~/.env (TG_BOT_TOKEN), получатель — из ~/.env (TG_CHAT_ID)
или из переменных окружения. Бота заводишь свой через @BotFather.

    python3 send_tg.py файл.docx "Подпись одной строкой"
"""
import os
import sys
from pathlib import Path
from urllib import request
import uuid

# Свой chat_id держи в ~/.env как TG_CHAT_ID, а не в коде.
CHAT_ID_DEFAULT = ''


def load_env(path=Path.home() / '.env'):
    env = {}
    if path.exists():
        for line in path.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def send_document(file_path, caption, token, chat_id):
    boundary = uuid.uuid4().hex
    file_path = Path(file_path)
    data = file_path.read_bytes()

    def field(name, value):
        return (f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n'
                f'{value}\r\n').encode('utf-8')

    body = field('chat_id', chat_id) + field('caption', caption)
    body += (f'--{boundary}\r\nContent-Disposition: form-data; name="document"; '
             f'filename="{file_path.name}"\r\n'
             f'Content-Type: application/octet-stream\r\n\r\n').encode('utf-8')
    body += data + f'\r\n--{boundary}--\r\n'.encode('utf-8')

    req = request.Request(
        f'https://api.telegram.org/bot{token}/sendDocument',
        data=body,
        headers={'Content-Type': f'multipart/form-data; boundary={boundary}'},
    )
    with request.urlopen(req, timeout=120) as resp:
        return resp.read().decode('utf-8')


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    file_path = sys.argv[1]
    caption = sys.argv[2] if len(sys.argv) > 2 else Path(file_path).stem

    env = load_env()
    token = os.environ.get('TG_BOT_TOKEN') or env.get('TG_BOT_TOKEN')
    chat_id = os.environ.get('TG_CHAT_ID') or env.get('TG_CHAT_ID') or CHAT_ID_DEFAULT
    if not token:
        print('НЕТ ТОКЕНА: TG_BOT_TOKEN не найден ни в окружении, ни в ~/.env')
        sys.exit(2)
    if not chat_id:
        print('НЕТ ПОЛУЧАТЕЛЯ: задай TG_CHAT_ID в ~/.env (свой id узнаешь у @userinfobot)')
        sys.exit(2)

    result = send_document(file_path, caption, token, chat_id)
    print('ОТПРАВЛЕНО' if '"ok":true' in result else f'ОШИБКА: {result[:400]}')


if __name__ == '__main__':
    main()

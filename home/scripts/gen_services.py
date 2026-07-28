#!/usr/bin/env python3
"""Генератор ~/.claude/workspace/SERVICES.md из ЖИВОГО состояния VPS.

Зачем: карта сервисов, которую ведут руками, расходится с фактом (на 19.07.2026
файл отставал на 3 месяца и не знал половины ботов). Владелец карты — не человек,
а этот скрипт: он снимает systemd/docker/порты/cron/MCP и перезаписывает файл.

Запуск: python3 ~/scripts/gen_services.py [--dry-run]
Крон: раз в сутки (см. хвост сгенерированного файла).

Описания сервисов НЕ придумываются — берутся из systemd Description и docker image,
поэтому «осмысленность» карты обеспечивается качеством unit-файлов, а не словарём здесь.
"""
from __future__ import annotations

import argparse
import re
import subprocess
from datetime import datetime, timezone, timedelta
from pathlib import Path

OUT = Path.home() / ".claude" / "workspace" / "SERVICES.md"
MSK = timezone(timedelta(hours=3))

# Маскируем всё, что пахнет секретом, — файл читается в контексте сессий.
SECRET_RE = re.compile(
    r"(?i)\b([A-Z0-9_]*(?:TOKEN|KEY|SECRET|PASSWORD|PASSWD|PWD|CREDENTIAL)[A-Z0-9_]*)\s*=\s*\S+"
)


def run(cmd: str, timeout: int = 30) -> str:
    """Выполнить команду, вернуть stdout. Пустая строка = источник недоступен."""
    try:
        r = subprocess.run(
            ["bash", "-lc", cmd], capture_output=True, text=True, timeout=timeout
        )
        return r.stdout.strip()
    except Exception:
        return ""


def mask(text: str) -> str:
    return SECRET_RE.sub(r"\1=***", text)


# Базовая обвязка ОС — в карте сервисов она шум: перечисляем одной строкой.
OS_NOISE = re.compile(
    r"^(systemd-|getty@|serial-getty@|user@|dbus|polkit|acpid|qemu-guest-agent|"
    r"tuned|rsyslog|unattended-upgrades|multipathd|irqbalance|snapd|packagekit)"
)


def _since(scope: str, unit: str) -> str:
    """ActiveEnterTimestamp вида 'Thu 2026-07-16 10:00:00 MSK' → '2026-07-16 10:00'."""
    raw = run(f"systemctl {scope} show {unit} -p ActiveEnterTimestamp --value", timeout=10)
    parts = raw.split()
    if len(parts) >= 3:
        return f"{parts[1]} {parts[2][:5]}"
    return "—"


def units_table(scope: str) -> str:
    """scope: '' (системные) или '--user'."""
    raw = run(
        f"systemctl {scope} list-units --type=service --state=running "
        f"--no-pager --plain --no-legend"
    )
    if not raw:
        return "_(источник недоступен)_\n"
    rows, noise = [], []
    for line in raw.splitlines():
        parts = line.split(None, 4)
        if len(parts) < 5:
            continue
        unit, _load, _active, _sub, desc = parts
        name = unit.removesuffix(".service")
        if OS_NOISE.match(name):
            noise.append(name)
            continue
        rows.append(f"| `{unit}` | {_since(scope, unit)} | {desc} |")
    out = ""
    if rows:
        out += "| Unit | Запущен с | Описание |\n|---|---|---|\n" + "\n".join(rows) + "\n"
    else:
        out += "_(прикладных сервисов нет)_\n"
    if noise:
        out += f"\nБазовая обвязка ОС (running): {', '.join(f'`{n}`' for n in sorted(noise))}\n"
    return out


def docker_table() -> str:
    raw = run("docker ps --format '{{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}'")
    if not raw:
        return "_(docker недоступен или контейнеров нет)_\n"
    rows = []
    for line in raw.splitlines():
        f = line.split("\t")
        while len(f) < 4:
            f.append("")
        ports = f[3].replace(", ", "<br>") or "—"
        rows.append(f"| `{f[0]}` | `{f[1]}` | {f[2]} | {ports} |")
    return "| Контейнер | Image | Статус | Порты |\n|---|---|---|---|\n" + "\n".join(rows) + "\n"


def ports_table() -> str:
    raw = run("ss -tlnp 2>/dev/null || ss -tln")
    if not raw:
        return "_(источник недоступен)_\n"
    rows = []
    for line in raw.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 4:
            continue
        local = parts[3]
        proc = ""
        m = re.search(r'users:\(\("([^"]+)"', line)
        if m:
            proc = f"`{m.group(1)}`"
        exposure = "🌍 наружу" if local.startswith(("0.0.0.0", "*", "[::]")) else "🔒 локально"
        rows.append(f"| `{local}` | {exposure} | {proc} |")
    if not rows:
        return "_(нет слушающих сокетов)_\n"
    return "| Адрес:порт | Доступность | Процесс |\n|---|---|---|\n" + "\n".join(sorted(set(rows))) + "\n"


def cron_block() -> str:
    raw = run("crontab -l")
    if not raw:
        return "_(crontab пуст или недоступен)_\n"
    lines = [ln for ln in raw.splitlines() if ln.strip() and not ln.strip().startswith("#")]
    return "```cron\n" + mask("\n".join(lines)) + "\n```\n"


def mcp_block() -> str:
    raw = run("timeout 60 claude mcp list 2>&1", timeout=70)
    if not raw:
        return "_(claude CLI недоступен)_\n"
    lines = [
        ln for ln in raw.splitlines()
        if ln.strip() and not ln.lower().startswith("checking mcp")
    ]
    return "```\n" + mask("\n".join(lines)) + "\n```\n"


def resources_block() -> str:
    disk = run("df -h / | tail -1")
    mem = run("free -h | sed -n '2p'")
    swap = run("free -h | sed -n '3p'")
    load = run("uptime")
    out = []
    if disk:
        f = disk.split()
        out.append(f"- **Диск /**: {f[2]} занято из {f[1]} (свободно {f[3]}, {f[4]})")
    if mem:
        f = mem.split()
        out.append(f"- **Память**: {f[2]} занято из {f[1]} (доступно {f[6] if len(f) > 6 else '?'})")
    if swap:
        f = swap.split()
        total = f[1] if len(f) > 1 else "?"
        note = " ⚠️ swap отсутствует" if total in ("0B", "0", "0Gi", "0Mi") else ""
        out.append(f"- **Swap**: {f[2] if len(f) > 2 else '?'} занято из {total}{note}")
    if load:
        m = re.search(r"load average: (.+)", load)
        if m:
            out.append(f"- **Load average**: {m.group(1)}")

    # крупнейшие каталоги домашней папки — чтобы рост диска был виден заранее
    top = run("du -sh ~/* ~/.[!.]* 2>/dev/null | sort -rh | head -6", timeout=180)
    if top:
        items = []
        for line in top.splitlines():
            parts = line.split(None, 1)
            if len(parts) == 2:
                items.append(f"`{Path(parts[1]).name}` {parts[0]}")
        if items:
            out.append(f"- **Крупнейшее в `~`**: {' · '.join(items)}")
    return "\n".join(out) + "\n" if out else "_(источник недоступен)_\n"


def build() -> str:
    now = datetime.now(MSK)
    stamp = now.strftime("%Y-%m-%d %H:%M МСК")
    host = run("hostname") or "?"
    osname = run("lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY | cut -d= -f2")
    cpu = run("nproc")
    ram = run("free -h | sed -n '2p' | awk '{print $2}'")

    return f"""---
title: SERVICES — живой снапшот сервисов VPS
scope: vps
updated: {now.strftime('%Y-%m-%d')}
generated: true
---

# SERVICES.md

> ⚙️ **Файл генерируется автоматически** — `~/scripts/gen_services.py`, снимок от **{stamp}**.
> Руками не править: правки затрутся следующим прогоном. Нужно постоянное пояснение —
> добавляй его в описание systemd-юнита или в `~/vault/projects/vps-infrastructure.md`.

Сервер: `{host}`, {osname.strip('"')}, {cpu} vCPU, {ram} RAM.

За архитектурными решениями и «почему так» → `~/vault/projects/vps-infrastructure.md`.

---

## Systemd — системные сервисы

{units_table('')}
## Systemd — user-сервисы (`systemctl --user`)

{units_table('--user')}
---

## Docker

{docker_table()}
---

## Открытые порты

{ports_table()}
---

## Cron

{cron_block()}
---

## MCP-серверы

{mcp_block()}
---

## Ресурсы

{resources_block()}
---

## Как это обновляется

```bash
python3 ~/scripts/gen_services.py          # перезаписать снапшот
python3 ~/scripts/gen_services.py --dry-run  # посмотреть, не записывая
```

Крон: раз в сутки. Источники — `systemctl`, `docker ps`, `ss -tlnp`, `crontab -l`,
`claude mcp list`, `df/free/uptime`. Значения вида `*_TOKEN=`/`*_KEY=` маскируются.
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="вывести в stdout, не записывать")
    args = ap.parse_args()

    content = build()
    if args.dry_run:
        print(content)
        return
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(content, encoding="utf-8")
    print(f"OK: {OUT} обновлён ({len(content.splitlines())} строк)")


if __name__ == "__main__":
    main()

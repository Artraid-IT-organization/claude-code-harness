#!/usr/bin/env bash
# SessionStart-хук: короткая инъекция «в очереди N решений CEO».
# Пусто → молчим (ноль засорения контекста). Содержимое НЕ инжектится — только счётчик.
# ТОЛЬКО для штабных сессий в $HOME: боты (`claude --print` из /tmp и своих
# каталогов) и воркеры в проектах очередь CEO видеть не должны — 12.07.26
# команда «скажи в начале ответа…» утекла в текст поздравления ДР-рассылки.
set +e
CWD="$(cat 2>/dev/null | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
print((d or {}).get("cwd","") or (d or {}).get("projectRoot",""))' 2>/dev/null)"
[[ "$CWD" == "$HOME" ]] || exit 0
Q="$HOME/.claude/workspace/DECISIONS.md"
[[ -f "$Q" ]] || exit 0
N=$(grep -c '^## \[' "$Q" 2>/dev/null)
[[ "${N:-0}" -gt 0 ]] || exit 0
echo "ОЧЕРЕДЬ РЕШЕНИЙ CEO: ${N} вопрос(ов) ждут владельца — ~/.claude/workspace/DECISIONS.md. Помимо основной задачи скажи в начале ответа: «в очереди ${N} вопрос(ов) — разберём?» Содержимое файла НЕ читай и не разворачивай, пока владелец не согласится; решённые блоки удаляй из файла."
exit 0

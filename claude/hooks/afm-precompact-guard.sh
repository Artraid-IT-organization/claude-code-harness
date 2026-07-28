#!/usr/bin/env bash
# CTX-фреймворк (AFM): страж авто-компакта. Если идёт активная волна (флаг WAVE_ACTIVE),
# АВТО-компакт блокируется (mid-wave суммаризация без чекпойнта = потеря незаписанного состояния).
# Ручной /compact (source=manual) не блокируем — оркестратор делает его осознанно после чекпойнта.
set -u
INPUT=$(cat)
SRC=$(printf '%s' "$INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('source',''))" 2>/dev/null)
if [ "$SRC" = "auto" ]; then
  for f in $HOME/*/afm/*/WAVE_ACTIVE; do
    [ -f "$f" ] || continue
    echo '{"decision":"block","reason":"AFM: активная волна ('"$f"') — сначала чекпойнт-ритуал (journal/plan/вердикты в файлы), затем управляемый /compact или /clear на границе волны."}'
    exit 0
  done
fi
exit 0

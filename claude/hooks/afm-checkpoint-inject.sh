#!/usr/bin/env bash
# CTX-фреймворк (AFM): при старте/очистке/компакте сессии авто-инжектит чекпойнт активной AFM-программы.
# Ищет CHECKPOINT.md активных программ в известных корнях; выводит в stdout -> попадает в контекст.
set -u
FOUND=0
for cp in $HOME/*/afm/*/CHECKPOINT.md; do
  [ -f "$cp" ] || continue
  # активной считается программа, чей журнал моложе 7 дней
  j="$(dirname "$cp")/journal.md"
  if [ -f "$j" ] && [ -n "$(find "$j" -mtime -7 2>/dev/null)" ]; then
    if [ "$FOUND" -eq 0 ]; then
      echo "=== АКТИВНАЯ AFM-ПРОГРАММА: авто-чекпойнт (CTX-фреймворк) ==="
      FOUND=1
    fi
    echo "--- $cp ---"
    head -60 "$cp"
    echo ""
    echo "(Полное состояние: PROGRAM.md, plan.md, хвост journal.md рядом с чекпойнтом. Оркестратору нужен /model fable — если сессия на другой модели, скажи пользователю.)"
  fi
done
exit 0

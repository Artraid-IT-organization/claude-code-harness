#!/usr/bin/env bash
# install.sh — установка харнесса на сервер.
# Запускать от имени будущего владельца:  bash install.sh
#
# Идемпотентен. Существующие настройки Claude Code не затираются, а СЛИВАЮТСЯ:
# твои разрешения и предпочтения сохраняются. Прежнее состояние бэкапится.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.harness-backup-$STAMP"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }

[ -d "$HERE/home" ] && [ -d "$HERE/claude" ] || {
  echo "Не найдены каталоги home/ и claude/ рядом с install.sh"; exit 1; }

say "0. Проверка окружения"
command -v python3 >/dev/null && ok "python3 $(python3 -V 2>&1 | awk '{print $2}')" \
  || { echo "  ✗ нет python3 — установи и повтори"; exit 1; }
command -v claude  >/dev/null && ok "claude есть" \
  || warn "нет Claude Code — установи: npm i -g @anthropic-ai/claude-code"
command -v node    >/dev/null && ok "node $(node -v)"  || warn "нет node — часть скиллов не заработает"
command -v git     >/dev/null && ok "git есть"          || warn "нет git — скилл работы с историей и часть проверок недоступны"

say "1. Бэкап текущего состояния"
if [ -d "$HOME/.claude" ] || [ -f "$HOME/CLAUDE.md" ]; then
  mkdir -p "$BACKUP"
  for p in .claude CLAUDE.md scripts vault reports context-ops; do
    [ -e "$HOME/$p" ] && cp -a "$HOME/$p" "$BACKUP/" 2>/dev/null || true
  done
  ok "прежнее состояние скопировано в $BACKUP"
else
  ok "чистая машина, бэкапить нечего"
  BACKUP=""
fi

say "2. Раскладка файлов"
mkdir -p "$HOME/.claude"
# CLAUDE.md не перезаписываем, если он уже есть: там может быть твоя работа
if [ -f "$HOME/CLAUDE.md" ]; then
  cp "$HERE/home/CLAUDE.md" "$HOME/CLAUDE.md.harness-new"
  warn "твой ~/CLAUDE.md оставлен как есть, версия харнесса рядом: CLAUDE.md.harness-new"
  tar -c -C "$HERE/home" --exclude=./CLAUDE.md . | tar -x -C "$HOME"
else
  tar -c -C "$HERE/home" . | tar -x -C "$HOME"
fi
ok "домашний каталог: scripts, vault, reports, context-ops"
tar -c -C "$HERE/claude" --exclude=./settings.json --exclude=./settings.local.json . \
  | tar -x -C "$HOME/.claude"
ok ".claude: хуки, сабагенты, скиллы, рабочее пространство, петля обучения"

say "3. Слияние настроек (твои разрешения и предпочтения сохраняются)"
python3 - "$HOME/.claude/settings.json" "$HERE/claude/settings.json" <<'PY'
import json, os, sys
dst, src = sys.argv[1], sys.argv[2]
mine = json.load(open(src, encoding='utf-8'))
existing = {}
if os.path.exists(dst):
    try:
        existing = json.load(open(dst, encoding='utf-8'))
    except Exception:
        existing = {}
merged = {**existing, **mine}
kept = [k for k in existing if k not in mine]
json.dump(merged, open(dst, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print("  ✓ settings.json: настройки харнесса применены"
      + (f", твои ключи сохранены: {', '.join(kept)}" if kept else ""))
PY
python3 - "$HOME/.claude/settings.local.json" "$HERE/claude/settings.local.json" <<'PY'
import json, os, sys
dst, src = sys.argv[1], sys.argv[2]
mine = json.load(open(src, encoding='utf-8'))
existing = {}
if os.path.exists(dst):
    try:
        existing = json.load(open(dst, encoding='utf-8'))
    except Exception:
        existing = {}
merged = {**existing, **mine}
own = 0
for section in ('allow', 'deny', 'ask'):
    a = (existing.get('permissions') or {}).get(section) or []
    b = (mine.get('permissions') or {}).get(section) or []
    if a or b:
        seen, out = set(), []
        for rule in a + b:                       # свои правила идут первыми
            if rule not in seen:
                seen.add(rule); out.append(rule)
        merged.setdefault('permissions', {})[section] = out
        own += len(a)
json.dump(merged, open(dst, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
total = len((merged.get('permissions') or {}).get('allow') or [])
print(f"  ✓ settings.local.json: {total} правил в allow, твоих было {own}")
PY

say "4. Каталог долгосрочной памяти"
# Claude Code именует каталог проекта слагом домашнего пути: /home/user → -home-user.
# Ошибиться здесь = память молча не подхватится, и это никак не проявится.
SLUG="$(printf '%s' "$HOME" | tr '/' '-')"
MEM_DIR="$HOME/.claude/projects/$SLUG/memory"
mkdir -p "$MEM_DIR"
if [ ! -f "$MEM_DIR/MEMORY.md" ]; then
  cat > "$MEM_DIR/MEMORY.md" <<'EOF'
# MEMORY.md — индекс долгосрочной памяти

> Одна строка на запись: заголовок и короткий хук. Детали — в отдельных файлах рядом.
> Это индекс, а не хранилище: он загружается в контекст каждую сессию, поэтому растёт медленно.

<!-- Формат строки:
     - [Тип: заголовок](имя-файла.md) — чем эта запись полезна в одной фразе

     Типы записей:
       user      — кто владелец: роль, экспертиза, предпочтения
       feedback  — как работать: поправки и подтверждённые подходы, обязательно с причиной
       project   — текущие работы, цели, ограничения, не выводимые из кода
       reference — указатели на внешние ресурсы: ссылки, панели, тикеты
-->
EOF
  ok "создан пустой индекс памяти: $MEM_DIR/MEMORY.md"
else
  ok "индекс памяти уже есть, не трогаю"
fi

say "5. Права на исполнение"
chmod +x "$HOME/.claude/hooks/"*.sh 2>/dev/null || true
chmod +x "$HOME/scripts/"* 2>/dev/null || true
chmod +x "$HOME/.claude/learning-loop/"*.py "$HOME/.claude/learning-loop/"*.sh 2>/dev/null || true
chmod +x "$HOME/context-ops/bin/"*.sh "$HOME/reports/tools/"*.sh 2>/dev/null || true
ok "хуки и скрипты исполняемые"

say "6. Инициализация петли обучения"
LL="$HOME/.claude/learning-loop"
if [ -f "$LL/ll.sqlite" ]; then
  ok "база уже есть, не трогаю"
else
  python3 - "$LL/schema.sql" "$LL/ll.sqlite" <<'PY'
import sqlite3, sys
schema, db = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
con.executescript(open(schema, encoding='utf-8').read())
con.commit(); con.close()
print("  ✓ ll.sqlite создана из schema.sql")
PY
  : > "$LL/sessions.jsonl"
  ok "журнал сессий создан пустым"
fi

say "7. Рабочие каталоги"
mkdir -p "$HOME/projects" "$HOME/logs" "$HOME/.runjob"
ok "созданы ~/projects, ~/logs, ~/.runjob"

say "8. Статуслайн"
# Строка состояния держится на внешнем npm-пакете. Без него обёртка печатает ошибку
# прямо в статусную строку — поэтому проверяем ЗАПУСКОМ и при неудаче отключаем.
HUD="$HOME/.claude/hud/omc-hud.mjs"
HUD_OK=0
if command -v npm >/dev/null && command -v node >/dev/null && [ -f "$HUD" ]; then
  [ -d "$(npm root -g)/oh-my-claude-sisyphus" ] || npm i -g oh-my-claude-sisyphus >/dev/null 2>&1 || true
  HUD_OUT="$(echo '{}' | timeout 10 node "$HUD" 2>&1 | head -1)"
  case "$HUD_OUT" in
    *"not installed"*|*"Error"*|*"error"*|*"Cannot find"*|"") HUD_OK=0 ;;
    *) HUD_OK=1 ;;
  esac
fi
if [ "$HUD_OK" -eq 1 ]; then
  ok "статуслайн работает"
else
  python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding='utf-8'))
if d.pop('statusLine', None) is not None:
    json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    print("  ✓ statusLine отключён — плагин не установлен")
else:
    print("  ✓ statusLine в настройках отсутствует")
PY
  warn "нужна строка состояния — поставь плагин, затем верни блок statusLine"
fi

say "9. Самопроверка"
CHECK_OK=1
for f in "$HOME/.claude/settings.json" "$HOME/.claude/workspace/SOUL.md" \
         "$HOME/.claude/hooks/loop-recall.sh" "$MEM_DIR/MEMORY.md" \
         "$HOME/vault/principles/gornostaev-17.md"; do
  [ -f "$f" ] && ok "есть ${f#$HOME/}" || { warn "НЕТ $f"; CHECK_OK=0; }
done
python3 -c "import json; json.load(open('$HOME/.claude/settings.json')); print('  ✓ settings.json — валидный JSON')" || CHECK_OK=0
python3 -c "import json; json.load(open('$HOME/.claude/settings.local.json')); print('  ✓ settings.local.json — валидный JSON')" || CHECK_OK=0
for h in "$HOME/.claude/hooks/"*.sh; do
  bash -n "$h" 2>/dev/null || { warn "синтаксис хука: $h"; CHECK_OK=0; }
done
ok "хуки синтаксически корректны"
echo '{"cwd":"'"$HOME"'"}' | bash "$HOME/.claude/hooks/loop-recall.sh" >/dev/null 2>&1 \
  && ok "хук петли обучения запускается" || { warn "хук петли падает"; CHECK_OK=0; }

say "ГОТОВО"
if [ "$CHECK_OK" -eq 1 ]; then
  cat <<EOF

Харнесс установлен. Дальше:

  1. bash $HERE/onboard.sh
     Интервью: заполнит SOUL.md, USER.md и CLAUDE.md под тебя и твои проекты.
     Без этого шага харнесс работает, но не знает, кто ты — половина смысла теряется.

  2. Свои токены в ~/.env, если нужна отправка отчётов:
     TG_BOT_TOKEN=...
     TG_CHAT_ID=...

  3. Запусти claude в домашнем каталоге и посмотри, как отрабатывает старт сессии.

EOF
  [ -n "$BACKUP" ] && echo "  Бэкап прежнего состояния: $BACKUP"
  echo
else
  echo "Проверка нашла проблемы — смотри пометки ! выше."
  exit 1
fi

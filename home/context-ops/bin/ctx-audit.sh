#!/usr/bin/env bash
# ctx-audit.sh — замер контекстного «налога» Claude Code на VPS.
# Методика и нормативы: ~/context-ops/METHOD.md. Обновлено: 2026-07-18.
set -uo pipefail

DIV=4  # ~байт на токен (кириллица UTF-8 ≈ 4–5, латиница ≈ 4) — оценка, не факт
OUT_DIR="$HOME/context-ops/audits"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$(date +%F)-raw.md"

fsize() { if [ -f "$1" ]; then wc -c < "$1"; else echo 0; fi; }
tok() { echo $(( ${1:-0} / DIV )); }
kb() { echo $(( (${1:-0} + 512) / 1024 )); }

report() {
echo "# Контекст-аудит (raw) — $(date '+%Y-%m-%d %H:%M')"
echo

echo "## 1. Модель по умолчанию"
MODEL=$(jq -r '.model // "не задана"' "$HOME/.claude/settings.json" 2>/dev/null || echo "jq недоступен")
echo "- settings.json: \`$MODEL\`"
case "$MODEL" in
  *"[1m]"*) echo "- 🔴 включено окно 1M — норматив: без [1m] по умолчанию" ;;
  *)        echo "- ✅ без [1m]" ;;
esac
echo

echo "## 2. Стартовый пакет штаба (грузится каждую сессию в ~)"
echo "| файл | КБ | ~токенов |"
echo "|---|---:|---:|"
main="$HOME/CLAUDE.md"
chain=0
list="$main"
while IFS= read -r rel; do
  rel="${rel#@}"
  case "$rel" in
    /*)   f="$rel" ;;
    "~"*) f="$HOME${rel#\~}" ;;
    *)    f="$HOME/$rel" ;;
  esac
  [ -f "$f" ] && list="$list
$f"
done < <(grep -oE '@[A-Za-z0-9._~/-]+\.md' "$main" 2>/dev/null)
while IFS= read -r f; do
  [ -z "$f" ] && continue
  b=$(fsize "$f"); chain=$((chain+b))
  echo "| ${f#$HOME/} | $(kb "$b") | $(tok "$b") |"
done <<< "$list"
# каталог памяти именуется слагом домашнего пути: /home/user → -home-user
MEM="$HOME/.claude/projects/$(printf '%s' "$HOME" | tr '/' '-')/memory/MEMORY.md"
mb=$(fsize "$MEM")
echo "| MEMORY.md (индекс памяти) | $(kb "$mb") | $(tok "$mb") |"
LESSON=$("$HOME/.claude/hooks/loop-recall.sh" 2>/dev/null | wc -c || echo 0)
echo "| инъекция уроков (hook) | $(kb "$LESSON") | $(tok "$LESSON") |"
grand=$((chain+mb+LESSON))
echo "| **итого** | **$(kb "$grand")** | **$(tok "$grand")** |"
echo
if [ "$chain" -gt 16384 ]; then echo "- 🔴 цепочка CLAUDE.md+импорты $(kb "$chain") КБ > норматива 16 КБ"; else echo "- ✅ цепочка CLAUDE.md+импорты в нормативе (≤16 КБ)"; fi
if [ "$mb" -gt 10240 ]; then echo "- 🔴 MEMORY.md $(kb "$mb") КБ > норматива 10 КБ — сжать хуки индекса"; else echo "- ✅ MEMORY.md в нормативе (≤10 КБ)"; fi
echo

echo "## 3. Скиллы (описания грузятся в каждую сессию, включая ботов)"
NSK=$(ls -d "$HOME"/.claude/skills/*/ 2>/dev/null | wc -l)
DSK=$(for f in "$HOME"/.claude/skills/*/SKILL.md; do awk '/^description:/' "$f" 2>/dev/null; done | wc -c)
echo "- скиллов: $NSK, суммарный вес описаний: $(kb "$DSK") КБ (~$(tok "$DSK") токенов)"
if [ "$NSK" -gt 30 ]; then echo "- 🔴 больше норматива 30 — вычистить неиспользуемые (в первую очередь пакеты)"; else echo "- ✅ в нормативе (≤30)"; fi
echo "- топ-5 самых тяжёлых описаний:"
for f in "$HOME"/.claude/skills/*/SKILL.md; do
  d=$(awk '/^description:/' "$f" 2>/dev/null | wc -c)
  echo "$d $(basename "$(dirname "$f")")"
done | sort -rn | head -5 | awk '{print "  - "$2" ("$1" байт)"}'
echo

echo "## 4. MCP-серверы (схемы инструментов = токены каждой сессии)"
G=$(jq -r '.mcpServers | keys | join(", ")' "$HOME/.claude.json" 2>/dev/null)
echo "- глобальные: ${G:-нет}"
jq -r '.projects | to_entries[]? | select(.value.mcpServers != null and (.value.mcpServers|length)>0) | "- " + .key + ": " + (.value.mcpServers|keys|join(", "))' "$HOME/.claude.json" 2>/dev/null
echo

echo "## 5. Автоматика: сессии за 7 дней по каталогам (статья В)"
echo "| каталог | сессий | МБ |"
echo "|---|---:|---:|"
for d in "$HOME"/.claude/projects/*/; do
  c=$(find "$d" -maxdepth 1 -name "*.jsonl" -mtime -7 2>/dev/null | wc -l)
  [ "$c" -gt 0 ] || continue
  m=$(find "$d" -maxdepth 1 -name "*.jsonl" -mtime -7 -print0 2>/dev/null | xargs -0 -r du -ck 2>/dev/null | tail -1 | cut -f1)
  echo "$c|$(( ${m:-0} / 1024 ))|$(basename "$d")"
done | sort -t'|' -k1,1 -rn | while IFS='|' read -r c m n; do echo "| $n | $c | $m |"; done
echo
echo "Правило: >20 сессий/нед в одном каталоге = проверить, что вызов идёт с явным --model по cost-curve."
echo

echo "## 6. Самые тяжёлые сессии за 7 дней (раздутый живой контекст, статья Б)"
find "$HOME/.claude/projects" -name "*.jsonl" -mtime -7 -size +3M 2>/dev/null | xargs -r du -m 2>/dev/null | sort -rn | head -5 | awk '{print "- "$1" МБ  "$2}'
echo
echo "---"
echo "Оценка токенов = байты/$DIV (грубо). Реальный расход лимита — /usage в интерактивной сессии."
}

report | tee "$OUT"
echo
echo "Сохранено: $OUT" >&2

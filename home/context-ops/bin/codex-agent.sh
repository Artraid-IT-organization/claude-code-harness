#!/usr/bin/env bash
# codex-agent.sh — OpenAI Codex CLI как субагент Claude (бюджет OpenAI, не лимит Claude).
# Железная деградация: пайплайн НИКОГДА не останавливается из-за Codex.
#
# Контракт для вызывающего (Claude/AFM-волна):
#   exit 0, stdout = ответ Codex                → успех
#   exit 3, stdout = "CODEX_UNAVAILABLE reason=<auth|limit|timeout|nobinary|error> [детали]"
#     → ОБЯЗАН: (1) выполнить ту же задачу sonnet-субагентом Claude НЕМЕДЛЕННО (не Fable),
#               (2) пометить фолбэк в отчёте/журнале волны («Codex недоступен: reason»).
#
# Режимы:
#   codex-agent.sh --check                       # быстрая проверка доступности (для Фазы 1 AFM)
#   codex-agent.sh [--write] [--timeout N] [--model M] "<задание>"
#
# Дефолты: sandbox read-only (Codex только читает репо); --write = workspace-write,
# допускается ТОЛЬКО в изолированном worktree. Секреты и красные зоны прода не передавать.
# Обновлено: 2026-07-18 (Context Ops)
set -uo pipefail

STATE_DIR="$HOME/context-ops/state"; mkdir -p "$STATE_DIR"
COOLDOWN_FILE="$STATE_DIR/codex.cooldown"   # unix-время, до которого Codex не дёргаем (лимит)
LOG="$STATE_DIR/codex-agent.log"
TIMEOUT=600
SANDBOX="read-only"
MODEL="${CODEX_MODEL:-}"                     # пусто = дефолт из ~/.codex/config.toml

now() { date +%s; }
fail() { echo "CODEX_UNAVAILABLE reason=$1${2:+ $2}"; exit 3; }

# --- fail-fast проверки доступности (не тратим время пайплайна)
command -v codex >/dev/null 2>&1 || fail nobinary
[ -f "$HOME/.codex/auth.json" ] || fail auth "выполни: codex login"
if [ -f "$COOLDOWN_FILE" ]; then
  until_ts=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
  if [ "$(now)" -lt "${until_ts:-0}" ]; then
    fail limit "cooldown до $(date -d "@${until_ts}" '+%H:%M' 2>/dev/null || echo '?')"
  else
    rm -f "$COOLDOWN_FILE"
  fi
fi

[ "${1:-}" = "--check" ] && { echo "CODEX_OK"; exit 0; }

while [ $# -gt 1 ]; do
  case "$1" in
    --write)   SANDBOX="workspace-write"; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --model)   MODEL="$2"; shift 2 ;;
    *) break ;;
  esac
done
PROMPT="${1:?задание обязательно}"

ARGS=(exec --sandbox "$SANDBOX" --skip-git-repo-check)
[ -n "$MODEL" ] && ARGS+=(--model "$MODEL")

OUT=$(timeout "$TIMEOUT" codex "${ARGS[@]}" "$PROMPT" 2>&1)
CODE=$?
echo "$(date '+%F %T') exit=$CODE sandbox=$SANDBOX chars=${#OUT} :: ${PROMPT:0:120}" >> "$LOG"

[ $CODE -eq 124 ] && fail timeout "${TIMEOUT}s"
if echo "$OUT" | grep -qiE 'usage limit|rate limit|quota|too many requests|429'; then
  echo $(( $(now) + 3600 )) > "$COOLDOWN_FILE"   # час не дёргаем, дальше пробуем снова
  fail limit "$(echo "$OUT" | grep -iE -m1 'usage limit|rate limit|quota|429' | head -c 160)"
fi
[ $CODE -ne 0 ] && fail error "exit=$CODE: $(echo "$OUT" | tail -c 200 | tr '\n' ' ')"

echo "$OUT"

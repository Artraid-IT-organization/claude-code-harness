#!/usr/bin/env bash
# Сбор фактуры за период по ВСЕМ проектам сервера — вход для отчёта.
# Выводит текст в stdout: объём по проектам, коммиты по дням, изменения вне git.
#
#   ./collect_facts.sh 2026-07-13 2026-07-20     # [начало, конец) — конец не включается
#   ./collect_facts.sh 2026-07-14                # один день
#
# Принцип: полный взгляд, без фиксированных списков.
#   • репозитории ищутся по всему $HOME (до 4 уровней), а не берутся из списка —
#     иначе новый проект недели молча выпадает из отчёта;
#   • коммиты берутся по ВСЕМ веткам (--all): работа часто идёт в feature-ветке,
#     а текущая ветка репозитория показывает лишь её часть;
#   • изменения вне git собираются по всем каталогам $HOME, кроме тяжёлых и мусорных.
# Никогда не считает doc-patrol и прочую автоматику за проделанную работу:
# они отфильтрованы, но их количество показано отдельно.
set -u

FROM="${1:?укажи дату начала: ГГГГ-ММ-ДД}"
TO="${2:-}"
if [ -z "$TO" ]; then
    TO=$(date -d "$FROM +1 day" +%Y-%m-%d)
fi

AUTO_RE='doc-patrol|\[bot\]'

# --- все git-репозитории в $HOME (worktree-копии не попадают: у них .git = файл) ---
mapfile -t REPOS < <(
    find "$HOME" -maxdepth 4 -type d -name .git \
         -not -path '*/node_modules/*' -not -path '*/.cache/*' \
         -not -path '*/venv/*' -not -path '*/.nvm/*' -not -path '*/.bun/*' \
         2>/dev/null | sed 's|/\.git$||' | sort -u
)

echo "==================== ФАКТУРА $FROM .. $TO ===================="
echo
echo "### ОБЪЁМ ПО ПРОЕКТАМ (все ветки, коммиты без автоматики)"
declare -A SEEN_REMOTE=()
for repo in "${REPOS[@]}"; do
    log=$(git -C "$repo" log --all --since="$FROM" --until="$TO" --oneline 2>/dev/null)
    all=$(printf '%s' "$log" | grep -c . )
    [ "$all" -eq 0 ] && continue
    auto=$(printf '%s\n' "$log" | grep -cE "$AUTO_RE")
    # два клона одного репозитория на сервере — не двойной объём работы, а дубль
    url=$(git -C "$repo" remote get-url origin 2>/dev/null)
    note=""
    if [ -n "$url" ]; then
        if [ -n "${SEEN_REMOTE[$url]:-}" ]; then
            note="  ⚠ тот же репозиторий, что ${SEEN_REMOTE[$url]} — не складывать"
        else
            SEEN_REMOTE[$url]="${repo#$HOME/}"
        fi
    fi
    printf '%-34s %4s (автоматика: %s)%s\n' "${repo#$HOME/}" "$((all - auto))" "$auto" "$note"
done

echo
echo "### КОММИТЫ ПО ДНЯМ И ПРОЕКТАМ (все ветки; в скобках — ветка/метка, если есть)"
for repo in "${REPOS[@]}"; do
    log=$(git -C "$repo" log --all --since="$FROM" --until="$TO" \
          --pretty=format:'%ad|%s%d' --date=format:'%d.%m %H:%M' 2>/dev/null \
          | grep -vE "$AUTO_RE" | sort)
    [ -z "$log" ] && continue
    echo
    echo "--- ${repo#$HOME/} ---"
    echo "$log"
done

echo
echo "### СОСТОЯНИЕ КЛЮЧЕВЫХ ПРОЕКТОВ (снапшоты, читать при сборке отчёта)"
for f in "$HOME/<проект>/STATE.md" \
         "$HOME/<проект>/afm/glass/CHECKPOINT.md" \
         "$HOME/.claude/workspace/DECISIONS.md"; do
    [ -f "$f" ] && echo "  $f  (изменён: $(date -r "$f" '+%d.%m %H:%M'))"
done
# Снапшоты активных программ AFM и задач периода — находятся, а не перечисляются
find "$HOME/<проекты>" "$HOME/vault/tasks" -maxdepth 4 \
     \( -name 'CHECKPOINT.md' -o -name '*STATE*.md' \) \
     -newermt "$FROM" ! -newermt "$TO" 2>/dev/null | head -15 | sed 's|^|  |'

echo
echo "### ИЗМЕНЕНИЯ ВНЕ GIT (конфиги, боты, ops-скрипты; кроме мусора и медиа)"
# Всё, что лежит внутри найденных репозиториев, уже посчитано коммитами выше —
# здесь только то, чего git не видит вовсе.
REPO_PRUNE=()
for repo in "${REPOS[@]}"; do REPO_PRUNE+=(-not -path "$repo/*"); done
find "$HOME" -maxdepth 3 -type f -newermt "$FROM" ! -newermt "$TO" \
     "${REPO_PRUNE[@]}" \
     -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.cache/*' \
     -not -path '*/venv/*' -not -path '*/.nvm/*' -not -path '*/.bun/*' \
     -not -path "$HOME/downloads/*" -not -path "$HOME/backups/*" \
     -not -path "$HOME/.claude/*" -not -path "$HOME/.claude-tg-sessions/*" \
     -not -path "$HOME/.secrets/*" -not -path "$HOME/.config/*" -not -path "$HOME/.npm/*" \
     -not -path '*/zoom-ops/archive/*' -not -path '*/logs/*' -not -path '*/state/*' \
     ! -name '.bash_history' ! -name '.claude.json' \
     ! -name '*.log' ! -name '*.db*' ! -name '*.pyc' ! -name '*.json.backup*' \
     ! -name '*.lock' ! -name '.*.lock' ! -name '*.sqlite*' \
     2>/dev/null | sed "s|^$HOME/||" | head -40
# Из кухни Claude Code берём только смысловое: рабочее пространство штаба, скиллы, хуки, настройки.
find "$HOME/.claude/workspace" "$HOME/.claude/skills" "$HOME/.claude/hooks" \
     "$HOME/.claude/settings.json" \
     -maxdepth 2 -type f -newermt "$FROM" ! -newermt "$TO" \
     ! -name '*.log' ! -name '*.lock' 2>/dev/null | sed "s|^$HOME/||" | head -20

echo
echo "### ВХОДЯЩИЕ ДОКУМЕНТЫ ЗА ПЕРИОД (календари, ТЗ, замечания)"
find "$HOME/downloads" -maxdepth 1 -type f \( -name '*.docx' -o -name '*.md' -o -name '*.pdf' \) \
     -newermt "$FROM" ! -newermt "$TO" 2>/dev/null | head -15

echo
echo "==================== КОНЕЦ ФАКТУРЫ ===================="
echo "Дальше: цифры и объёмы подтверждать в ops-доках и STATE, а не выводить из формулировок коммитов."

#!/usr/bin/env bash
# Upsert блока в очередь решений CEO. Использование:
#   decision-queue-upsert.sh <id> <заголовок> <текст-тела (многострочный одним аргументом)>
# Один id = один блок: существующий блок с этим id заменяется. flock от гонок.
set -uo pipefail
Q="$HOME/.claude/workspace/DECISIONS.md"
ID="${1:?id}"; TITLE="${2:?title}"; BODY="${3:-}"
exec 8>>"$Q.lock"
flock 8
ID="$ID" TITLE="$TITLE" BODY="$BODY" Q="$Q" python3 - <<'PY'
import os, re, datetime
q = os.environ['Q']; iid = os.environ['ID']; title = os.environ['TITLE']; body = os.environ['BODY']
t = open(q, encoding='utf-8').read() if os.path.exists(q) else "# DECISIONS — очередь решений владельца\n"
# выпилить существующий блок этого id (до следующего '## [' или конца)
t = re.sub(r'\n## \[' + re.escape(iid) + r'\][^\n]*\n(?:(?!## \[).*\n?)*', '\n', t)
block = f"\n## [{iid}] {datetime.date.today().isoformat()} — {title}\n{body.rstrip()}\n"
open(q, 'w', encoding='utf-8').write(t.rstrip() + '\n' + block)
PY
rm -f "$Q.lock"

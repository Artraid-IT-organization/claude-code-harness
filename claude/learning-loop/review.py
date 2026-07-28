#!/usr/bin/env python3
# review.py — СБОРЩИК материала для Learning Review Session (READ-ONLY, ничего не пишет).
# Собирает за окно --since: журнал Stop-hook (sessions.jsonl), fail/blocked-трейсы из loop.py-БД,
# существующие уроки (для duplicate-check). Выводит структурированный бандл, который читает агент
# в /learning-review и предлагает КАНДИДАТЫ в уроки. Запись — только после OK CEO (loop.py add-lesson).
import argparse, json, os, re, sqlite3, sys, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "ll.sqlite")
JOURNAL = os.path.join(HERE, "sessions.jsonl")


def parse_since(s):
    m = re.match(r"^(\d+)\s*([hHdD])$", (s or "24h").strip())
    if not m:
        return 24 * 3600
    n, unit = int(m.group(1)), m.group(2).lower()
    return n * (3600 if unit == "h" else 86400)


def iso_cutoff(seconds):
    t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=seconds)
    return t.strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="24h", help="окно: 24h / 48h / 2d (default 24h)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    cutoff = iso_cutoff(parse_since(args.since))

    sessions = []
    if os.path.isfile(JOURNAL):
        for line in open(JOURNAL, encoding="utf-8"):
            try:
                r = json.loads(line)
            except Exception:
                continue
            if (r.get("ts") or "") >= cutoff:
                sessions.append(r)

    traces, lessons = [], []
    if os.path.isfile(DB):
        conn = sqlite3.connect(DB)
        conn.row_factory = sqlite3.Row
        try:
            traces = [dict(x) for x in conn.execute(
                "SELECT t.run_id,t.agent,t.task_kind,t.domain_keys,t.outcome,t.error_class,"
                "t.input_redacted,t.output_redacted,t.created_at,e.verdict,e.reason,e.invariant_id "
                "FROM traces t LEFT JOIN evals e ON e.run_id=t.run_id "
                "WHERE t.created_at>=? AND (t.outcome IN ('fail','blocked','partial') OR e.verdict='fail') "
                "ORDER BY t.created_at DESC", (cutoff,)).fetchall()]
        except Exception:
            traces = []
        try:
            lessons = [dict(x) for x in conn.execute(
                "SELECT lesson_id,title,scope,scope_tag,trust,task_kind,support_count,updated_at "
                "FROM lessons ORDER BY updated_at DESC").fetchall()]
        except Exception:
            lessons = []
        conn.close()

    bundle = {"since": args.since, "cutoff_utc": cutoff,
              "sessions": sessions, "fail_traces": traces, "existing_lessons": lessons}

    if args.json:
        print(json.dumps(bundle, ensure_ascii=False, indent=1))
        return 0

    print("=" * 70)
    print("LEARNING REVIEW — материал за %s (cutoff %s)" % (args.since, cutoff))
    print("=" * 70)
    print("\n## СЕССИИ (журнал Stop-hook, %d) — транскрипты для анализа:" % len(sessions))
    for s in sessions:
        print("  - %s  cwd=%s\n    transcript=%s" % (s.get("ts"), s.get("cwd"), s.get("transcript")))
    if not sessions:
        print("  (нет записей; журнал наполнится со следующих сессий через Stop-hook)")
    print("\n## FAIL/BLOCKED-ТРЕЙСЫ из петли (%d):" % len(traces))
    for t in traces:
        print("  - [%s/%s] kind=%s domain=%s\n    error=%s reason=%s inv=%s"
              % (t.get("outcome"), t.get("verdict"), t.get("task_kind"), t.get("domain_keys"),
                 t.get("error_class"), t.get("reason"), t.get("invariant_id")))
    if not traces:
        print("  (нет — захват урока: loop.py record-trace --outcome fail ...)")
    print("\n## СУЩЕСТВУЮЩИЕ УРОКИ (%d) — для duplicate-check:" % len(lessons))
    for l in lessons:
        print("  - id=%s [%s/%s] %s :: %s" % (l.get("lesson_id"), l.get("trust"),
              l.get("scope_tag"), l.get("task_kind"), l.get("title")))
    print("\n" + "=" * 70)
    print("ДАЛЕЕ (агент): прочитай транскрипты сессий, найди реальные уроки, выдай КАНДИДАТЫ")
    print("в формате RUNBOOK. НИЧЕГО не пиши до OK CEO. Анти-загрязнение: не сохранять разовое/")
    print("очевидное/«будь внимательнее»/неподтверждённые гипотезы/длинные рассуждения/то, что уже")
    print("в CLAUDE.md/agent.md/INVARIANTS.md. Запись только: loop.py add-lesson после одобрения.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

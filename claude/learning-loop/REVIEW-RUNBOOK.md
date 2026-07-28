<!-- updated: 2026-06-27 -->
# Learning Review — RUNBOOK

Ручной human-in-the-loop разбор накопленных логов петли обучения. Цель: агент **предлагает**
кандидаты в уроки, а в постоянную память пишется **только утверждённое тобой**. Никакой авто-записи.

Каденс — на твоё усмотрение: 1–2 раза в день или раз в два дня. Это ручной запуск, не cron.

---

## 1. Как запускать review-сессию

**Вариант A (рекомендуется) — слэш-команда в Claude Code:**
```
/learning-review --since 24h
```
(или `--since 48h` / `--since 2d`; без аргумента — 24h). Агент: соберёт материал → прочитает
транскрипты → выдаст КАНДИДАТЫ → дождётся твоего решения по каждому → запишет только одобренные.

**Вариант B — только собрать материал (без агента), глазами:**
```
~/.claude/learning-loop/review.sh --since 24h
```
Печатает журнал сессий, fail-трейсы и существующие уроки. Ничего не пишет (dry-run).

**Твои ответы по каждому кандидату:** `OK` · `NO` · `EDIT: …` · `MERGE WITH: <id>` · `LOWER SCOPE` · `DELETE OLD`.

---

## 2. Где что лежит

| Что | Путь |
|---|---|
| Журнал сессий (Stop-hook) | `~/.claude/learning-loop/sessions.jsonl` |
| Трейсы/оценки/УРОКИ (БД) | `~/.claude/learning-loop/ll.sqlite` |
| **Утверждённая память (уроки)** | таблица `lessons` в `ll.sqlite`, `trust IN (verified,adopted)` |
| Движок | `~/.claude/learning-loop/loop.py` |
| Сборщик review | `~/.claude/learning-loop/review.py` / `review.sh` |
| Слэш-команда | `~/.claude/commands/learning-review.md` |
| Хуки (recall/record/agent.md) | `~/.claude/hooks/*.sh`, включены в `~/.claude/settings.json` |
| Правила поведения | `~/CLAUDE.md` (секция «Само-дисциплина») |

**Что реально инъектируется в новую сессию:** только `trust=verified/adopted` (approved). `proposed`
(авто-дистиллированные кандидаты) в recall НЕ попадают — они ждут review. Scope: `global` видны
везде, `crm`/`bi`/`<repo>` — только в своём проекте (по cwd).

---

## 3. Откат ошибочно добавленного урока

```
# найти id
python3 ~/.claude/learning-loop/loop.py digest --scope-tag <global|crm|bi> --json
# мягко (исключить из recall, но оставить след)
python3 ~/.claude/learning-loop/loop.py promote --lesson-id <id> --to deprecated
# жёстко (удалить совсем)
python3 ~/.claude/learning-loop/loop.py delete-lesson --lesson-id <id>
```

## 4. Проверить, что следующая сессия получила новые уроки

```
# что увидит recall в CRM-контексте (то же, что инъектирует SessionStart-хук):
python3 ~/.claude/learning-loop/loop.py digest --scope-tag crm
# или вручную прогнать сам хук:
echo '{"cwd":"$HOME/<проект>"}' | ~/.claude/hooks/loop-recall.sh
```
В НОВОЙ сессии Claude Code в начале контекста появится блок «УРОКИ ПРОШЛЫХ СЕССИЙ …».
Если пусто — значит approved-уроков для этого scope нет (только proposed-кандидаты, ждущие review).

---

## 5. Анти-загрязнение памяти (агент соблюдает на этапе предложения)
НЕ сохранять: одноразовое ситуативное · очевидные правила · «будь внимательнее» ·
неподтверждённые гипотезы · длинные рассуждения · то, что уже в CLAUDE.md/agent.md/INVARIANTS.md.
Уроки — короткие (1–3 предложения), с датой и source-id, без PII (маскируется автоматически),
без дублей (dedup по scope+title).

## 6. Поток данных
```
работа агента ──(Stop-hook)──▶ sessions.jsonl ──┐
ошибки/правки ─(record-trace)▶ traces+evals ────┼─▶  /learning-review  ──(кандидаты)──▶ CEO
                                                 │         (review.py)                     │OK
                                                 ▼                                          ▼
                                          existing lessons ◀───────────── add-lesson (approved) 
                                                 │
                              SessionStart-hook (recall approved, scope-aware) ──▶ контекст новой сессии
```

---

## 7. Жизненный цикл знания (applicability + half-life) — добавлено 27.06.26

У каждого урока два управляющих поля:
- **applicability** — области: `Global / Architecture / CRM / BI / Bash / Claude Code / Python / Security…` (через запятую).
- **half-life** — срок жизни: `permanent` (вечное правило, не стареет) · `long` (стабильное, пересмотр ~180д) · `temporary` (факт/feature-flag, ~30д) · плюс `last_verified` (дата последней проверки).

**Маршрутизация recall (что инъектируется в сессию):** универсальные области (`global/bash/tooling/shell/security/python/architecture/claude-code/agent`) видны в ЛЮБОМ проекте; проектные (`crm/bi`) — только в своём cwd. Так знание про bash приходит везде, а CRM-специфика не шумит в BI.

**Пересмотр устаревающих (анти-захламление):**
```
python3 ~/.claude/learning-loop/loop.py review-due           # что пора перепроверить (temporary>30д / long>180д)
python3 ~/.claude/learning-loop/loop.py verify-lesson --lesson-id N   # актуален → обновить last_verified
python3 ~/.claude/learning-loop/loop.py promote --lesson-id N --to deprecated  # устарел → убрать из recall
```
`/learning-review` теперь начинается с Шага 0 (review-due) — каждая ручная сессия пересматривает стареющие знания.

**Дисциплина отбора:** в долгую память — знание, полезное через полгода (permanent/long). Транзитные факты (`temporary`) сохранять только если несут долгую ценность; иначе не предлагать. Вечное правило ≠ наблюдение одной сессии.

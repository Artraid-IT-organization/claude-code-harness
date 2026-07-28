---
description: Ручная review-сессия петли обучения — предложить кандидаты в уроки, записать только утверждённые
---

# Learning Review Session (human-in-the-loop, dry-run по умолчанию)

Аргументы (окно): `$ARGUMENTS` (например `--since 24h` / `--since 48h` / `--since 2d`; по умолчанию 24h).

Выполни СТРОГО по шагам. **НИЧЕГО не записывай в память на этапе предложения. Запись — только после явного OK владельца по каждому кандидату.**

## Шаг 0. Пересмотр устаревающих знаний (жизненный цикл)
Запусти: `python3 ~/.claude/learning-loop/loop.py review-due`
Покажет уроки, которым пора перепроверка (temporary >30д / long >180д; permanent не стареют). По каждому спроси владельца:
- актуален → `loop.py verify-lesson --lesson-id N` (обновит last_verified);
- устарел → `loop.py promote --lesson-id N --to deprecated` (уберёт из recall);
- изменился → `EDIT` (deprecate старый + add-lesson новый).
Это не даёт памяти захламиться устаревшими наблюдениями.

## Шаг 1. Собрать материал (read-only)
Запусти: `~/.claude/learning-loop/review.sh $ARGUMENTS`
Это выведет: журнал сессий (Stop-hook) с путями транскриптов, fail/blocked-трейсы петли, существующие уроки (для duplicate-check).

## Шаг 2. Проанализировать
Прочитай перечисленные транскрипты сессий и трейсы. Ищи РЕАЛЬНЫЕ уроки:
- где владелец поправил агента;
- где агент нарушил инвариант / неверно понял архитектуру / полез не туда / повторил старую ошибку;
- полезный подтверждённый паттерн, который стоит закрепить.

## Шаг 3. Анти-загрязнение (фильтр ДО предложения) — НЕ предлагать:
- одноразовые ситуативные выводы; очевидные правила; «будь внимательнее»;
- неподтверждённые гипотезы; длинные рассуждения;
- то, что уже есть в CLAUDE.md / agent.md / INVARIANTS.md / памяти (сверь по списку existing_lessons и по доке).
- **Фильтр Expected reuse:** честно оцени, сколько раз знание реально пригодится. Low (<5 применений/год) → как правило НЕ в постоянную память (разовое — не урок). В память пускать Medium (5–20) и High (>20). Этот фильтр главная защита от разрастания памяти.

## Шаг 4. Выдать КАНДИДАТЫ (только текст в чат, без записи)
По каждому — коротко, обязательные поля:
- **title** (кратко);
- **source/session** (id/ts/транскрипт);
- **observed mistake / useful pattern**;
- **proposed memory text** (1–3 предложения, без PII);
- **scope**: global / crm / bi / agent / bash / `<repo>`;
- **applicability** (области, через запятую): Global / Architecture / CRM / BI / Bash / Claude Code / Python / Security…;
- **half-life**: permanent (вечное правило) / long (стабильное, пересмотр ~180д) / temporary (факт/флаг, ~30д);
- **confidence**: low / medium / high;
- **expected reuse**: High (>20 применений) / Medium (5–20) / Low (<5). Если честно Low — кандидат, скорее всего, не должен жить в постоянной памяти вообще; не предлагать без явной долгой ценности;
- **duplicate check**: есть ли близкий существующий урок (id) → предложить MERGE;
- **почему стоит сохранять** (одна фраза). НЕ предлагать temporary-факты, которые устареют через месяц, если они не несут долгой ценности.
Пронумеруй кандидаты. Затем СТОП — жди ответа.

## Шаг 5. Реакция владельца (по каждому)
- **OK** — записать как есть;
- **NO** — отклонить;
- **EDIT: …** — записать в его редакции;
- **MERGE WITH: <id>** — объединить с существующим;
- **LOWER SCOPE** — сделать проектным, не глобальным;
- **DELETE OLD** — удалить устаревший урок.

## Шаг 6. Запись ТОЛЬКО утверждённого
- OK / EDIT → `python3 ~/.claude/learning-loop/loop.py add-lesson --title "…" --body "…" --scope-tag <global|crm|bi|agent|bash|repo> --applicability "Global,Architecture|CRM|Bash|Security…" --half-life <permanent|long|temporary> --task-kind <kind> --source "<session-id/ts>" --severity <low|medium|high|critical>` (PII маскируется; dedup по scope+title; trust=adopted; last_verified=сегодня).
- MERGE WITH → тот же add-lesson с тем же title/scope (сработает dedup → support+1) ИЛИ вручную инкремент существующего.
- LOWER SCOPE → add-lesson с `--scope-tag <repo>` вместо global.
- DELETE OLD → `python3 ~/.claude/learning-loop/loop.py delete-lesson --lesson-id <id>`.
Записывай КОРОТКО, с датой и source-id. После записи покажи итог (`loop.py digest --scope-tag <scope>`), чтобы подтвердить, что урок попал в approved-память.

Помни: на этапе 1–4 запись запрещена. Только Шаг 6 пишет, и только по утверждённым.

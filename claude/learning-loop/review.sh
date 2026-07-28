#!/usr/bin/env bash
# Learning Review — сборщик материала для ручной review-сессии (READ-ONLY, dry-run по сути:
# НИЧЕГО не пишет в память). Печатает журнал сессий + fail-трейсы + существующие уроки.
# Запуск:  ~/.claude/learning-loop/review.sh --since 24h    (или 48h / 2d)
# Запись утверждённых уроков — отдельно, командой loop.py add-lesson ПОСЛЕ одобрения CEO.
exec python3 "$HOME/.claude/learning-loop/review.py" "$@"

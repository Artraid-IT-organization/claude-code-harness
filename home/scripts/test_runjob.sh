#!/usr/bin/env bash
# Селфтест runjob.sh — проверка ПОВЕДЕНИЕМ, ассерты равенством.
set -uo pipefail
T=$(mktemp -d)
export RUNJOB_HOME="$T/state"
R="$HOME/scripts/runjob.sh"
PASS=0; FAIL=0
ok()  { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS $1 ($2)"; else FAIL=$((FAIL+1)); echo "  FAIL $1: ожидалось «$3», получено «$2»"; fi; }

mkdir -p "$T/out"
# обработчик: делает файл-результат; ключи с 'bad' всегда падают
cat > "$T/handler.sh" <<'EOF'
#!/usr/bin/env bash
key="$1"; out="$2"
case "$key" in *bad*) exit 1;; esac
echo "result of $key" > "$out/$key.done"
EOF
chmod +x "$T/handler.sh"

echo "=== ТЕСТ 1: базовый прогон, часть падает ==="
for i in 1 2 3 4 5; do echo "item$i"; done > "$T/items.txt"
echo "bad1" >> "$T/items.txt"
bash "$R" run t1 --items "$T/items.txt" --done "$T/out/{}.done" \
     --cmd "$T/handler.sh {} $T/out" --workers 3 --waves 4 --retry 2 > "$T/t1.log" 2>&1
ok "успешных результатов" "$(ls "$T/out"/*.done 2>/dev/null | wc -l)" "5"
ok "финал честный (с ошибками)" "$(grep -c 'ЗАВЕРШЕНО С ОШИБКАМИ' "$RUNJOB_HOME/t1/STATUS")" "1"
ok "проваленный зафиксирован" "$(sort -u "$RUNJOB_HOME/t1/failed.txt" | wc -l)" "1"

echo "=== ТЕСТ 2: идемпотентность — повтор не переделывает ==="
touch -d '2020-01-01' "$T/out/item1.done"
bash "$R" run t2 --items "$T/items.txt" --done "$T/out/{}.done" \
     --cmd "$T/handler.sh {} $T/out" --workers 3 --waves 2 --retry 1 > "$T/t2.log" 2>&1
ok "item1 не перезаписан" "$(date -r "$T/out/item1.done" +%Y)" "2020"

echo "=== ТЕСТ 3: ГЛАВНЫЙ — работы, добавленные ПО ХОДУ, подхватываются ==="
rm -rf "$T/out2"; mkdir -p "$T/out2"
seq 1 4 | sed 's/^/slow/' > "$T/items2.txt"
cat > "$T/slow.sh" <<'EOF'
#!/usr/bin/env bash
sleep 1; echo done > "$2/$1.done"
EOF
chmod +x "$T/slow.sh"
( sleep 3; seq 5 8 | sed 's/^/slow/' >> "$T/items2.txt" ) &   # дописываем список в процессе
bash "$R" run t3 --items "$T/items2.txt" --done "$T/out2/{}.done" \
     --cmd "$T/slow.sh {} $T/out2" --workers 2 --waves 10 --settle 5 > "$T/t3.log" 2>&1
wait
ok "подхвачены все 8 (4 исходных + 4 дописанных)" "$(ls "$T/out2"/*.done 2>/dev/null | wc -l)" "8"
ok "фаза ЗАВЕРШЕНО" "$(grep -c 'ЗАВЕРШЕНО' "$RUNJOB_HOME/t3/STATUS")" "1"

echo "=== ТЕСТ 4: STATUS отвечает на «как дела» ==="
ok "есть время последнего успеха" "$(grep -c 'последний успех' "$RUNJOB_HOME/t3/STATUS")" "1"
ok "status по имени работает" "$(bash "$R" status t3 | grep -c 'задание:')" "1"
ok "list видит задания" "$(bash "$R" list | wc -l)" "3"

echo
echo "ИТОГ: PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ] && rm -rf "$T"
exit $FAIL

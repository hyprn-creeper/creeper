#!/bin/bash
# Автотесты creeper на подставной системе (CREEPER_ROOT). Запуск: bash creeper-tests.sh
C=${C:-$(cd "$(dirname "$0")/.." && pwd)/creeper}
R=/tmp/ctest; REPO=/tmp/ctest-repo; MK=/tmp/ctest-mk
export CREEPER_ROOT=$R
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \e[32mOK\e[0m   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \e[31mFAIL\e[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/         /' | head -n 15; }
check(){ local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
run()  { OUT=$("$C" "$@" 2>&1 </dev/null); RC=$?; }

# zstd-заглушка на gzip (в песочнице нет zstd)
if ! command -v zstd >/dev/null || [ -n "${FAKEZSTD:-}" ]; then
  mkdir -p /tmp/ctest-bin
  printf '#!/bin/sh\ncase " $* " in *" -d "*|*" -dc "*) exec gzip -dc;; *) exec gzip -c;; esac\n' > /tmp/ctest-bin/zstd
  chmod +x /tmp/ctest-bin/zstd; export PATH=/tmp/ctest-bin:$PATH
fi

reset_root() {
  rm -rf "$R" "$REPO" "$MK"; mkdir -p "$R"/usr/{bin,lib} "$R"/etc "$R"/run "$R"/var/lib/creeper/recipes "$R"/var/cache/creeper/sources "$MK" "$REPO"
  ln -s usr/bin "$R/bin"; ln -s usr/lib "$R/lib"
  : > "$R/etc/creeper.conf"
}
# mk <имя> <версия> [доп. строка Makefile] — исходник с файлами (включая файл с пробелом)
mk() {
  local d=$MK/$1-$2; rm -rf "$d"; mkdir -p "$d"
  printf 'all:\n\t@echo building %s; sleep 1\ninstall:\n\tmkdir -p $(DESTDIR)/bin $(DESTDIR)/etc $(DESTDIR)/usr/share/doc/%s-%s\n\techo "#!/bin/sh" > "$(DESTDIR)/bin/%s"; echo "echo %s %s" >> "$(DESTDIR)/bin/%s"; chmod 755 "$(DESTDIR)/bin/%s"\n\techo conf=%s > "$(DESTDIR)/etc/%s.conf"\n\techo readme > "$(DESTDIR)/usr/share/doc/%s-%s/READ ME.txt"\n\techo la > "$(DESTDIR)/usr/lib/lib%s.la" || true\n\t%s\n' \
    "$1" "$1" "$2" "$1" "$1" "$2" "$1" "$1" "$2" "$1" "$1" "$2" "$1" "${3:-true}" > "$d/Makefile"
  sed -i 's#echo la > "$(DESTDIR)/usr/lib/#mkdir -p $(DESTDIR)/usr/lib; echo la > "$(DESTDIR)/usr/lib/#' "$d/Makefile"
  tar -C "$MK" -czf "$R/var/cache/creeper/sources/$1-$2.tar.gz" "$1-$2"
}
# rec <имя> <версия> "<deps>" [release]
rec() {
  mkdir -p "$R/var/lib/creeper/recipes/$1"
  cat > "$R/var/lib/creeper/recipes/$1/recipe" <<EOF
name=$1
version=$2
release=${4:-1}
desc="тест $1"
source=(http://x.invalid/$1-\$version.tar.gz)
depends=($3)
backup=(etc/$1.conf)
build()   { make; }
package() { make DESTDIR="\$PKG" install; }
EOF
}

echo "== 1. установка из исходников с зависимостями"
reset_root; mk world 1.0; mk hello 1.0; rec world 1.0 ""; rec hello 1.0 "world"
run install hello
check "install hello: код 0" [ $RC -eq 0 ]
check "оба пакета стоят" [ -x "$R/usr/bin/hello" -a -x "$R/usr/bin/world" ]
check "ссылка /bin не превратилась в каталог" [ -L "$R/bin" ]
check "hello = explicit" grep -qx explicit "$R/var/lib/creeper/installed/hello/reason"
check "world = dep" grep -qx dep "$R/var/lib/creeper/installed/world/reason"
check ".la удалены" [ ! -e "$R/usr/lib/libhello.la" ]
check "файл с пробелом установлен" [ -f "$R/usr/share/doc/hello-1.0/READ ME.txt" ]
check "бинарники в кэше" [ -s "$R/var/cache/creeper/bin/hello-1.0-1.tar.zst" -a -s "$R/var/cache/creeper/bin/world-1.0-1.tar.zst" ]
check "sha256 записаны" [ -s "$R/var/lib/creeper/installed/hello/sha256" ]
check "история пишется" grep -q 'install hello-1.0-1' "$R/var/log/creeper/history.log"
run list; check "list помечает зависимость" grep -q 'world.*(зависимость)' <<<"$OUT"

echo "== 2. verify"
run verify; check "verify: всё цело" [ $RC -eq 0 ]
: > "$R/usr/bin/hello"                              # «пустой файл после зависания»
rm -f "$R/usr/share/doc/world-1.0/READ ME.txt"
run verify; check "verify ловит испорченный и пропавший файлы" [ $RC -ne 0 ]
check "verify называет hello" grep -q hello <<<"$OUT"
check "verify называет world" grep -q world <<<"$OUT"
run install hello --rebuild; check "починка через --rebuild" [ $RC -eq 0 ]
check "после починки hello не пустой" [ -s "$R/usr/bin/hello" ]

echo "== 3. owns / files / info / deps / search"
run owns /bin/hello; check "owns /bin/hello → hello" grep -q 'пакету.*hello' <<<"$OUT"
run owns "/usr/share/doc/hello-1.0/READ ME.txt"; check "owns для пути с пробелом" grep -q 'hello' <<<"$OUT"
run files hello; check "files" grep -q '/usr/bin/hello' <<<"$OUT"
run info world; check "info: нужен для hello" grep -q 'нужен для:   hello' <<<"$OUT"
run deps hello; check "deps дерево" grep -q 'world' <<<"$OUT"
run search hel; check "search фильтрует" bash -c "grep -q hello <<<\"\$0\" && ! grep -q world <<<\"\$0\"" "$OUT"

echo "== 4. конфликт файлов"
mk evil 1.0 'install -Dm755 /dev/null $(DESTDIR)/usr/bin/hello'; rec evil 1.0 ""
run install evil; check "конфликт обнаружен" bash -c "[ $RC -ne 0 ] && grep -q 'пакет hello' <<<\"\$0\"" "$OUT"
check "чужой файл не тронут" [ -s "$R/usr/bin/hello" ]

echo "== 5. конфиги при обновлении"
echo mine > "$R/etc/hello.conf"
mk hello 1.1; rec hello 1.1 "world"
run upgrade; check "upgrade прошёл" [ $RC -eq 0 ]
check "свой конфиг сохранён" grep -qx mine "$R/etc/hello.conf"
check "новый конфиг рядом" [ -f "$R/etc/hello.conf.creeper-new" ]
check "старая документация убрана" [ ! -e "$R/usr/share/doc/hello-1.0" ]
check "новая документация есть" [ -d "$R/usr/share/doc/hello-1.1" ]
check "verify не ругается на свой конфиг" "$C" verify hello

echo "== 6. upgrade добавляет новую зависимость"
mk extra 1.0; rec extra 1.0 ""
mk hello 1.2; rec hello 1.2 "world extra"
run upgrade; check "upgrade с новой зависимостью" [ $RC -eq 0 ]
check "extra поставлен" [ -x "$R/usr/bin/extra" ]
check "extra = dep" grep -qx dep "$R/var/lib/creeper/installed/extra/reason"

echo "== 7. blow: порядок, отказ, подтверждение не мешает в скриптах"
run blow world; check "нельзя взорвать нужное" [ $RC -ne 0 ]
run blow world extra hello -y; check "blow набора в любом порядке" [ $RC -eq 0 ]
check "всё удалено" [ ! -e "$R/usr/bin/hello" -a ! -e "$R/usr/bin/world" -a ! -e "$R/usr/bin/extra" ]
check "конфиги сохранены без --purge" [ -f "$R/etc/world.conf" ]
check "/usr/lib на месте (защита)" [ -d "$R/usr/lib" ]

echo "== 8. orphans / autoremove"
run install hello                    # из кэша
check "повторная установка из кэша" grep -q 'кэш' <<<"$OUT"
run blow hello -y
run orphans; check "orphans: world и extra" bash -c "grep -q world <<<\"\$0\" && grep -q extra <<<\"\$0\"" "$OUT"
run autoremove -y; check "autoremove" [ ! -e "$R/usr/bin/world" -a ! -e "$R/usr/bin/extra" ]
run orphans; check "больше сирот нет" grep -q 'нет' <<<"$OUT"

echo "== 9. репозиторий бинарников (file://)"
cp "$R"/var/cache/creeper/bin/*.tar.zst "$REPO/"
"$C" index > "$REPO/index.txt"
check "index.txt не пустой" [ -s "$REPO/index.txt" ]
rm -rf "$R/var/cache/creeper/bin"
echo "BINREPO=file://$REPO" > "$R/etc/creeper.conf"
run fetch hello; check "fetch скачал бинарники" [ -s "$R/var/cache/creeper/bin/hello-1.2-1.tar.zst" ]
check "fetch не установил" [ ! -e "$R/usr/bin/hello" ]
run install hello; check "install из репозитория" bash -c "[ $RC -eq 0 ] && grep -q 'скачать\|кэш' <<<\"\$0\"" "$OUT"
check "hello работает" [ -x "$R/usr/bin/hello" ]
run install hello --rebuild; check "--rebuild собирает из исходников" grep -q 'сборка' <<<"$OUT"
# испорченный бинарник в репозитории
rm -rf "$R/var/cache/creeper/bin"; "$C" blow hello -y >/dev/null 2>&1
echo junk >> "$REPO/hello-1.2-1.tar.zst"
run install hello; check "испорченный бинарник отвергнут" bash -c "[ $RC -ne 0 ] && grep -q 'сумма' <<<\"\$0\"" "$OUT"
# недоступный репозиторий: откат на сборку
echo "BINREPO=file:///nonexistent" > "$R/etc/creeper.conf"; rm -f "$R/var/tmp/creeper/index.txt"
run install hello; check "без репозитория — сборка" bash -c "[ $RC -eq 0 ] && grep -q 'сборка' <<<\"\$0\"" "$OUT"

echo "== 10. sync и self-update"
mkdir -p "$REPO/stage/recipes"; cp -r "$R"/var/lib/creeper/recipes/* "$REPO/stage/recipes/"
mkdir -p "$REPO/stage/recipes/newpkg"; printf 'name=newpkg\nversion=1\nsource=()\n' > "$REPO/stage/recipes/newpkg/recipe"
tar -C "$REPO/stage" -czf "$REPO/recipes.tar.gz" recipes
cp "$C" /tmp/ctest-creeper-new; sed -i 's/^CREEPER_VERSION=.*/CREEPER_VERSION=9.9/' /tmp/ctest-creeper-new
cp /tmp/ctest-creeper-new "$REPO/creeper"; echo "9.9 $(sha256sum "$REPO/creeper" | cut -d' ' -f1)" > "$REPO/creeper.version"
echo "BINREPO=file://$REPO" > "$R/etc/creeper.conf"
run sync; check "sync: 1 новый рецепт" grep -q 'новых 1' <<<"$OUT"
check "sync сообщает о новом creeper" grep -q 'creeper 9.9' <<<"$OUT"
cp "$C" /tmp/ctest-self; chmod +x /tmp/ctest-self
OUT=$(/tmp/ctest-self self-update 2>&1); check "self-update до 9.9" bash -c "grep -q '9.9' <<<\"\$0\" && grep -q '^CREEPER_VERSION=9.9' /tmp/ctest-self" "$OUT"
echo "9.10 0000000000000000000000000000000000000000000000000000000000000000" > "$REPO/creeper.version"
OUT=$(/tmp/ctest-self self-update 2>&1); check "self-update отвергает чужую сумму" grep -q 'не совпала' <<<"$OUT"

echo "== 11. clean, new, history, ошибки рецептов"
mkdir -p "$R/var/tmp/creeper/junk"; touch "$R/var/cache/creeper/sources/old-0.1.tar.gz"
run clean --all; check "clean --all" [ ! -e "$R/var/cache/creeper/sources/old-0.1.tar.gz" -a ! -e "$R/var/tmp/creeper/junk" ]
check "исходник установленного пакета сохранён" [ -e "$R/var/cache/creeper/sources/hello-1.2.tar.gz" ]
OUT=$(cd /tmp && rm -rf /tmp/libfoo && RECIPES_OUT=/tmp "$C" new https://example.org/dl/libfoo-2.4.1.tar.xz 2>&1)
check "new: заготовка" grep -q 'version=2.4.1' /tmp/libfoo/recipe
check "new: \$version в ссылке" grep -q 'libfoo-\$version.tar.xz' /tmp/libfoo/recipe
check "new: заготовка — корректный bash" bash -n /tmp/libfoo/recipe
run history; check "history" grep -q 'blow' <<<"$OUT"
mkdir -p "$R/var/lib/creeper/recipes/broken"; printf 'name=broken\nversion=1\nbuild() { make\n' > "$R/var/lib/creeper/recipes/broken/recipe"
run install broken; check "сломанный рецепт — понятная ошибка" grep -q 'с ошибкой' <<<"$OUT"
run install nosuch; check "нет рецепта — подсказка" grep -q 'creeper search' <<<"$OUT"
run frobnicate; check "неизвестная команда — код ≠ 0" [ $RC -ne 0 ]

echo "== 12. сбой сборки"
mk failpkg 1.0 'false'; rec failpkg 1.0 ""
run install failpkg; check "сбой сборки: код ≠ 0 и путь к логу" bash -c "[ $RC -ne 0 ] && grep -q 'creeper log failpkg' <<<\"\$0\"" "$OUT"
check "после сбоя ничего не установлено" [ ! -e "$R/var/lib/creeper/installed/failpkg" ]
check "сбой записан в историю" grep -q 'FAIL failpkg' "$R/var/log/creeper/history.log"

echo "== 13. потоки"
echo 'MAKEFLAGS="-j3"' > "$R/etc/creeper.conf"; run help; check "MAKEFLAGS=-j3 → 3 потока" grep -q 'Потоки сборки: 3' <<<"$OUT"
echo 'CREEPER_JOBS=2' > "$R/etc/creeper.conf"; run help; check "CREEPER_JOBS=2" grep -q 'Потоки сборки: 2' <<<"$OUT"

echo "== 14. --reinstall из кэша"
echo "" > "$R/etc/creeper.conf"; "$C" install hello >/dev/null 2>&1
: > "$R/usr/bin/hello"
run install hello --reinstall; check "--reinstall берёт кэш" grep -q 'кэш' <<<"$OUT"
check "после --reinstall файл цел" [ -s "$R/usr/bin/hello" ]
run install hello; check "без ключа — уже установлен" grep -q 'уже установлен' <<<"$OUT"

echo "== 15. creeper farm (подставной GitHub API)"
MOCK=$(cd "$(dirname "$0")" && pwd)/mock_github.py
reset_root; mk world 1.0; mk hello 1.0; rec world 1.0 ""; rec hello 1.0 "world"
"$C" install hello >/dev/null 2>&1
READY=/tmp/ctest-ready; rm -rf "$READY"; mkdir -p "$READY"; cp "$R"/var/cache/creeper/bin/*.tar.zst "$READY/"
"$C" blow hello world -y >/dev/null 2>&1; rm -rf "$R/var/cache/creeper/bin"
mkdir -p "$REPO/st"; cp -r "$R/var/lib/creeper/recipes" "$REPO/st/"; tar -C "$REPO/st" -czf "$REPO/recipes.tar.gz" recipes
: > "$REPO/index.txt"
cat > "$R/etc/creeper.conf" <<EOF
BINREPO=file://$REPO
FARM_REPO=me/creeper
FARM_API=http://127.0.0.1:18080
FARM_POLL=1
EOF
start_mock() { pkill -f "mock_github.py 18080" 2>/dev/null; sleep 0.3; python3 "$MOCK" 18080 tok123 "$REPO" "$READY" "$@" & MOCKPID=$!; sleep 1; }
start_mock
run farm build hello; check "без токена — подсказка" grep -q 'farm token' <<<"$OUT"
OUT=$(printf 'badtoken\n' | "$C" farm token 2>&1); check "неверный токен отвергнут" grep -q 'не принят' <<<"$OUT"
OUT=$(printf 'tok123\n' | "$C" farm token 2>&1); check "токен сохранён" grep -q 'запись есть' <<<"$OUT"
check "файл токена только для root" [ "$(stat -c %a "$R/etc/creeper/github-token")" = 600 ]
check "токен не в аргументах curl" bash -c "! grep -q 'Bearer' <<<\"\$(declare -f)\""
run farm build hello
check "farm build: код 0" [ $RC -eq 0 ]
check "рецепты отправлены (hello и world)" bash -c "grep -q 'рецепт hello-1.0 отправлен' <<<\"\$0\" && grep -q 'рецепт world-1.0 отправлен' <<<\"\$0\"" "$OUT"
check "ферма собрала" grep -q 'ферма собрала' <<<"$OUT"
check "поставлено с фермы" grep -q 'скачать' <<<"$OUT"
check "hello стоит" [ -x "$R/usr/bin/hello" ]
"$C" blow hello world -y >/dev/null 2>&1
run farm build hello
check "повторно рецепты не отправляются" bash -c "! grep -q 'отправлен' <<<\"\$0\"" "$OUT"
run farm status; check "farm status показывает запуски" grep -q 'build: hello' <<<"$OUT"
mkdir -p /tmp/ctest-newrec; printf 'name=newpkg\nversion=2.0\nsource=()\nbuild(){ :; }\n' > /tmp/ctest-newrec/recipe
run farm send /tmp/ctest-newrec/recipe; check "farm send файла" grep -q 'newpkg-2.0 отправлен' <<<"$OUT"
check "рецепт скопирован себе" [ -f "$R/var/lib/creeper/recipes/newpkg/recipe" ]
start_mock fail
mk extra 1.0; rec extra 1.0 ""
run farm build extra
check "сбой фермы: код ≠ 0" [ $RC -ne 0 ]
check "сбой фермы: выдержка из лога" grep -q "шаг 'build' упал" <<<"$OUT"
check "сбой фермы: ссылка на лог" grep -q 'весь лог' <<<"$OUT"
run farm log; check "farm log" grep -q 'xx>' <<<"$OUT"
run farm build 'bad;name'; check "плохое имя отвергнуто" grep -q 'плохое имя' <<<"$OUT"
kill $MOCKPID 2>/dev/null

echo
printf 'Итого: \e[32m%d прошло\e[0m, \e[31m%d упало\e[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

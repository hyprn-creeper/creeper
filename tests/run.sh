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
OUT=$(cd /tmp && rm -rf /tmp/libfoo && RECIPES_OUT=/tmp "$C" new https://example.org/dl/libfoo-2.4.1.tar.xz --no-download 2>&1)
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
check "рецепт сохранён как свой" [ -f "$R/var/lib/creeper/local/newpkg/recipe" ]
rm -rf /tmp/ctest-gh; mkdir -p /tmp/ctest-gh
OUT=$(RECIPES_OUT=/tmp/ctest-gh "$C" new https://github.com/pub/tool 2>&1 </dev/null)
check "new по странице GitHub: последняя версия" grep -qx 'version=2.5.1' /tmp/ctest-gh/tool/recipe
check "new по странице GitHub: ссылка на архив тега" grep -qF 'source=(tool-$version.tar.gz::https://github.com/pub/tool/archive/refs/tags/v$version.tar.gz)' /tmp/ctest-gh/tool/recipe
check "new по странице GitHub: описание и сайт" bash -c ". /tmp/ctest-gh/tool/recipe; [ \"\$desc\" = 'A tool, \"quoted\"' ] && [ \"\$url\" = https://github.com/pub/tool ]"
OUT=$(RECIPES_OUT=/tmp/ctest-gh "$C" new https://github.com/pub/tagsonly.git 2>&1 </dev/null)
check "new: без релизов берётся тег, release_3_0_2 → 3.0.2" grep -qx 'version=3.0.2' /tmp/ctest-gh/tagsonly/recipe
OUT=$(RECIPES_OUT=/tmp/ctest-gh "$C" new https://github.com/foo/Bar/archive/refs/tags/v1.4.tar.gz --no-download 2>&1 </dev/null)
check "new: ссылка на архив тега GitHub → имя-версия.tar.gz::" grep -qF 'source=(bar-$version.tar.gz::https://github.com/foo/Bar/archive/refs/tags/v$version.tar.gz)' /tmp/ctest-gh/bar/recipe
start_mock fail
mk extra 1.0; rec extra 1.0 ""
run farm build extra
check "сбой фермы: код ≠ 0" [ $RC -ne 0 ]
check "сбой фермы: выдержка из лога" grep -q "шаг 'build' упал" <<<"$OUT"
check "сбой фермы: ссылка на лог" grep -q 'весь лог' <<<"$OUT"
run farm log; check "farm log" grep -q 'xx>' <<<"$OUT"
run farm build 'bad;name'; check "плохое имя отвергнуто" grep -q 'плохое имя' <<<"$OUT"
kill $MOCKPID 2>/dev/null

echo "== 16. norepo: закрытые пакеты не попадают в index"
reset_root; mk secret 1.0; rec secret 1.0 ""; echo 'norepo=1' >> "$R/var/lib/creeper/recipes/secret/recipe"
mk hello 1.0; rec hello 1.0 ""
"$C" install secret hello >/dev/null 2>&1
check "norepo-пакет установлен" [ -x "$R/usr/bin/secret" ]
run index; check "index без norepo-пакета" bash -c "grep -q '^hello ' <<<\"\$0\" && ! grep -q '^secret ' <<<\"\$0\"" "$OUT"

echo "== 17. пакет с конфликтом не попадает в кэш бинарников"
reset_root; mk hello 1.0; rec hello 1.0 ""; "$C" install hello >/dev/null 2>&1
mk evil 1.0 'install -Dm755 /dev/null $(DESTDIR)/usr/bin/hello'; rec evil 1.0 ""
"$C" install evil >/dev/null 2>&1
check "бракованный бинарник не в кэше" [ ! -e "$R/var/cache/creeper/bin/evil-1.0-1.tar.zst" ]
run index; check "и не в индексе" bash -c "! grep -q '^evil ' <<<\"\$0\"" "$OUT"

echo "== 18. upgrade: порядок по зависимостям, hold, outdated"
reset_root; mk aaa 1.0; mk zzz 1.0; rec zzz 1.0 ""; rec aaa 1.0 "zzz"
"$C" install aaa >/dev/null 2>&1
mk aaa 2.0; mk zzz 2.0; rec zzz 2.0 ""; rec aaa 2.0 "zzz"
run outdated; check "outdated показывает оба" bash -c "grep -q 'aaa.*1.0-1 → 2.0-1' <<<\"\$0\" && grep -q 'zzz' <<<\"\$0\"" "$OUT"
run upgrade --dry-run; check "upgrade --dry-run ничего не ставит" [ "$(cat "$R/var/lib/creeper/installed/aaa/version")" = 1.0 ]
run upgrade
check "upgrade: код 0" [ $RC -eq 0 ]
check "зависимость zzz обновлена раньше aaa" bash -c "[ \$(grep -n 'install zzz-2.0' '$R/var/log/creeper/history.log' | cut -d: -f1) -lt \$(grep -n 'install aaa-2.0' '$R/var/log/creeper/history.log' | cut -d: -f1) ]"
check "zzz осталась зависимостью" grep -qx dep "$R/var/lib/creeper/installed/zzz/reason"
mk aaa 3.0; rec aaa 3.0 "zzz"
run hold aaa; check "hold" [ -e "$R/var/lib/creeper/installed/aaa/hold" ]
run upgrade; check "замороженный не обновляется" [ "$(cat "$R/var/lib/creeper/installed/aaa/version")" = 2.0 ]
check "upgrade говорит про заморозку" grep -q 'заморожен' <<<"$OUT"
run list; check "list помечает замороженный" grep -q 'aaa.*(заморожен)' <<<"$OUT"
run upgrade aaa; check "названный явно — обновляется" [ "$(cat "$R/var/lib/creeper/installed/aaa/version")" = 3.0 ]
run unhold aaa; check "unhold" [ ! -e "$R/var/lib/creeper/installed/aaa/hold" ]

echo "== 19. rollback"
run rollback aaa 2.0
check "rollback: код 0" [ $RC -eq 0 ]
check "вернулась версия 2.0" bash -c "[ \"\$('$R/usr/bin/aaa')\" = 'aaa 2.0' ] && [ \$(cat '$R/var/lib/creeper/installed/aaa/version') = 2.0 ]"
check "после отката заморожен" [ -e "$R/var/lib/creeper/installed/aaa/hold" ]
run rollback aaa 9.9; check "нет такой версии — понятная ошибка" bash -c "[ $RC -ne 0 ] && grep -q 'в кэше нет' <<<\"\$0\"" "$OUT"
run rollback zzz </dev/null; check "без терминала — самая свежая из прежних" [ "$(cat "$R/var/lib/creeper/installed/zzz/version")" = 1.0 ]

echo "== 20. общий файл не удаляется вместе с одним из владельцев"
reset_root; mk hello 1.0; rec hello 1.0 ""; "$C" install hello >/dev/null 2>&1
mk twin 1.0 'install -Dm755 /dev/null $(DESTDIR)/usr/bin/hello'; rec twin 1.0 ""
run install twin --force; check "--force ставит поверх" [ $RC -eq 0 ]
run blow twin -y
check "общий /usr/bin/hello остался" [ -e "$R/usr/bin/hello" ]
check "свой файл twin удалён" [ ! -e "$R/usr/bin/twin" ]

echo "== 21. смена локали между установкой и обновлением не ломает списки"
reset_root
mk loc 1.0 'for f in a-b a_b aB ab Ab "a b" a.b; do echo x > "$(DESTDIR)/usr/share/doc/loc-1.0/$$f"; done'; rec loc 1.0 ""
LC_ALL=en_US.UTF-8 "$C" install loc >/dev/null 2>&1
mk loc 1.1 'mkdir -p $(DESTDIR)/usr/share/keep; for f in a-b a_b aB ab Ab "a b" a.b; do echo x > "$(DESTDIR)/usr/share/keep/$$f"; done'
sed -i 's#doc/loc-1.1#doc/loc-1.0#g' "$MK/loc-1.1/Makefile"; tar -C "$MK" -czf "$R/var/cache/creeper/sources/loc-1.1.tar.gz" loc-1.1
rec loc 1.1 ""
LC_ALL=C "$C" upgrade >/dev/null 2>&1
check "после обновления в другой локали файлы на месте" bash -c "[ \$(ls '$R/usr/share/keep' | wc -l) -eq 7 ] && [ -f '$R/usr/share/doc/loc-1.0/READ ME.txt' ]"
check "а лишние убраны" [ ! -e "$R/usr/share/doc/loc-1.0/a-b" ]
LC_ALL=en_US.UTF-8 "$C" verify >/dev/null 2>&1; check "verify после смены локали" [ $? -eq 0 ]

echo "== 22. Ctrl+C во время сборки: сборка останавливается, замок свободен"
reset_root; mk slow 1.0; rec slow 1.0 ""
sed -i 's/build()   { make; }/build()   { echo start; sleep 47; }/' "$R/var/lib/creeper/recipes/slow/recipe"
python3 - "$C" <<'PY'
import os, signal, subprocess, sys, time
p = subprocess.Popen([sys.argv[1], "install", "slow"], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
time.sleep(4)
os.killpg(p.pid, signal.SIGINT)      # как Ctrl+C в терминале: сигнал всей группе
try: p.wait(10)
except subprocess.TimeoutExpired: pass
time.sleep(1)
PY
check "сборка не осталась в фоне" bash -c "! pgrep -f '^sleep 47' >/dev/null"
pkill -f '^sleep 47' 2>/dev/null
run blow nosuch -y; check "замок свободен" bash -c "! grep -q 'уже работает' <<<\"\$0\"" "$OUT"
( "$C" install slow >/dev/null 2>&1 & echo $! > /tmp/ctest-pid ); sleep 4
kill -TERM "$(cat /tmp/ctest-pid)"; sleep 2
check "kill creeper останавливает и сборку" bash -c "! pgrep -f '^sleep 47' >/dev/null"
pkill -f '^sleep 47' 2>/dev/null

echo "== 23. свои пакеты: new, add, edit, lint, forget, sync"
reset_root
# исходники трёх видов
S=/tmp/ctest-src; rm -rf "$S"; mkdir -p "$S/mfoo-1.2/src" "$S/cbar-0.3" "$S/abaz-2.0" "$S/plain-1.0"
printf "project('mfoo','c')\nx = dependency('libworld')\ny = dependency('threads')\nz = dependency('nosuchlib-9')\n" > "$S/mfoo-1.2/meson.build"
printf 'cmake_minimum_required(VERSION 3.5)\npkg_check_modules(W REQUIRED world>=1.0)\n' > "$S/cbar-0.3/CMakeLists.txt"
printf '#!/bin/sh\n' > "$S/abaz-2.0/configure"
printf 'all:\n\t@true\ninstall:\n\tinstall -Dm755 /dev/null $(DESTDIR)$(PREFIX)/bin/plain\n' > "$S/plain-1.0/Makefile"
for d in mfoo-1.2 cbar-0.3 abaz-2.0 plain-1.0; do tar -C "$S" -czf "$S/$d.tar.gz" "$d"; done
rec world 1.0 ""; mkdir -p "$R/var/lib/creeper/recipes/cmake"; printf 'name=cmake\nversion=4.0\nsource=()\npackage() { :; }\n' > "$R/var/lib/creeper/recipes/cmake/recipe"
run new "file://$S/mfoo-1.2.tar.gz" --desc 'тест "кавычки" $HOME'
L=$R/var/lib/creeper/local
check "new: рецепт лёг в свои" [ -f "$L/mfoo/recipe" ]
check "new: определил meson" grep -q 'meson setup' "$L/mfoo/recipe"
check "new: имя и версия" bash -c "grep -qx 'name=mfoo' '$L/mfoo/recipe' && grep -qx 'version=1.2' '$L/mfoo/recipe'"
check "new: \$version в ссылке" grep -q 'mfoo-\$version.tar.gz' "$L/mfoo/recipe"
check "new: sha256 записан" grep -q "sha256=($(sha256sum "$S/mfoo-1.2.tar.gz" | cut -d' ' -f1))" "$L/mfoo/recipe"
check "new: зависимость найдена по имени библиотеки" grep -qx 'depends=(world)' "$L/mfoo/recipe"
check "new: ненайденная библиотека названа" grep -q 'не нашёл пакетов: nosuchlib-9' "$L/mfoo/recipe"
check "new: описание с кавычками не ломает рецепт" bash -c "[ \"\$(. '$L/mfoo/recipe'; echo \"\$desc\")\" = 'тест \"кавычки\" \$HOME' ]"
check "new: исходник уже в кэше" [ -s "$R/var/cache/creeper/sources/mfoo-1.2.tar.gz" ]
run lint mfoo; check "new: рецепт проходит lint" [ $RC -eq 0 ]
run new "file://$S/cbar-0.3.tar.gz"; check "new: cmake + зависимость cmake и world" grep -qx 'depends=(cmake world)' "$L/cbar/recipe"
run new "file://$S/abaz-2.0.tar.gz"; check "new: autotools" grep -q './configure --prefix=/usr' "$L/abaz/recipe"
run new "file://$S/plain-1.0.tar.gz" --name myplain --deps "world"
check "new: --name и --deps" bash -c "grep -qx 'name=myplain' '$L/myplain/recipe' && grep -qx 'depends=(world)' '$L/myplain/recipe'"
check "new: make" grep -q 'make PREFIX=/usr DESTDIR' "$L/myplain/recipe"
run new "file://$S/plain-1.0.tar.gz" --name myplain; check "new: существующий не затирается молча" [ $RC -ne 0 ]
mk world 1.0; run install myplain
check "свой пакет собирается и ставится" [ -e "$R/usr/bin/plain" ]
run search --local; check "search --local" bash -c "grep -q myplain <<<\"\$0\" && ! grep -q '^world' <<<\"\$0\"" "$OUT"
run search plain; check "search помечает свой" grep -q 'свой' <<<"$OUT"
run info myplain; check "info: свой рецепт" grep -q 'свой рецепт' <<<"$OUT"
run cat myplain; check "cat" grep -q 'name=myplain' <<<"$OUT"
# edit: правка рецепта из репозитория становится своей копией
printf '#!/bin/sh\nsed -i "s/^version=1.0/version=1.5/" "$1"\n' > /tmp/ctest-ed; chmod +x /tmp/ctest-ed
EDITOR=/tmp/ctest-ed "$C" edit world >/dev/null 2>&1
check "edit: своя копия" grep -qx 'version=1.5' "$L/world/recipe"
check "edit: рецепт репозитория не тронут" grep -qx 'version=1.0' "$R/var/lib/creeper/recipes/world/recipe"
run outdated; check "свой рецепт главнее" grep -q 'world.*1.0-1 → 1.5-1' <<<"$OUT"
printf '#!/bin/sh\ntrue\n' > /tmp/ctest-ed
run forget world; EDITOR=/tmp/ctest-ed "$C" edit world >/dev/null 2>&1
check "edit без изменений не плодит копию" [ ! -e "$L/world" ]
# sync не трогает свои и убирает совпавшие
mkdir -p "$REPO/st/recipes"; cp -r "$R/var/lib/creeper/recipes/." "$REPO/st/recipes/"; cp -r "$L/abaz" "$REPO/st/recipes/"
sed -i 's/^version=1.0/version=7.7/' "$REPO/st/recipes/world/recipe"
tar -C "$REPO/st" -czf "$REPO/recipes.tar.gz" recipes; : > "$REPO/index.txt"
echo "BINREPO=file://$REPO" > "$R/etc/creeper.conf"
EDITOR="sed -i s/^version=1.0/version=1.5/" "$C" edit world >/dev/null 2>&1
run sync
check "sync: код 0" [ $RC -eq 0 ]
check "sync не тронул свой рецепт" grep -qx 'version=1.5' "$L/world/recipe"
check "sync говорит, что действует свой" grep -q 'world: действует твой рецепт' <<<"$OUT"
check "sync убрал свой рецепт, совпавший с репозиторием" [ ! -e "$L/abaz" ]
run forget world; check "forget возвращает рецепт репозитория" bash -c "[ ! -e '$L/world' ] && '$C' info world | grep -q '7.7'"
: > "$R/etc/creeper.conf"
# lint и add
B=/tmp/ctest-bad; mkdir -p "$B"
printf 'name="bad name"\nversion=\nsource=(v1.0.tar.gz::http://x/v1.0.tar.gz http://y/v2.0.tar.gz)\ndepends=(nosuchdep)\nbuild() { :; }\n' > "$B/recipe"
run lint "$B/recipe"
check "lint: код ≠ 0" [ $RC -ne 0 ]
check "lint: плохое имя" grep -q "имя 'bad name'" <<<"$OUT"
check "lint: нет версии" grep -q 'нет version' <<<"$OUT"
check "lint: нет package()" grep -q 'нет функции package' <<<"$OUT"
check "lint: общее имя архива" grep -q "v2.0.tar.gz.*слишком общо" <<<"$OUT"
check "lint: неизвестная зависимость" grep -q "зависимость 'nosuchdep'" <<<"$OUT"
run add "$B/recipe"; check "add отвергает плохой рецепт" [ $RC -ne 0 ]
printf 'name=good\nversion=1\ndesc="x"\nsource=()\nbuild() { :; }\npackage() { install -Dm644 /dev/null "$PKG/usr/share/good"; }\n' > "$B/recipe"
run add "$B/recipe"; check "add принимает хороший" [ -f "$L/good/recipe" ]
run install good; check "и он ставится" [ -e "$R/usr/share/good" ]
OUT=$(cd /tmp && rm -rf /tmp/libfoo && RECIPES_OUT=/tmp "$C" new https://example.org/dl/libfoo-2.4.1.tar.xz --no-download 2>&1)
check "new --no-download: заготовка без сети" grep -q 'раскомментируй' /tmp/libfoo/recipe
run install mfo; check "опечатка в имени — подсказка похожих" grep -q 'может быть:.*mfoo' <<<"$OUT"

echo "== 24. doctor, mark, rdeps, size, list, completion"
reset_root; mk world 1.0; mk hello 1.0; rec world 1.0 ""; rec hello 1.0 "world"
"$C" install hello >/dev/null 2>&1
run doctor; check "doctor: чистая система" [ $RC -eq 0 ]
run rdeps world; check "rdeps" grep -qx hello <<<"$OUT"
run mark dep hello; run orphans; check "mark dep → сироты" bash -c "grep -qx hello <<<\"\$0\"" "$OUT"
run mark explicit hello; run list --explicit; check "list --explicit" bash -c "grep -q '^hello' <<<\"\$0\" && ! grep -q '^world' <<<\"\$0\"" "$OUT"
run list --deps; check "list --deps" bash -c "grep -q '^world' <<<\"\$0\" && ! grep -q '^hello' <<<\"\$0\"" "$OUT"
run size; check "size" grep -q 'всего в 2 пакетах' <<<"$OUT"
"$C" blow world --force -y >/dev/null 2>&1
run doctor; check "doctor находит нарушенную зависимость" bash -c "[ $RC -ne 0 ] && grep -q 'hello требует world' <<<\"\$0\"" "$OUT"
"$C" completion > /tmp/ctest-compl; check "completion — корректный bash" bash -n /tmp/ctest-compl
check "completion дополняет команды и пакеты" bash -c ". /tmp/ctest-compl; COMP_WORDS=(sudo creeper ins); COMP_CWORD=2; _creeper; [ \"\${COMPREPLY[0]}\" = install ]"
run help; check "help упоминает tui" grep -q 'creeper tui' <<<"$OUT"

echo "== 25. zip-исходники и предупреждение о /usr/lib64"
reset_root; Z=/tmp/ctest-zip; rm -rf "$Z"; mkdir -p "$Z/zipped-1.0"
printf 'all:\n\t@true\ninstall:\n\tinstall -Dm644 /dev/null $(DESTDIR)/usr/lib64/libz.so\n' > "$Z/zipped-1.0/Makefile"
( cd "$Z" && python3 -m zipfile -c "$R/var/cache/creeper/sources/zipped-1.0.zip" zipped-1.0 )
rec zipped 1.0 ""; sed -i 's/zipped-\$version.tar.gz/zipped-$version.zip/' "$R/var/lib/creeper/recipes/zipped/recipe"
run install zipped
check "zip распакован и собран" [ -e "$R/usr/lib64/libz.so" ]
check "предупреждение о /usr/lib64" grep -q '/usr/lib64' <<<"$OUT"

echo "== 26. TUI (в псевдотерминале)"
reset_root; mk world 1.0; mk hello 1.0; rec world 1.0 ""; rec hello 1.0 "world"; rec zeta 3.1 ""
OUT=$(python3 "$(cd "$(dirname "$0")" && pwd)/tui_test.py" "$C" "$R" "file://$S/plain-1.0.tar.gz" 2>&1); RC=$?
if [ $RC -eq 0 ]; then ok "сценарий TUI пройден"; else bad "сценарий TUI" "$OUT"; fi
check "TUI: hello установлен клавишей i" [ -x "$R/usr/bin/hello" ]
check "TUI: свой пакет создан мастером" [ -f "$R/var/lib/creeper/local/plain/recipe" ]
check "TUI: свой пакет собран и установлен" [ -e "$R/usr/bin/plain" ]

echo
printf 'Итого: \e[32m%d прошло\e[0m, \e[31m%d упало\e[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

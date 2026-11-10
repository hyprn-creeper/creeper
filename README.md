# creeper

Пакетный менеджер для **Hyprn LFS** (Linux From Scratch 12.4, SysV).

```
creeper tui                     # всё в одном окне: список, поиск, установка, свои пакеты
sudo creeper install git        # Ссссс... поставить (готовый бинарник или сборка)
sudo creeper blow git           # *** БА-БАХ! *** удалить
creeper search | info | list | deps | files | owns | verify | doctor | history
```

## Окно: `creeper tui`

Работает в любом терминале, ничего дополнительно ставить не надо (чистый bash). Root не нужен:
для действий creeper сам вызовет `sudo`.

| Клавиша | Действие |
|---|---|
| ↑ ↓ PgUp PgDn | движение по списку |
| Tab, 1–4 | вкладки: все / установленные / обновления / свои |
| `/` | поиск по имени и описанию (Esc — сбросить) |
| Enter | действия с пакетом: поставить, взорвать, пересобрать, файлы, рецепт, заморозить, откатить… |
| Пробел | отметить несколько пакетов, затем `i` — поставить, `b` — взорвать |
| `u` / `s` | обновить всё / обновить рецепты |
| `n` | **создать свой пакет** по ссылке |
| `m` | меню: проверка системы, очистка, ферма, обновление creeper |
| `q` | выход |

Клавиши работают и в русской раскладке. Значки: ✓ установлен, ↑ есть обновление, ★ свой рецепт.

## Свои пакеты

```
sudo creeper new https://github.com/areofyl/fetch       # страница проекта: возьмёт последний релиз
sudo creeper new https://example.org/foo-1.2.tar.xz     # или прямая ссылка на архив
```

Мастер скачивает исходники и сам определяет имя, версию, sha256, **способ сборки**
(autotools, meson, cmake, make, cargo, go, python) и **зависимости** — по библиотекам, которые
ищет сборка (pkg-config). Потом спрашивает, что поправить, и предлагает собрать здесь или на ферме.
То же самое в окне: `creeper tui` → `n`.

Свои рецепты лежат в `/var/lib/creeper/local/` — они главнее рецептов из репозитория,
и `sync` их не трогает.

| Команда | Что делает |
|---|---|
| `new [ссылка]` | мастер нового пакета (`--name --ver --desc --deps --type`, `-y` — без вопросов) |
| `edit <п>` | править рецепт в редакторе; правка рецепта из репозитория становится своей копией |
| `lint <п\|файл>` | проверить рецепт на ошибки |
| `cat <п>` | показать рецепт |
| `add <файл>` | принять готовый файл рецепта как свой |
| `forget <п>` | убрать свой рецепт (вернуть рецепт из репозитория) |
| `farm send <п>` | отправить свой рецепт в репозиторий фермы |

## Команды

| Команда | Что делает |
|---|---|
| `install <п...>` | ставит вместе с зависимостями: `[кэш]` → `[скачать]` с фермы → `[сборка]` |
| `install --reinstall <п>` | переставить ту же версию (быстро, из бинарника) |
| `install --rebuild <п>` | собрать заново из исходников |
| `blow <п...>` | удалить (спрашивает подтверждение, `-y` — без вопросов) |
| `upgrade [п...]` | обновить всё (или названное), у чего рецепт новее; зависимости — в правильном порядке |
| `outdated` | что обновится |
| `hold <п>` / `unhold <п>` | заморозить пакет: `upgrade` его не трогает |
| `rollback <п> [версия]` | вернуть прежнюю сборку из кэша (и заморозить) |
| `autoremove` / `orphans` | убрать / показать зависимости, которые больше никому не нужны |
| `mark explicit\|dep <п>` | «нужен мне» / «только зависимость» |
| `fetch <п...>` | только скачать — потом можно ставить без сети |
| `verify [п...]` | проверить файлы по sha256 (пропавшие, испорченные после сбоя) |
| `doctor [--fast]` | проверка системы: зависимости, программы без нужных библиотек, общие файлы, рецепты |
| `deps <п>` / `rdeps <п>` | дерево зависимостей / кому нужен пакет |
| `size [N]` | самые большие пакеты |
| `sync` | обновить рецепты с фермы (и сообщить о новом creeper) |
| `self-update` | обновить сам creeper (с проверкой sha256) |
| `clean [--all]` | временные файлы (`--all`: и исходники/бинарники старых версий) |
| `log <п>` / `history` | лог сборки / журнал установок и удалений |
| `completion` | автодополнение для bash: `echo '. <(creeper completion)' >> ~/.bashrc` |

После установки и удаления creeper сам обновляет общие кэши системы (шрифты, значки, схемы GLib,
типы файлов, модули ядра) — в рецептах это писать не нужно.

## Ферма прямо из LFS

```
sudo creeper farm token            # один раз: fine-grained токен (Actions + Contents: Read and write)
sudo creeper farm build hyprn-dwm  # собрать на GitHub, дождаться, поставить
sudo creeper farm status           # последние сборки
sudo creeper new https://…/foo-1.0.tar.xz && sudo creeper farm build foo   # свой пакет
```

`farm build` сам отправляет в репозиторий рецепты, которых там нет или которые у тебя новее.

## Рабочий стол: dwm

`sudo creeper farm build hyprn-dwm` → 52 пакета: Xorg 21.1 (modesetting, без Mesa), libinput,
шрифты DejaVu, dwm 6.8, st 0.9.3, dmenu 5.4, slstatus 1.1. Запуск с консоли: `startdwm`.

| Клавиши | Действие |
|---|---|
| Super+Shift+Enter | терминал st |
| Super+P | меню программ (dmenu) |
| Super+J / Super+K | следующее / предыдущее окно |
| Super+Shift+C | закрыть окно |
| Super+1…9 | рабочие столы |
| Alt+Shift | раскладка us/ru |
| Super+Shift+Q | выйти из dwm |

Рецепты Xorg генерируются: `python3 tools/gen-xorg-recipes.py`.

## Discord

`sudo creeper install discord` → ~40 пакетов с фермы (GTK3, NSS, Mesa, PulseAudio, D-Bus...)
и загрузчик Discord. Само приложение скачивается при первом запуске в `~/.config/discord`
(рецепт помечен `norepo=1`: закрытая программа на ферму не выкладывается).
Для голоса: `sudo usermod -aG audio $USER`. Лог: `~/.local/share/discord.log`.

## Ядро

`sudo creeper install linux` → ядро 7.2.15-lfs с конфигом Arch (NVMe и ext4 встроены, без initramfs),
ставится рядом со старым. Пункт GRUB добавляется в Arch: `sudo bash tools/lfs-grub-add.sh 7.2.15-lfs`.

## Зонд

`.github/workflows/probe.yml`: `discord` (какие библиотеки нужны), `lfs-discord` (проверка в копии LFS),
`urls` (все ссылки рецептов), `kernel`, `blfs:раздел/страница` (команды со страниц BLFS).

## Рецепт

```bash
name=htop
version=3.4.1
release=1                       # поднять, чтобы пересобрать ту же версию
desc="интерактивный монитор процессов"
source=(https://github.com/htop-dev/htop/releases/download/$version/htop-$version.tar.xz)
sha256=()                       # пусто = запомнить при первой загрузке
depends=()
backup=()                       # конфиги, которые не затирать при обновлении

build()   { ./configure --prefix=/usr --sysconfdir=/etc; make; }
package() { make DESTDIR="$PKG" install; }
# необязательно: prepare(), check(), post_install(), pre_blow(); keep_la=1
```

В рецептах доступны `$PKG` (куда ставить), `$SOURCES`, `$version`, `$JOBS` (потоки; для ninja — `ninja -j"$JOBS"`).
Архивы `.tar.*` и `.zip` распаковываются сами. Если имя архива общее (`v1.2.tar.gz`), пиши
`source=(имя-$version.tar.gz::ссылка)` — иначе он совпадёт с чужим. Проверка рецепта: `creeper lint <п>`.

## Ферма

`.github/workflows/build.yml` собирает пакеты в копии этой LFS (релиз `base`)
и выкладывает бинарники в релиз `bin` вместе с `index.txt` (sha256), рецептами и самим creeper.

Запуск: Actions → build → Run workflow, или `gh workflow run build.yml -f packages="htop tmux"`.

## Образ для фермы

`sudo bash builder/make-image.sh` (в Arch, LFS подключена в /mnt/lfs) →
`~/lfs-builder.tar.zst` без паролей, ключа Wi-Fi и домашних папок →
`gh release upload base ~/lfs-builder.tar.zst --clobber`

# creeper

Пакетный менеджер для **Hyprn LFS** (Linux From Scratch 12.4, SysV).

```
sudo creeper install git        # Ссссс... поставить (готовый бинарник или сборка)
sudo creeper blow git           # *** БА-БАХ! *** удалить
creeper search | info | list | deps | files | owns | verify | history
```

## Команды

| Команда | Что делает |
|---|---|
| `install <п...>` | ставит вместе с зависимостями: `[кэш]` → `[скачать]` с фермы → `[сборка]` |
| `install --reinstall <п>` | переставить ту же версию (быстро, из бинарника) |
| `install --rebuild <п>` | собрать заново из исходников |
| `blow <п...>` | удалить (спрашивает подтверждение, `-y` — без вопросов) |
| `upgrade` | обновить всё, у чего рецепт новее (с новыми зависимостями) |
| `autoremove` / `orphans` | убрать / показать зависимости, которые больше никому не нужны |
| `fetch <п...>` | только скачать — потом можно ставить без сети |
| `verify [п...]` | проверить файлы по sha256 (пропавшие, испорченные после сбоя) |
| `deps <п>` | дерево зависимостей |
| `sync` | обновить рецепты с фермы (и сообщить о новом creeper) |
| `self-update` | обновить сам creeper (с проверкой sha256) |
| `clean [--all]` | временные файлы (`--all`: и исходники/бинарники старых версий) |
| `new <url>` | заготовка рецепта по ссылке на архив |
| `log <п>` / `history` | лог сборки / журнал установок и удалений |

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

## Ферма

`.github/workflows/build.yml` собирает пакеты в копии этой LFS (релиз `base`)
и выкладывает бинарники в релиз `bin` вместе с `index.txt` (sha256), рецептами и самим creeper.

Запуск: Actions → build → Run workflow, или `gh workflow run build.yml -f packages="htop tmux"`.

## Образ для фермы

`sudo bash builder/make-image.sh` (в Arch, LFS подключена в /mnt/lfs) →
`~/lfs-builder.tar.zst` без паролей, ключа Wi-Fi и домашних папок →
`gh release upload base ~/lfs-builder.tar.zst --clobber`

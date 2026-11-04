# creeper

Пакетный менеджер для **Hyprn LFS** (Linux From Scratch 12.4, SysV).

```
sudo creeper install git      # Ссссс... поставить (готовый бинарник или сборка)
sudo creeper blow git         # *** БА-БАХ! *** удалить
creeper search | info | list | files | owns
```

## Как устроено

- `recipes/<пакет>/recipe` — рецепт: версия, исходники, зависимости, `build()` и `package()`.
- Пакеты ставятся через `DESTDIR`, creeper помнит все файлы и умеет их удалить.
- Сборочная ферма (`.github/workflows/build.yml`) собирает пакеты в копии этой LFS
  (релиз `base`) и выкладывает бинарники в релиз `bin` вместе с `index.txt` (sha256).
- На компьютере `creeper install` сначала ищет бинарник в `bin`, иначе собирает сам.

## Собрать пакет на ферме

Actions → build → Run workflow → `packages: git`
или из терминала: `gh workflow run build.yml -f packages="git"`

## Образ для фермы

`sudo bash builder/make-image.sh` (в Arch, LFS подключена в /mnt/lfs) →
`~/lfs-builder.tar.zst` без паролей, ключа Wi-Fi и домашних папок →
`gh release create base ~/lfs-builder.tar.zst`

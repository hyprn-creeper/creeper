#!/bin/bash
# Установка creeper в LFS — запускать в Arch:  sudo bash install-host.sh
# (раздел LFS должен быть подключён в /mnt/lfs)
set -e
LFS=${LFS:-/mnt/lfs}
HERE=$(dirname "$(readlink -f "$0")")
die() { echo "ОШИБКА: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "запусти через sudo"
mountpoint -q "$LFS" || die "$LFS не подключён: sudo mount /dev/nvme0n1p4 $LFS"
[ -f "$LFS/etc/lfs-release" ] || die "в $LFS не похоже на LFS (нет /etc/lfs-release)"
command -v curl >/dev/null || die "нужен curl в Arch"

echo "==> creeper -> $LFS/usr/bin/creeper"
install -Dm755 "$HERE/creeper" "$LFS/usr/bin/creeper"
install -dm755 "$LFS/var/lib/creeper/recipes" "$LFS/var/cache/creeper/sources" \
               "$LFS/var/log/creeper" "$LFS/var/tmp/creeper"
cp -r "$HERE"/recipes/* "$LFS/var/lib/creeper/recipes/"
[ -f "$LFS/etc/creeper.conf" ] || install -m644 "$HERE/creeper.conf" "$LFS/etc/creeper.conf"

echo "==> скачиваю исходники для рецептов (в LFS пока нечем качать)"
SRC=$LFS/var/cache/creeper/sources
for r in "$HERE"/recipes/*/recipe; do
  ( . "$r"
    for s in "${source[@]}"; do
      case $s in *::*) f=${s%%::*}; u=${s#*::};; *) u=$s; f=$(basename "$s");; esac
      if [ -s "$SRC/$f" ]; then echo "    есть: $f"; continue; fi
      echo "    $f"
      curl -fL# --retry 3 -o "$SRC/$f.part" "$u" && mv "$SRC/$f.part" "$SRC/$f" \
        || { rm -f "$SRC/$f.part"; echo "    !! не скачалось: $u"; }
    done )
done

chown -R root:root "$LFS/usr/bin/creeper" "$LFS/var/lib/creeper" "$LFS/var/cache/creeper" \
                   "$LFS/etc/creeper.conf"
echo
echo "Готово. Загрузись в LFS, войди как root и выполни:"
echo "    creeper search"
echo "    creeper help"

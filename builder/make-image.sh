#!/bin/bash
# Чистый образ LFS для сборочной фермы — запускать в Arch:
#     sudo bash builder/make-image.sh
# Берёт /mnt/lfs, выкидывает личное (пароли, ключ Wi-Fi, домашние папки, логи),
# и делает ~/lfs-builder.tar.zst. Этот файл будет ПУБЛИЧНЫМ на GitHub.
set -euo pipefail
LFS=${LFS:-/mnt/lfs}
OUT=${OUT:-/home/${SUDO_USER:-$USER}/lfs-builder.tar.zst}
STAGE=${STAGE:-/home/${SUDO_USER:-$USER}/.lfs-builder-stage}
die() { echo "ОШИБКА: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "запусти через sudo"
mountpoint -q "$LFS" || die "$LFS не подключён: sudo mount /dev/nvme0n1p4 $LFS"
[ -f "$LFS/etc/lfs-release" ] || die "в $LFS нет LFS"
command -v zstd >/dev/null || die "нужен zstd (sudo pacman -S zstd)"

echo "==> копирую систему без лишнего в $STAGE"
rm -rf "$STAGE"; mkdir -p "$STAGE"
tar -C "$LFS" -cpf - --one-file-system \
  --exclude=./sources --exclude=./tools --exclude=./boot --exclude=./lost+found \
  --exclude=./home --exclude=./root --exclude=./tmp --exclude=./var/tmp \
  --exclude=./var/log --exclude=./var/cache/creeper --exclude=./var/lib/dhcpcd \
  --exclude=./usr/lib/firmware --exclude=./usr/lib/modules \
  --exclude=./usr/share/doc --exclude=./usr/share/man --exclude=./usr/share/info \
  --exclude=./etc/wpa_supplicant.conf --exclude='./etc/ssh/*key*' \
  --exclude='./etc/*.creeper-new' . | tar -C "$STAGE" -xpf -

echo "==> вычищаю личное"
# пароли: в образе все учётки заблокированы
for f in etc/shadow etc/gshadow etc/shadow- etc/gshadow-; do
  [ -f "$STAGE/$f" ] && awk -F: 'BEGIN{OFS=":"} {$2="!"; print}' "$STAGE/$f" > "$STAGE/$f.new" && mv "$STAGE/$f.new" "$STAGE/$f"
done
chmod 600 "$STAGE"/etc/shadow "$STAGE"/etc/gshadow 2>/dev/null || true
mkdir -p "$STAGE"/{home,root,tmp,var/tmp,var/log,boot}
chmod 700 "$STAGE/root"; chmod 1777 "$STAGE/tmp" "$STAGE/var/tmp"
rm -f "$STAGE"/etc/creeper.conf "$STAGE"/etc/resolv.conf
: > "$STAGE/etc/resolv.conf"

# проверка: не осталось ли хешей паролей и ключа Wi-Fi
if grep -q '\$' "$STAGE/etc/shadow"; then die "в shadow остались хеши — образ НЕ создан"; fi
if grep -rqs 'psk=' "$STAGE/etc" 2>/dev/null; then die "в /etc нашёлся psk= (ключ Wi-Fi) — образ НЕ создан"; fi

echo "==> сжимаю (несколько минут)"
tar -C "$STAGE" -cpf - . | zstd -T0 -15 -q -c > "$OUT.part"
mv "$OUT.part" "$OUT"
chown "${SUDO_USER:-root}": "$OUT" 2>/dev/null || true
rm -rf "$STAGE"
echo
ls -lh "$OUT"
echo "Готово. Размер должен быть меньше 2 ГБ (предел GitHub)."

#!/bin/bash
# Добавить в GRUB (Arch) пункт для нового ядра LFS, не трогая старый.
#   sudo bash tools/lfs-grub-add.sh 7.2.15-lfs
# Берёт существующий пункт LFS из /etc/grub.d/40_custom, копирует его и меняет ядро.
set -euo pipefail
KVER=${1:?укажи версию ядра, например 7.2.15-lfs}
F=/etc/grub.d/40_custom
[ "$(id -u)" -eq 0 ] || { echo "запусти через sudo"; exit 1; }
grep -q "vmlinuz-$KVER" "$F" && { echo "пункт для $KVER уже есть в $F"; exit 0; }
cp -a "$F" "$F.bak-$(date +%Y%m%d-%H%M%S)"
python3 - "$F" "$KVER" <<'PY'
import re, sys
path, kver = sys.argv[1], sys.argv[2]
text = open(path).read()
# первый пункт menuentry, в котором грузится vmlinuz-*-lfs*
blocks = list(re.finditer(r'menuentry\s[^\n]*\{.*?\n\}', text, re.S))
lfs = [b for b in blocks if re.search(r'vmlinuz-[^\s]*lfs', b.group(0))]
if not lfs:
    sys.exit("в %s не нашёл пункт LFS (строку linux .../vmlinuz-...lfs...)" % path)
old = lfs[0].group(0)
oldk = re.search(r'vmlinuz-([^\s]+)', old).group(1)
new = old.replace('vmlinuz-' + oldk, 'vmlinuz-' + kver, 1)
def title(m):
    t = m.group(2)
    t = t.replace(oldk, kver) if oldk in t else "%s (%s)" % (t, kver)
    return "menuentry %s%s%s" % (m.group(1), t, m.group(1))
new = re.sub(r"menuentry\s+(['\"])(.*?)\1", title, new, count=1)
text = text[:lfs[0].start()] + new + "\n\n" + text[lfs[0].start():]
open(path, "w").write(text)
print("добавлен пункт:\n" + new)
PY
grub-mkconfig -o /boot/grub/grub.cfg
echo "Готово. Новое ядро — первым пунктом LFS; старое осталось ниже (если что-то не так — выбери его)."

#!/usr/bin/env python3
"""Генератор рецептов Xorg (BLFS 12.4, без Mesa) для creeper.
Запуск: python3 tools/gen-xorg-recipes.py  → пишет recipes/<имя>/recipe
Нетиповые пакеты (xorg-server, шрифты, suckless, мета-пакет) — отдельными файлами ниже по скрипту.
"""
import os, sys, textwrap

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "recipes")
XC = "--prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static"
X = "https://www.x.org/pub/individual"
XF = "https://xorg.freedesktop.org/archive/individual"

# имя, версия, описание, ссылка ($version подставится), зависимости, тип, доп. опции
# тип: xorg (autotools с XORG_CONFIG), meson, auto (свои опции configure целиком)
PKGS = [
 ("util-macros", "1.20.2", "макросы autoconf для пакетов X.org", f"{X}/util/util-macros-$version.tar.xz", [], "xorg", ""),
 ("xorgproto", "2024.1", "заголовки протоколов X11", f"{XF}/proto/xorgproto-$version.tar.xz", ["util-macros"], "meson", "-D legacy=true"),
 ("libXau", "1.0.12", "авторизация X11", f"{X}/lib/libXau-$version.tar.xz", ["xorgproto"], "xorg", ""),
 ("libXdmcp", "1.1.5", "протокол XDMCP", f"{X}/lib/libXdmcp-$version.tar.xz", ["xorgproto"], "xorg", ""),
 ("xcb-proto", "1.17.0", "описания протокола XCB", f"{XF}/proto/xcb-proto-$version.tar.xz", [], "xcbproto", ""),
 ("libxcb", "1.17.0", "XCB — низкоуровневая библиотека X11", f"{XF}/lib/libxcb-$version.tar.xz", ["libXau", "libXdmcp", "xcb-proto"], "xorg", "--without-doxygen --docdir='${datadir}'/doc/libxcb-$version"),
 ("libpng", "1.6.50", "картинки PNG", "https://downloads.sourceforge.net/libpng/libpng-$version.tar.xz", [], "auto", "--prefix=/usr --disable-static"),
 ("xtrans", "1.6.0", "сетевой транспорт X11", f"{X}/lib/xtrans-$version.tar.xz", ["util-macros"], "xorg", ""),
 ("libX11", "1.8.12", "Xlib — основная библиотека X11", f"{X}/lib/libX11-$version.tar.xz", ["xtrans", "libxcb", "xorgproto"], "xorg", ""),
 ("libXext", "1.3.6", "расширения X11", f"{X}/lib/libXext-$version.tar.xz", ["libX11"], "xorg", ""),
 ("libICE", "1.1.2", "Inter-Client Exchange", f"{X}/lib/libICE-$version.tar.xz", ["xtrans", "xorgproto"], "xorg", ""),
 ("libSM", "1.2.6", "управление сеансом X11", f"{X}/lib/libSM-$version.tar.xz", ["libICE"], "xorg", ""),
 ("libXt", "1.3.1", "X Toolkit Intrinsics", f"{X}/lib/libXt-$version.tar.xz", ["libSM", "libX11"], "xorg", "--with-appdefaultdir=/etc/X11/app-defaults"),
 ("libXmu", "1.2.1", "служебные функции X11", f"{X}/lib/libXmu-$version.tar.xz", ["libXt", "libXext"], "xorg", ""),
 ("libXfixes", "6.0.1", "расширение XFIXES", f"{X}/lib/libXfixes-$version.tar.xz", ["libX11"], "xorg", ""),
 ("libXrender", "0.9.12", "расширение RENDER", f"{X}/lib/libXrender-$version.tar.xz", ["libX11"], "xorg", ""),
 ("libXcursor", "1.2.3", "курсоры X11", f"{X}/lib/libXcursor-$version.tar.xz", ["libXrender", "libXfixes"], "xorg", ""),
 ("libXdamage", "1.1.6", "расширение DAMAGE", f"{X}/lib/libXdamage-$version.tar.xz", ["libXfixes"], "xorg", ""),
 ("libXcomposite", "0.4.6", "расширение COMPOSITE", f"{X}/lib/libXcomposite-$version.tar.xz", ["libXfixes"], "xorg", ""),
 ("libfontenc", "1.1.8", "кодировки шрифтов X11", f"{X}/lib/libfontenc-$version.tar.xz", ["xorgproto"], "xorg", ""),
 ("libXfont2", "2.0.7", "шрифты для X-сервера", f"{X}/lib/libXfont2-$version.tar.xz", ["libfontenc", "freetype", "xtrans"], "xorg", "--disable-devel-docs"),
 ("libXft", "2.3.9", "сглаженные шрифты X11 (Xft)", f"{X}/lib/libXft-$version.tar.xz", ["libXrender", "fontconfig"], "xorg", ""),
 ("libXi", "1.8.2", "расширение XInput", f"{X}/lib/libXi-$version.tar.xz", ["libXext", "libXfixes"], "xorg", ""),
 ("libXinerama", "1.1.5", "несколько мониторов (Xinerama)", f"{X}/lib/libXinerama-$version.tar.xz", ["libXext"], "xorg", ""),
 ("libXrandr", "1.5.4", "расширение RandR (экраны)", f"{X}/lib/libXrandr-$version.tar.xz", ["libXext", "libXrender"], "xorg", ""),
 ("libXtst", "1.2.5", "расширение XTEST", f"{X}/lib/libXtst-$version.tar.xz", ["libXi"], "xorg", ""),
 ("libXScrnSaver", "1.2.4", "расширение MIT-SCREEN-SAVER", f"{X}/lib/libXScrnSaver-$version.tar.xz", ["libXext"], "xorg", ""),
 ("libxkbfile", "1.1.3", "файлы раскладок XKB", f"{X}/lib/libxkbfile-$version.tar.xz", ["libX11"], "xorg", ""),
 ("libxshmfence", "1.3.3", "общие барьеры памяти X11", f"{X}/lib/libxshmfence-$version.tar.xz", ["xorgproto"], "xorg", ""),
 ("libpciaccess", "0.18.1", "доступ к устройствам PCI", f"{X}/lib/libpciaccess-$version.tar.xz", ["util-macros"], "meson", ""),
 ("libdrm", "2.4.125", "доступ к видеоядру (DRM)", "https://dri.freedesktop.org/libdrm/libdrm-$version.tar.xz", ["libpciaccess"], "meson", "-D udev=true -D valgrind=disabled"),
 ("pixman", "0.46.4", "работа с пикселями (рисование)", "https://www.cairographics.org/releases/pixman-$version.tar.gz", [], "meson", ""),
 ("libxcvt", "0.1.3", "расчёт видеорежимов VESA CVT", f"{X}/lib/libxcvt-$version.tar.xz", [], "meson", ""),
 ("font-util", "1.4.1", "утилиты шрифтов X.org", f"{X}/font/font-util-$version.tar.xz", ["util-macros"], "xorg", ""),
 ("xbitmaps", "1.1.3", "стандартные картинки X11", f"{X}/data/xbitmaps-$version.tar.xz", ["util-macros"], "xorg", ""),
 ("xkeyboard-config", "2.45", "описания раскладок клавиатуры", f"{X}/data/xkeyboard-config/xkeyboard-config-$version.tar.xz", [], "meson", ""),
 ("xkbcomp", "1.4.7", "компилятор раскладок XKB (нужен серверу)", f"{X}/app/xkbcomp-$version.tar.xz", ["libxkbfile"], "xorg", ""),
 ("xauth", "1.1.4", "ключи доступа к X-серверу", f"{X}/app/xauth-$version.tar.xz", ["libXau", "libXext", "libXmu"], "xorg", ""),
 ("setxkbmap", "1.3.4", "переключение раскладок (us/ru)", f"{X}/app/setxkbmap-$version.tar.xz", ["libxkbfile"], "xorg", ""),
 ("xsetroot", "1.1.3", "фон рабочего стола, имя окна (статус dwm)", f"{X}/app/xsetroot-$version.tar.xz", ["libXmu", "libXcursor", "xbitmaps"], "xorg", ""),
 ("xrandr", "1.5.3", "разрешение и мониторы", f"{X}/app/xrandr-$version.tar.xz", ["libXrandr"], "xrandr", ""),
 ("xset", "1.2.5", "настройки X (клавиатура, экран)", f"{X}/app/xset-$version.tar.xz", ["libXmu", "libXext"], "xorg", ""),
 ("xprop", "1.2.8", "свойства окон (отладка)", f"{X}/app/xprop-$version.tar.xz", ["libX11"], "xorg", ""),
 ("xinput", "1.6.4", "настройка мыши и тачпада", f"{X}/app/xinput-$version.tar.xz", ["libXi", "libXrandr", "libXinerama"], "xorg", ""),
 ("mtdev", "1.1.7", "мультитач для старых драйверов", "https://bitmath.org/code/mtdev/mtdev-$version.tar.bz2", [], "auto", "--prefix=/usr --disable-static"),
 ("libevdev", "1.13.4", "события устройств ввода", "https://www.freedesktop.org/software/libevdev/libevdev-$version.tar.xz", [], "meson", "-D documentation=disabled -D tests=disabled"),
 ("libinput", "1.29.0", "клавиатура, мышь, тачпад", "https://gitlab.freedesktop.org/libinput/libinput/-/archive/$version/libinput-$version.tar.gz", ["libevdev", "mtdev"], "meson", "-D debug-gui=false -D tests=false -D libwacom=false -D udev-dir=/usr/lib/udev"),
 ("xf86-input-libinput", "1.5.0", "драйвер ввода Xorg через libinput", f"{X}/driver/xf86-input-libinput-$version.tar.xz", ["libinput", "xorg-server"], "xorg", ""),
 ("xinit", "1.4.4", "startx — запуск X из консоли", f"{X}/app/xinit-$version.tar.xz", ["libX11", "xauth"], "xorg", "--with-xinitdir=/etc/X11/app-defaults"),
]


def recipe_text(name, ver, desc, url, deps, kind, extra):
    head = f'''name={name}
version={ver}
desc="{desc}"
url={url.split("/$version")[0].rsplit("/", 1)[0] if False else ""}
source=({url})
depends=({" ".join(deps)})
'''
    head = head.replace("url=\n", "")
    if kind == "xorg":
        body = f'''
build() {{
  ./configure {XC} --docdir=/usr/share/doc/{name}-$version {extra}
  make
}}
package() {{ make DESTDIR="$PKG" install; }}
'''
    elif kind == "auto":
        body = f'''
build() {{
  ./configure {extra}
  make
}}
package() {{ make DESTDIR="$PKG" install; }}
'''
    elif kind == "xcbproto":
        body = f'''
build() {{
  PYTHON=python3 ./configure {XC}
  make
}}
package() {{ make DESTDIR="$PKG" install; }}
'''
    elif kind == "xrandr":
        body = f'''
build() {{
  ./configure {XC}
  make
}}
package() {{
  make DESTDIR="$PKG" install
  rm -f "$PKG/usr/bin/xkeystone"     # как в BLFS: без cairo-5c/nickle не работает
}}
'''
    elif kind == "meson" and name == "xorgproto":
        body = f'''
build() {{
  mkdir -p build && cd build
  meson setup --prefix=/usr --buildtype=release {extra} ..
  ninja -j"$JOBS"
}}
package() {{
  cd build && DESTDIR="$PKG" ninja install
  # этот заголовок ставит libX11 — пусть он им и владеет
  rm -f "$PKG/usr/include/X11/extensions/XKBgeom.h"
}}
'''
        head = head.replace("version=", "release=2\nversion=", 1)
    elif kind == "meson":
        body = f'''
build() {{
  mkdir -p build && cd build
  meson setup --prefix=/usr --buildtype=release {extra} ..
  ninja -j"$JOBS"
}}
package() {{ cd build && DESTDIR="$PKG" ninja install; }}
'''
    else:
        raise SystemExit("неизвестный тип " + kind)
    return head + body


def write(name, text):
    d = os.path.join(ROOT, name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "recipe"), "w") as f:
        f.write(textwrap.dedent(text).lstrip())


for p in PKGS:
    write(p[0], recipe_text(*p))

# ---------- нетиповые ----------
write("freetype", '''
name=freetype
version=2.13.3
desc="отрисовка шрифтов FreeType"
source=(https://downloads.sourceforge.net/freetype/freetype-$version.tar.xz)
depends=(libpng which)

prepare() {
  sed -ri "s:.*(AUX_MODULES.*valid):\\1:" modules.cfg
  sed -r "s:.*(#.*SUBPIXEL_RENDERING) .*:\\1:" -i include/freetype/config/ftoption.h
}
build() {
  ./configure --prefix=/usr --enable-freetype-config --disable-static
  make
}
package() { make DESTDIR="$PKG" install; }
''')

write("fontconfig", '''
name=fontconfig
version=2.17.1
desc="поиск и настройка шрифтов"
source=(https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/$version/fontconfig-$version.tar.xz)
depends=(freetype)

build() {
  ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \\
              --disable-docs --docdir=/usr/share/doc/fontconfig-$version
  make
}
package() { make DESTDIR="$PKG" install; }
post_install() { fc-cache -f >/dev/null 2>&1 || true; }
''')

write("xorg-server", '''
name=xorg-server
version=21.1.18
desc="X-сервер Xorg (modesetting, без Mesa: программная отрисовка)"
source=(https://www.x.org/pub/individual/xserver/xorg-server-$version.tar.xz)
depends=(pixman libxcvt libXfont2 libxkbfile libdrm libpciaccess libxshmfence font-util xtrans libXau libXdmcp xkeyboard-config xkbcomp)
backup=(etc/X11/Xwrapper.config)

build() {
  mkdir -p build && cd build
  # без elogind/dbus (SysV) сервер работает от root через Xorg.wrap;
  # glamor выключен — для него нужна Mesa (добавим позже вместе с GTK)
  meson setup .. --prefix=/usr --localstatedir=/var --buildtype=release \\
        -D glamor=false -D systemd_logind=false -D suid_wrapper=true \\
        -D secure-rpc=false -D xkb_output_dir=/var/lib/xkb
  ninja -j"$JOBS"
}
package() {
  cd build && DESTDIR="$PKG" ninja install
  install -dm755 "$PKG/etc/X11/xorg.conf.d"
  cat > "$PKG/etc/X11/Xwrapper.config" << "EOF"
# без elogind X-серверу нужны права root (запуск через startx с консоли)
needs_root_rights = yes
allowed_users = console
EOF
  chmod 4755 "$PKG/usr/libexec/Xorg.wrap" 2>/dev/null || true
}
post_install() {
  install -dm1777 /tmp/.ICE-unix /tmp/.X11-unix
  grep -q '/tmp/.X11-unix' /etc/sysconfig/createfiles 2>/dev/null || cat >> /etc/sysconfig/createfiles << "EOF"
/tmp/.ICE-unix dir 1777 root root
/tmp/.X11-unix dir 1777 root root
EOF
}
''')

write("dejavu-fonts", '''
name=dejavu-fonts
version=2.37
desc="шрифты DejaVu (кириллица, моноширинный для терминала)"
source=(https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-$version.tar.bz2)
depends=(fontconfig)

build() { :; }
package() {
  install -dm755 "$PKG/usr/share/fonts/dejavu"
  install -m644 ttf/*.ttf "$PKG/usr/share/fonts/dejavu/"
}
post_install() { fc-cache -f >/dev/null 2>&1 || true; }
''')

# suckless: общая часть — пути X11 и freetype в config.mk
SL_MK = '''  sed -i -e 's#^X11INC = .*#X11INC = /usr/include#' -e 's#^X11LIB = .*#X11LIB = /usr/lib#' \\
         -e 's#^FREETYPEINC = .*#FREETYPEINC = /usr/include/freetype2#' config.mk'''

write("dwm", f'''
name=dwm
version=6.8
desc="dwm — плиточный оконный менеджер (suckless)"
source=(https://dl.suckless.org/dwm/dwm-$version.tar.gz)
depends=(libX11 libXft libXinerama)

prepare() {{
{SL_MK}
  cp config.def.h config.h
  # клавиша-модификатор — Super (Win), как в Hyprland, а не Alt
  sed -i 's/#define MODKEY Mod1Mask/#define MODKEY Mod4Mask/' config.h
  sed -i 's/"monospace:size=10"/"DejaVu Sans Mono:size=11"/g' config.h
}}
build()   {{ make; }}
package() {{ make PREFIX=/usr DESTDIR="$PKG" install; }}
''')

write("st", f'''
name=st
version=0.9.3
desc="st — простой терминал (suckless)"
source=(https://dl.suckless.org/st/st-$version.tar.gz)
depends=(libX11 libXft fontconfig)

prepare() {{
{SL_MK}
  cp config.def.h config.h
  sed -i 's/static char \\*font = .*/static char *font = "DejaVu Sans Mono:pixelsize=16:antialias=true:autohint=true";/' config.h
  # terminfo ставим сами в $PKG, а не в систему сборщика
  sed -i '/tic -sx st.info/d' Makefile
}}
build()   {{ make; }}
package() {{
  make PREFIX=/usr DESTDIR="$PKG" install
  install -dm755 "$PKG/usr/share/terminfo"
  tic -sx -o "$PKG/usr/share/terminfo" st.info
}}
''')

write("dmenu", f'''
name=dmenu
version=5.4
desc="dmenu — меню запуска программ (Super+P в dwm)"
source=(https://dl.suckless.org/tools/dmenu-$version.tar.gz)
depends=(libX11 libXft libXinerama)

prepare() {{
{SL_MK}
  cp config.def.h config.h
  sed -i 's/"monospace:size=10"/"DejaVu Sans Mono:size=11"/' config.h
}}
build()   {{ make; }}
package() {{ make PREFIX=/usr DESTDIR="$PKG" install; }}
''')

write("slstatus", f'''
name=slstatus
version=1.1
desc="slstatus — строка состояния dwm (время, батарея, память)"
source=(https://dl.suckless.org/tools/slstatus-$version.tar.gz)
depends=(libX11)

prepare() {{
  sed -i -e 's#^X11INC = .*#X11INC = /usr/include#' -e 's#^X11LIB = .*#X11LIB = /usr/lib#' config.mk
  cp config.def.h config.h
  # свой набор: процессор, память, батарея, дата-время
  python3 - << "PY"
import re
s = open("config.h").read()
args = """static const struct arg args[] = {{
	/* function format          argument */
	{{ cpu_perc,     " CPU %s%% |",  NULL }},
	{{ ram_perc,     " RAM %s%% |",  NULL }},
	{{ battery_perc, " BAT %s%% |",  "BAT1" }},
	{{ datetime,     " %s ",         "%d.%m %H:%M" }},
}};"""
s = re.sub(r"static const struct arg args\\[\\] = \\{{.*?\\n\\}};", args, s, flags=re.S)
open("config.h", "w").write(s)
PY
}}
build()   {{ make; }}
package() {{ make PREFIX=/usr DESTDIR="$PKG" install; }}
''')

write("hyprn-dwm", '''
name=hyprn-dwm
version=1.0
desc="рабочий стол Hyprn: Xorg + dwm + st + dmenu, команда startdwm"
source=()
depends=(xorg-server xf86-input-libinput xkbcomp xinit xauth setxkbmap xsetroot xrandr xset dejavu-fonts dwm st dmenu slstatus)

build() { :; }
package() {
  install -dm755 "$PKG/usr/bin" "$PKG/usr/share/hyprn"
  cat > "$PKG/usr/share/hyprn/dwm-session" << "EOF"
#!/bin/sh
# сеанс dwm (свой можно положить в ~/.xinitrc — тогда запускай просто startx)
setxkbmap -layout us,ru -option grp:alt_shift_toggle 2>/dev/null   # Alt+Shift — язык
xsetroot -solid '#1b1d2b' 2>/dev/null
xset r rate 300 40 2>/dev/null
[ -x /usr/bin/slstatus ] && slstatus &
[ -r "$HOME/.xprofile" ] && . "$HOME/.xprofile"
exec dwm
EOF
  chmod 755 "$PKG/usr/share/hyprn/dwm-session"
  cat > "$PKG/usr/bin/startdwm" << "EOF"
#!/bin/sh
# startdwm — запустить dwm из консоли (tty)
log="$HOME/.local/share/xorg-session.log"
mkdir -p "$HOME/.local/share"
tty=$(tty 2>/dev/null)
case $tty in /dev/tty[0-9]*) vt="vt${tty#/dev/tty}";; *) vt=;; esac
startx /usr/share/hyprn/dwm-session -- $vt -keeptty > "$log" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "X завершился с ошибкой ($rc). Логи: $log и /var/log/Xorg.0.log"
  tail -n 15 /var/log/Xorg.0.log 2>/dev/null | grep -E '\\(EE\\)|Fatal' || tail -n 10 "$log"
fi
exit $rc
EOF
  chmod 755 "$PKG/usr/bin/startdwm"
}
post_install() {
  echo "Готово. Войди обычным пользователем на tty и набери:  startdwm"
  echo "  Super+Shift+Enter — терминал st, Super+P — меню, Super+Shift+C — закрыть окно,"
  echo "  Super+J/K — переключать окна, Super+1..9 — рабочие столы, Super+Shift+Q — выход, Alt+Shift — язык"
}
''')

print("рецептов:", len(PKGS) + 9)

#!/usr/bin/env python3
"""Сценарий для `creeper tui` в псевдотерминале.
Запуск: tui_test.py <creeper> <CREEPER_ROOT> <ссылка на архив для мастера>"""
import fcntl, os, pty, re, select, struct, sys, termios, time

C, ROOT, URL = sys.argv[1:4]
env = dict(os.environ, CREEPER_ROOT=ROOT, TERM="xterm", LC_ALL="C.UTF-8", EDITOR="true")
pid, fd = pty.fork()
if pid == 0:
    os.execvpe(C, [C, "tui"], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
buf = ""


def pump(t=0.2):
    global buf
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                buf += os.read(fd, 65536).decode("utf-8", "replace")
            except OSError:
                return


def plain(s):
    return re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", s)


def expect(text, timeout=25, what=None):
    global buf
    end = time.time() + timeout
    while time.time() < end:
        pump(0.1)
        if text in plain(buf):
            return
    print("НЕ ДОЖДАЛСЯ: %s (%s)\n--- экран ---\n%s" % (text, what or "", plain(buf)[-1500:]))
    os.kill(pid, 9)
    sys.exit(1)


def send(keys, pause=0.3):
    global buf
    buf = ""
    os.write(fd, keys.encode())
    pump(pause)


UP, DOWN, END, ESC, TAB = "\x1b[A", "\x1b[B", "\x1b[F", "\x1b", "\t"

expect("установлено 0", what="главный экран")
expect("hello")
expect("zeta")
send("i"); expect("Поставить: hello?")
send("y"); expect("готово", 60, "установка hello")
send("\r"); expect("установлено 2", what="после установки")
send("/"); expect("Поиск")
send("zeta\r"); expect("поиск: zeta")
send(ESC, 0.5); expect("hello", what="сброс поиска")
send(TAB); expect("world", what="вкладка установленных")
send("\r"); expect("Взорвать (удалить)", what="меню действий")
send(ESC, 0.5); expect("установлено 2")
send(" "); expect("отмечено 1", what="отметка пробелом")
send(ESC, 0.5)
send("?"); expect("клавиши"); send("x"); expect("установлено 2")
send("т"); expect("Новый пакет", what="русская раскладка: т = n")
send(URL + "\r"); expect("проверь, поправь", 40, "форма мастера")
expect("Сборка:       make")
expect("Имя:          plain")
send(END + UP * 4); expect("> Сохранить и собрать здесь")
send("\r"); expect("готово", 30, "add")
send("\r"); expect("готово", 60, "сборка своего пакета")
send("\r"); expect("установлено 3")
send("й")                       # русская раскладка: й = q
for _ in range(50):
    p, st = os.waitpid(pid, os.WNOHANG)
    if p:
        sys.exit(0 if os.WEXITSTATUS(st) == 0 else 2)
    pump(0.1)
print("TUI не вышел по q\n" + plain(buf)[-800:])
os.kill(pid, 9)
sys.exit(1)

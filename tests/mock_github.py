#!/usr/bin/env python3
"""Подставной GitHub API для тестов `creeper farm`.

Запуск: mock_github.py <порт> <токен> <каталог-репозитория-бинарников> <каталог-готовых-бинарников> [fail]
- проверяет заголовок Authorization: Bearer <токен>
- contents API для recipes/<имя>/recipe (хранит в памяти)
- dispatches → создаёт запуск, который за 3 опроса проходит queued → in_progress → completed;
  при успехе «публикует» бинарники: копирует <готовые>/* в <репозиторий> и дописывает index.txt
- fail: запуск завершается с failure и логом с ошибкой creeper
"""
import base64, hashlib, json, os, shutil, sys, re
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT, TOKEN, REPO_DIR, READY_DIR = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
FAIL = len(sys.argv) > 5 and sys.argv[5] == "fail"
recipes = {}          # имя -> bytes
runs = []             # список dict
polls = {}
next_id = [1000]
log_calls = []


def blob_sha(b):
    return hashlib.sha1(b"blob %d\0" % len(b) + b).hexdigest()


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, obj=None, raw=None, ctype="application/json"):
        body = raw if raw is not None else json.dumps(obj or {}).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def auth(self):
        if self.headers.get("Authorization") != "Bearer " + TOKEN:
            self.send(401, {"message": "Bad credentials"})
            return False
        return True

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def do_GET(self):
        if not self.auth():
            return
        path = self.path.split("?")[0]
        log_calls.append("GET " + path)
        m = re.fullmatch(r"/repos/([^/]+/[^/]+)", path)
        if m:
            return self.send(200, {"full_name": m.group(1), "permissions": {"push": True}})
        m = re.fullmatch(r"/repos/[^/]+/[^/]+/contents/recipes/([^/]+)/recipe", path)
        if m:
            b = recipes.get(m.group(1))
            return self.send(200, {"sha": blob_sha(b)}) if b is not None else self.send(404, {"message": "Not Found"})
        if re.fullmatch(r"/repos/[^/]+/[^/]+/actions/workflows/build.yml/runs", path):
            out = []
            for r in reversed(runs):
                out.append({"id": r["id"], "event": "workflow_dispatch", "status": r["status"],
                            "conclusion": r["conclusion"], "created_at": "2026-11-05T18:00:00Z",
                            "display_title": "build: " + r["packages"]})
            return self.send(200, {"workflow_runs": out})
        m = re.fullmatch(r"/repos/[^/]+/[^/]+/actions/runs/(\d+)", path)
        if m:
            r = self.advance(int(m.group(1)))
            return self.send(200, {"id": r["id"], "status": r["status"], "conclusion": r["conclusion"]})
        m = re.fullmatch(r"/repos/[^/]+/[^/]+/actions/runs/(\d+)/jobs", path)
        if m:
            r = next(x for x in runs if x["id"] == int(m.group(1)))
            st = "in_progress" if r["status"] == "in_progress" else "completed"
            return self.send(200, {"jobs": [{"id": r["id"] * 10, "conclusion": r["conclusion"],
                                             "steps": [{"name": "Сборка", "status": st}]}]})
        m = re.fullmatch(r"/repos/[^/]+/[^/]+/actions/jobs/(\d+)/logs", path)
        if m:
            txt = ("2026-11-05T18:00:01.0000000Z ==> будет установлено: x[сборка]\n"
                   "2026-11-05T18:00:02.0000000Z xx> x: шаг 'build' упал (код 2). Полный лог: creeper log x\n"
                   "2026-11-05T18:00:02.0000000Z ##[error]Process completed with exit code 1.\n")
            return self.send(200, raw=txt.encode(), ctype="text/plain")
        self.send(404, {"message": "Not Found"})

    def advance(self, rid):
        r = next(x for x in runs if x["id"] == rid)
        polls[rid] = polls.get(rid, 0) + 1
        if r["status"] == "queued":
            r["status"] = "in_progress"
        elif r["status"] == "in_progress" and polls[rid] >= 3:
            r["status"] = "completed"
            r["conclusion"] = "failure" if FAIL else "success"
            if not FAIL:
                self.publish(r["packages"].split())
        return r

    def publish(self, pkgs):
        idx = os.path.join(REPO_DIR, "index.txt")
        lines = open(idx).read().splitlines() if os.path.exists(idx) else []
        for f in os.listdir(READY_DIR):
            name = f.rsplit("-", 2)[0]
            if name not in pkgs:
                continue
            shutil.copy(os.path.join(READY_DIR, f), REPO_DIR)
            ver, rel = f[len(name) + 1:-len(".tar.zst")].rsplit("-", 1)
            sha = hashlib.sha256(open(os.path.join(REPO_DIR, f), "rb").read()).hexdigest()
            lines = [l for l in lines if l.split()[4] != f] + ["%s %s %s %s %s" % (name, ver, rel, sha, f)]
        open(idx, "w").write("\n".join(sorted(lines)) + "\n")

    def do_POST(self):
        if not self.auth():
            return
        if self.path.endswith("/dispatches"):
            b = self.body()
            assert b["ref"] == "main", b
            next_id[0] += 1
            runs.append({"id": next_id[0], "status": "queued", "conclusion": None,
                         "packages": b["inputs"]["packages"], "rebuild": b["inputs"]["rebuild"]})
            return self.send(204, raw=b"")
        self.send(404, {"message": "Not Found"})

    def do_PUT(self):
        if not self.auth():
            return
        m = re.fullmatch(r"/repos/[^/]+/[^/]+/contents/recipes/([^/]+)/recipe", self.path)
        if not m:
            return self.send(404, {"message": "Not Found"})
        b = self.body()
        name = m.group(1)
        if name in recipes and b.get("sha") != blob_sha(recipes[name]):
            return self.send(409, {"message": "sha mismatch"})
        recipes[name] = base64.b64decode(b["content"])
        self.send(201, {"content": {"sha": blob_sha(recipes[name])}})


HTTPServer(("127.0.0.1", PORT), H).serve_forever()

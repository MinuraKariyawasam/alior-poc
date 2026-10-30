#!/usr/bin/env python3
"""Mock backend for the PoD. Stdlib only.

  mock.py --port 8081 --version v1

Serves /transfers, /transfers/instant, /accounts, /legacy/accounts, /healthz on any method.
Behaviour headers (from CLAUDE.md conventions):
  x-mock-delay-ms: <n>   sleep n ms before answering
  x-mock-status: <code>  answer with that HTTP status
Response is JSON with the version, path, method, host and request body size.
"""
import argparse, hashlib, json, socket, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "v1"
PATHS = ("/transfers", "/transfers/instant", "/accounts", "/legacy/accounts", "/healthz")

class H(BaseHTTPRequestHandler):
    def _any(self):
        n = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(n) if n else b""
        delay = int(self.headers.get("x-mock-delay-ms") or 0)
        if delay: time.sleep(delay / 1000)
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        status = int(self.headers.get("x-mock-status") or (200 if path in PATHS else 404))
        out = {"service": "mock", "version": VERSION, "path": path, "method": self.command,
               "host": socket.gethostname(), "port": self.server.server_port,
               "body_bytes": n, "body_md5": hashlib.md5(body).hexdigest() if n else None,
               "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        data = json.dumps(out).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.send_header("x-mock-version", VERSION)
        self.end_headers()
        self.wfile.write(data)
    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_OPTIONS = _any
    def log_message(self, fmt, *a): sys.stderr.write("%s %s\n" % (self.address_string(), fmt % a))

if __name__ == "__main__":
    p = argparse.ArgumentParser(); p.add_argument("--port", type=int, default=8080); p.add_argument("--version", default="v1")
    a = p.parse_args(); VERSION = a.version
    ThreadingHTTPServer(("0.0.0.0", a.port), H).serve_forever()

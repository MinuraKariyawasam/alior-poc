#!/usr/bin/env python3
"""Tiny logging HTTP forward proxy for PoD 1.6 (CONNECT + plain GET/POST). stdlib only, one line per request on stdout.
ponytail: single-threaded-per-connection ThreadingHTTPServer, no auth, no caching; tinyproxy/squid if this ever matters."""
import http.server, socket, socketserver, sys, threading, urllib.request

class Proxy(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *a): sys.stdout.write("proxy %s %s\n" % (self.client_address[0], fmt % a)); sys.stdout.flush()
    def do_CONNECT(self):
        host, _, port = self.path.partition(":")
        try: up = socket.create_connection((host, int(port or 443)), timeout=10)
        except OSError as e: self.send_error(502, str(e)); return
        self.log_message("CONNECT %s", self.path)
        self.send_response(200, "Connection established"); self.end_headers()
        def pump(a, b):
            try:
                while True:
                    d = a.recv(65536)
                    if not d: break
                    b.sendall(d)
            except OSError: pass
            finally:
                try: b.shutdown(socket.SHUT_WR)
                except OSError: pass
        t = threading.Thread(target=pump, args=(self.connection, up), daemon=True); t.start(); pump(up, self.connection); t.join()
    def _plain(self):
        n = int(self.headers.get("Content-Length") or 0); body = self.rfile.read(n) if n else None
        req = urllib.request.Request(self.path, data=body, method=self.command, headers={k: v for k, v in self.headers.items() if k.lower() not in ("proxy-connection", "connection")})
        self.log_message("%s %s", self.command, self.path)
        try:
            with urllib.request.urlopen(req, timeout=15) as r: data = r.read(); self.send_response(r.status); [self.send_header(k, v) for k, v in r.headers.items() if k.lower() != "transfer-encoding"]; self.end_headers(); self.wfile.write(data)
        except urllib.error.HTTPError as e: self.send_response(e.code); self.end_headers(); self.wfile.write(e.read())
        except Exception as e: self.send_error(502, str(e))
    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = _plain

class S(socketserver.ThreadingMixIn, http.server.HTTPServer): daemon_threads = True
if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 3128
    print("proxy listening on", port, flush=True); S(("0.0.0.0", port), Proxy).serve_forever()

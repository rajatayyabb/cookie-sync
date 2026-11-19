# Cookie Sync

> **Security notice:** This repository contains browser-cookie collection and transfer utilities. Browser cookies can act as bearer credentials and may provide access to personal or business accounts. Use this code only on systems you own or are explicitly authorized to test. Never collect, transmit, or store real credentials without documented authorization.

Cookie Sync is a Windows-focused toolkit containing two separate utilities for security testing and controlled lab environments:

- **CookieDrop** — a one-shot collection workflow.
- **CookieSync** — a sender/receiver workflow intended for authorized testing between machines on the same network.

The tools do not share application code.

## Repository layout

```text
.
├── LICENSE
├── README.md
├── cookiedrop/
│   ├── README.md
│   ├── RUN.bat
│   ├── build-sfx.ps1
│   ├── config.example.json
│   └── cookies.ps1
└── cookiesync/
    ├── README.md
    ├── config.example.json
    ├── requirements.txt
    ├── receiver/
    │   ├── install_autostart.bat
    │   ├── receiver.py
    │   ├── start_receiver.bat
    │   └── uninstall_autostart.bat
    └── sender/
        ├── fetch_and_run.bat
        ├── run.bat
        └── sender.py
```

## Choose the relevant component

| Component | Purpose | Documentation |
|---|---|---|
| `cookiedrop/` | Single-machine collection workflow | [`cookiedrop/README.md`](cookiedrop/README.md) |
| `cookiesync/` | Sender/receiver workflow for an authorized lab | [`cookiesync/README.md`](cookiesync/README.md) |

## Important handling requirements

- Obtain written authorization before running any component.
- Use a disposable test account and an isolated test machine whenever possible.
- Do not use production browser profiles or collect cookies belonging to another person.
- Treat every generated file as a credential-bearing artifact.
- Do not upload dumps to public storage, chat services, email, or third-party systems.
- Restrict permissions on local test output and securely delete it after the test.
- Do not enable persistence or firewall changes unless explicitly required by the approved test plan.
- Revoke test sessions and rotate affected credentials after testing.

## Responsible use

This project is not intended for malware, surveillance, account takeover, credential theft, or unauthorized access. If you discover unexpected cookie access on a device, preserve relevant evidence, disconnect the device from untrusted networks, revoke active sessions, rotate credentials, and follow your organization’s incident-response process.

## License

MIT — see [`LICENSE`](LICENSE).

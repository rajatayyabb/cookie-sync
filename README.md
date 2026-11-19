<div align="center">

# Cookie Sync

### A controlled security-testing toolkit for browser-session artifact research

[![Platform](https://img.shields.io/badge/platform-Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/rajatayyabb/cookie-sync)
[![Language](https://img.shields.io/badge/code-Python%20%7C%20PowerShell-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://github.com/rajatayyabb/cookie-sync)
[![License](https://img.shields.io/badge/license-MIT-2ea44f?style=for-the-badge)](LICENSE)
[![Use](https://img.shields.io/badge/use-authorized%20labs%20only-dc3545?style=for-the-badge)](#security-first)

**Cookie Sync** contains two separate Windows-oriented utilities for controlled, authorized security testing. It is designed for isolated lab environments—not for personal browsing profiles, production systems, or other people’s accounts.

</div>

> [!CAUTION]
> **Browser cookies are bearer credentials.** Treat every generated artifact as sensitive authentication material. Use only disposable test accounts, isolated machines, and written authorization. Never use this project to access, monitor, or transfer another person’s sessions.

## What’s inside

| Component | Focus | Guide |
|:--|:--|:--|
| `cookiedrop/` | One-shot local collection workflow | [`cookiedrop/README.md`](cookiedrop/README.md) |
| `cookiesync/` | Sender/receiver workflow for an authorized LAN lab | [`cookiesync/README.md`](cookiesync/README.md) |

The components are independent and do not share application code.

## Architecture at a glance

```text
┌──────────────────────────────┐       ┌──────────────────────────────┐
│        COOKIEDROP             │       │         COOKIESYNC             │
│                              │       │                              │
│  Controlled test machine     │       │  Authorized source machine   │
│  └─ local test workflow      │       │  └─ sender                    │
│                              │       │          │                   │
│  Lab-only output handling    │       │          ▼                   │
│                              │       │  Authorized receiver machine │
│                              │       │  └─ receiver                  │
└──────────────────────────────┘       └──────────────────────────────┘
```

## Repository map

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

## Security-first

Before any authorized assessment:

- Obtain written permission and define the exact scope.
- Use a disposable account with no access to real services or sensitive data.
- Use an isolated VM or dedicated lab machine—not a daily-use computer.
- Keep generated files local, access-controlled, time-limited, and encrypted where appropriate.
- Do not send artifacts to Telegram, email, public storage, or untrusted third parties.
- Do not enable persistence, firewall changes, or startup behavior unless the approved test plan requires it.
- Revoke test sessions, rotate test credentials, and securely delete artifacts when finished.

### If you found unexpected cookie access

1. Disconnect the affected device from untrusted networks.
2. Revoke active sessions for impacted accounts.
3. Rotate passwords and review MFA/recovery settings.
4. Preserve relevant evidence for your security team.
5. Follow your organization’s incident-response process.

## Responsible use

This repository is not intended for malware, surveillance, credential theft, account takeover, or unauthorized access. The maintainers do not endorse collecting real credentials or operating against systems without explicit authorization.

## License

Released under the MIT License. See [`LICENSE`](LICENSE).

<div align="center">

**Read the safety guidance before opening or running any component.**

</div>

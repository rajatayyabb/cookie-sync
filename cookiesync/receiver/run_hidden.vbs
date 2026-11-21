Set sh = CreateObject("WScript.Shell")
p = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
sh.CurrentDirectory = p & "..\"
sh.Run "cmd /c set PY=python& python receiver\receiver.py --quiet", 0, False
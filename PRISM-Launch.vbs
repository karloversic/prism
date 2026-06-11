' PRISM-Launch.vbs - flash-free PowerShell launcher.
' wscript.exe runs in the GUI subsystem, so no console window is ever created
' for the launcher itself, and both launch paths below create the powershell
' console hidden from the first frame (SW_HIDE at process creation) - unlike
' "powershell -WindowStyle Hidden", which creates a visible console and hides
' it a moment later (the "flash").
'
' Usage: wscript.exe PRISM-Launch.vbs <user|runas> <script.ps1> [extra args...]
Option Explicit
Dim args, mode, target, extra, i, psArgs
Set args = WScript.Arguments
If args.Count < 2 Then WScript.Quit 1
mode   = LCase(args(0))
target = args(1)
extra  = ""
For i = 2 To args.Count - 1
    extra = extra & " " & args(i)
Next
psArgs = "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File """ & target & """" & extra
On Error Resume Next  ' a cancelled UAC prompt raises here; exit quietly instead of a script-error popup
If mode = "runas" Then
    CreateObject("Shell.Application").ShellExecute "powershell.exe", psArgs, "", "runas", 0
Else
    CreateObject("WScript.Shell").Run "powershell.exe " & psArgs, 0, False
End If

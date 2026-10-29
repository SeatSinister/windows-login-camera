# Windows Login Camera

Takes a webcam photo after a wrong password at the Windows sign-in or unlock screen. Files are saved locally in **Documents/Windows Login Camera** with date and time in the filename. No photo is uploaded. The program does not impose a retry limit or lockout timer.

## Requirements

- Windows 10 or 11 and an available webcam.
- Administrator rights to install the event task.
- FFmpeg with DirectShow support. Install with `winget install --id Gyan.FFmpeg --exact`, then reopen PowerShell.
- Camera access enabled under Windows Settings → Privacy & security → Camera, including desktop apps.

Find the camera name in Windows PowerShell:

```powershell
ffmpeg -list_devices true -f dshow -i dummy
```

Run PowerShell **as Administrator** in this project folder, replacing the example camera name with the exact listed name:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install.ps1 -CameraName 'Integrated Camera'
```

The installer takes test photos as your account and as SYSTEM, enables failed logon auditing, and registers a Windows event task. Then lock Windows and enter an incorrect password once. Check **Documents/Windows Login Camera** for a JPG. If no photo appears, read `errors.log` and the timestamped `.ffmpeg.log` there. Only the locked-screen test proves capture works while Windows is locked. Some cameras or Windows privacy settings may block background capture.

The task starts only when Windows writes Security event 4625. The script accepts interactive logon types 2, 7, and 11 and wrong-password status `0xC000006A`. PIN and Windows Hello behavior may differ across devices and might not produce this status. There is no resident process at idle. FFmpeg starts briefly per failed attempt, so several simultaneous failures may briefly use more memory.

To remove the task, run `Uninstall.ps1` as Administrator. It keeps photos and Windows audit settings.

## Privacy

Only use this on a computer you own or administer, and tell other users about the camera. Photos can contain personal information. The task runs as SYSTEM so it can read the Security event log; review the script before installing it. Keep the photo folder private and delete old photos when no longer needed.

## Technical references

- [Windows event 4625](https://learn.microsoft.com/windows/security/threat-protection/auditing/event-4625)
- [Task Scheduler event triggers and ValueQueries](https://learn.microsoft.com/en-us/windows/win32/taskschd/taskschedulerschema-valuequeries-eventtriggertype-element)
- [Windows camera privacy](https://learn.microsoft.com/en-us/windows/apps/develop/camera/camera-privacy-setting)

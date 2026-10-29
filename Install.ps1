param(
    [Parameter(Mandatory=$true)] [string] $CameraName,
    [string] $FFmpegPath = 'ffmpeg.exe'
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Windows PowerShell as Administrator.'
}

$ffmpegCommand = Get-Command $FFmpegPath -ErrorAction Stop
$ffmpeg = $ffmpegCommand.Source
$documents = [Environment]::GetFolderPath('MyDocuments')
if (-not $documents) { throw 'Documents folder could not be located.' }
$output = Join-Path $documents 'Windows Login Camera'
$installDir = Join-Path $env:ProgramData 'WindowsLoginCamera'
$taskName = 'WindowsLoginCamera'
$captureScript = Join-Path $installDir 'Capture-FailedLogin.ps1'

# Verify the camera as the installing user before changing system settings.
New-Item -ItemType Directory -Path $installDir, $output -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Capture-FailedLogin.ps1') -Destination $captureScript -Force
@{ CameraName=$CameraName; FFmpegPath=$ffmpeg; OutputDirectory=$output } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $installDir 'config.json') -Encoding UTF8
& "$env:SystemRoot\System32\icacls.exe" $installDir /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect the installation directory.' }
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $captureScript -SelfTest
if ($LASTEXITCODE -ne 0) { throw "Camera test failed. Read $output\errors.log" }

# Audit Logon (GUID is language-independent); Windows then writes Security event 4625.
& "$env:SystemRoot\System32\auditpol.exe" /set /subcategory:'{0CCE9215-69AE-11D9-BED3-505054503030}' /failure:enable
if ($LASTEXITCODE -ne 0) { throw 'Could not enable failed logon auditing.' }

$escapedScript = [Security.SecurityElement]::Escape($captureScript)
$subscription = [Security.SecurityElement]::Escape("<QueryList><Query Id='0' Path='Security'><Select Path='Security'>*[System[(EventID=4625)]]</Select></Query></QueryList>")
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Take a webcam photo after a wrong interactive Windows password.</Description></RegistrationInfo>
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>$subscription</Subscription>
      <ValueQueries><Value name="EventRecordID">Event/System/EventRecordID</Value></ValueQueries>
    </EventTrigger>
  </Triggers>
  <Principals><Principal id="System"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>Queue</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT30S</ExecutionTimeLimit>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="System"><Exec>
    <Command>$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe</Command>
    <Arguments>-NoProfile -ExecutionPolicy Bypass -File &quot;$escapedScript&quot; -RecordId `$(EventRecordID)</Arguments>
  </Exec></Actions>
</Task>
"@
$taskXml = Join-Path $installDir 'task.xml'
$xml | Set-Content -LiteralPath $taskXml -Encoding Unicode
& "$env:SystemRoot\System32\schtasks.exe" /Create /F /TN $taskName /XML $taskXml
if ($LASTEXITCODE -ne 0) { throw 'Could not register the event task.' }

# Confirm that SYSTEM, the task's actual account, can access the camera.
$testTask = 'WindowsLoginCameraSelfTest'
$testAction = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$captureScript`" -SelfTest"
$testTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(10)
$testSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds 30) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$oldTest = @(Get-ChildItem -LiteralPath $output -Filter '*_test.jpg' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
try {
    Register-ScheduledTask -TaskName $testTask -Action $testAction -Trigger $testTrigger -Settings $testSettings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
    Start-ScheduledTask -TaskName $testTask
    $deadline = (Get-Date).AddSeconds(30)
    do {
        Start-Sleep -Seconds 1
        $newTest = @(Get-ChildItem -LiteralPath $output -Filter '*_test.jpg' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notin $oldTest })
        if ($newTest.Count -gt 0) { break }
    } while ((Get-Date) -lt $deadline)
    if ($newTest.Count -eq 0) { throw "SYSTEM camera test failed. Read $output\errors.log" }
} catch {
    & "$env:SystemRoot\System32\schtasks.exe" /Delete /F /TN $taskName | Out-Null
    throw
} finally {
    Unregister-ScheduledTask -TaskName $testTask -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Host "Installed. Test photo: $output"
Write-Host 'Now lock Windows and try a wrong password once. Check for a new JPG or errors.log.'

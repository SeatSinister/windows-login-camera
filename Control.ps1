param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('on', 'off', 'status')]
    [string] $Action
)

$ErrorActionPreference = 'Stop'
$taskName = 'WindowsLoginCamera'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open Windows PowerShell as Administrator to manage Windows Login Camera.'
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -eq $task) {
    throw 'Windows Login Camera is not installed. Run Install.ps1 first.'
}

switch ($Action) {
    'on' {
        Enable-ScheduledTask -TaskName $taskName | Out-Null
        Write-Host 'Windows Login Camera: включено. Состояние сохранится после перезагрузки.'
    }
    'off' {
        Disable-ScheduledTask -TaskName $taskName | Out-Null
        if ($task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop
        }
        Write-Host 'Windows Login Camera: выключено. Состояние сохранится после перезагрузки.'
    }
    'status' {
        if ($task.State -eq 'Disabled' -or -not $task.Settings.Enabled) {
            Write-Host 'Windows Login Camera: выключено.'
        } else {
            Write-Host 'Windows Login Camera: включено.'
        }
    }
}

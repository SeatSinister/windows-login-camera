$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Windows PowerShell as Administrator.'
}
& "$env:SystemRoot\System32\schtasks.exe" /Delete /F /TN 'WindowsLoginCamera'
if ($LASTEXITCODE -ne 0) { throw 'Could not delete scheduled task.' }
Remove-Item -LiteralPath (Join-Path $env:ProgramData 'WindowsLoginCamera') -Recurse -Force
Write-Host 'Task removed. Photos and the Windows audit policy were left untouched.'

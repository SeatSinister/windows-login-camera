param(
    [long] $RecordId = 0,
    [switch] $SelfTest
)

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot 'config.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$output = [string] $config.OutputDirectory
$ffmpeg = [string] $config.FFmpegPath
$camera = [string] $config.CameraName

function Write-CaptureError([string] $message) {
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    Add-Content -LiteralPath (Join-Path $output 'errors.log') -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $message) -Encoding UTF8
}

try {
    if (-not (Test-Path -LiteralPath $ffmpeg -PathType Leaf)) { throw 'FFmpeg was not found.' }
    if ([string]::IsNullOrWhiteSpace($camera)) { throw 'Camera name is empty.' }

    if (-not $SelfTest) {
        if ($RecordId -le 0) { throw 'Missing event record ID.' }
        $xpath = "*[System[(EventID=4625) and (EventRecordID=$RecordId)]]"
        $event = Get-WinEvent -LogName Security -FilterXPath $xpath -MaxEvents 1 -ErrorAction Stop
        if (-not $event) { throw "Security event $RecordId was not found." }
        [xml] $eventXml = $event.ToXml()
        $data = @{}
        foreach ($field in $eventXml.Event.EventData.Data) { $data[[string]$field.Name] = [string]$field.InnerText }
        # Interactive sign-in, unlock, and cached interactive sign-in only.
        if ($data.LogonType -notin @('2', '7', '11')) { exit 0 }
        # Wrong password or PIN. Other logon failures are ignored.
        if ($data.SubStatus -ne '0xc000006a' -and $data.Status -ne '0xc000006a') { exit 0 }
        $when = $event.TimeCreated
    } else {
        $when = Get-Date
    }

    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $stamp = $when.ToString('yyyy-MM-dd_HH-mm-ss-fff')
    $suffix = if ($SelfTest) { 'test' } else { "event-$RecordId" }
    $image = Join-Path $output "$stamp`_$suffix.jpg"

    # A separate process runs only for an event; no background polling or RAM use at idle.
    $cameraArg = '"video=' + $camera.Replace('"', '\"') + '"'
    $imageArg = '"' + $image.Replace('"', '\"') + '"'
    $args = @('-hide_banner', '-loglevel', 'error', '-y', '-f', 'dshow', '-i', $cameraArg, '-ss', '1', '-frames:v', '1', '-q:v', '3', $imageArg)
    $errorFile = "$image.ffmpeg.log"
    $process = Start-Process -FilePath $ffmpeg -ArgumentList $args -Wait -PassThru -NoNewWindow -RedirectStandardError $errorFile
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $image)) {
        throw "Camera capture failed (FFmpeg exit code $($process.ExitCode)). See $errorFile."
    }
    Remove-Item -LiteralPath $errorFile -Force
} catch {
    Write-CaptureError $_.Exception.Message
    exit 1
}

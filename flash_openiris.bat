@echo off
set "SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "& {$f=$env:SELF;$c=[IO.File]::ReadAllText($f,[Text.Encoding]::UTF8);$ps=($c -split '##PS##\r?\n',2)[1];$t=$env:TEMP+'\oi_'+[IO.Path]::GetRandomFileName()+'.ps1';[IO.File]::WriteAllText($t,$ps,[Text.Encoding]::UTF8);try{& $t}finally{ri $t -Force -EA 0}}"
exit /b
##PS##
#Requires -Version 5.1
# OpenIris Firmware Flasher
# https://github.com/yayokorea/OpenIris

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ── 출력 헬퍼 ───────────────────────────────────────────────────────────────
function Write-Header { param($msg) Write-Host "`n╔══ $msg" -ForegroundColor Cyan }
function Write-Ok     { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn   { param($msg) Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Fail   { param($msg) Write-Host "  [X]  $msg" -ForegroundColor Red }
function Write-Info   { param($msg) Write-Host "       $msg" -ForegroundColor Gray }
function Pause-Exit   { param($msg) Write-Fail $msg; Read-Host "`n아무 키나 눌러 종료"; exit 1 }

# ── --no-stub 필요 보드 목록 ─────────────────────────────────────────────────
$NO_STUB_ENVS = @(
    "wrooms3QIO",        "wrooms3QIO_release",
    "wrooms3USB",        "wrooms3USB_release",
    "wrooms3QIOUSB",     "wrooms3QIOUSB_release",
    "Babble-wrooms-s3",  "Babble-wrooms-s3_release",
    "Babble_USB-wrooms-s3", "Babble_USB-wrooms-s3_release",
    "xiaosenses3_USB",   "xiaosenses3_USB_release"
)

Write-Host ""
Write-Host "  ██████╗ ██████╗ ███████╗███╗   ██╗    ██╗██████╗ ██╗███████╗" -ForegroundColor Cyan
Write-Host "  ██╔══██╗██╔══██╗██╔════╝████╗  ██║    ██║██╔══██╗██║██╔════╝" -ForegroundColor Cyan
Write-Host "  ██║  ██║██████╔╝█████╗  ██╔██╗ ██║    ██║██████╔╝██║███████╗" -ForegroundColor Cyan
Write-Host "  ██║  ██║██╔═══╝ ██╔══╝  ██║╚██╗██║    ██║██╔══██╗██║╚════██║" -ForegroundColor Cyan
Write-Host "  ██████╔╝██║     ███████╗██║ ╚████║    ██║██║  ██║██║███████║" -ForegroundColor Cyan
Write-Host "  ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝    ╚═╝╚═╝  ╚═╝╚═╝╚══════╝" -ForegroundColor Cyan
Write-Host "                     OpenIris Firmware Flasher" -ForegroundColor White
Write-Host ""

# ════════════════════════════════════════════════════════════════════════════
# 1. 의존성 확인 및 설치
# ════════════════════════════════════════════════════════════════════════════
Write-Header "환경 확인"

function Find-Python {
    foreach ($cmd in @("python", "python3", "py")) {
        try {
            $ver = & $cmd --version 2>&1
            if ($ver -match "Python 3\.(\d+)") {
                $minor = [int]$Matches[1]
                if ($minor -ge 8) { return $cmd }
            }
        } catch {}
    }
    return $null
}

$pythonCmd = Find-Python

if (-not $pythonCmd) {
    Write-Warn "Python 3.8+ 이 설치되어 있지 않습니다. 자동 설치를 시도합니다..."
    Write-Host ""

    $installed = $false

    # 방법 1: winget
    try {
        $null = Get-Command winget -ErrorAction Stop
        Write-Info "winget 으로 Python 3.12 설치 중..."
        $result = Start-Process -FilePath "winget" `
            -ArgumentList "install --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements" `
            -Wait -PassThru -NoNewWindow
        if ($result.ExitCode -eq 0) { $installed = $true }
    } catch {
        Write-Info "winget 사용 불가"
    }

    # 방법 2: 직접 다운로드
    if (-not $installed) {
        Write-Info "Python 설치 파일 다운로드 중 (python-3.12.7-amd64.exe)..."
        $installer = "$env:TEMP\python_setup.exe"
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest `
                -Uri "https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe" `
                -OutFile $installer -UseBasicParsing
            Write-Info "설치 중 (조용한 모드)..."
            $result = Start-Process -FilePath $installer `
                -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 Include_test=0" `
                -Wait -PassThru
            if ($result.ExitCode -eq 0) { $installed = $true }
            Remove-Item $installer -Force -ErrorAction SilentlyContinue
        } catch {
            Pause-Exit "Python 다운로드 실패: $_`n수동으로 https://www.python.org 에서 설치 후 재실행하세요."
        }
    }

    # PATH 갱신
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH","User")

    $pythonCmd = Find-Python
    if (-not $pythonCmd) {
        Pause-Exit "Python 설치 후에도 명령어를 찾을 수 없습니다.`n터미널을 다시 열고 재실행하거나, 수동으로 Python 을 설치하세요."
    }
}

$pyVer = & $pythonCmd --version 2>&1
Write-Ok "Python: $pyVer  ($pythonCmd)"

# esptool 확인
$esptoolOk = $false
try {
    $etVer = & $pythonCmd -m esptool version 2>&1 | Select-Object -First 1
    if ($etVer -match "esptool") { $esptoolOk = $true }
} catch {}

if (-not $esptoolOk) {
    Write-Info "esptool 설치 중..."
    & $pythonCmd -m pip install esptool --quiet
    if ($LASTEXITCODE -ne 0) { Pause-Exit "esptool 설치 실패" }
    Write-Ok "esptool 설치 완료"
} else {
    Write-Ok "esptool: $etVer"
}

# ════════════════════════════════════════════════════════════════════════════
# 2. GitHub 릴리즈 선택
# ════════════════════════════════════════════════════════════════════════════
Write-Header "릴리즈 선택"

try {
    $releases = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/yayokorea/OpenIris/releases" `
        -Headers @{ "User-Agent" = "OpenIris-Flasher/1.0"; "Accept" = "application/vnd.github+json" }
} catch {
    Pause-Exit "GitHub API 요청 실패: $_"
}

if ($releases.Count -eq 0) { Pause-Exit "릴리즈를 찾을 수 없습니다." }

Write-Host ""
$showCount = [Math]::Min($releases.Count, 10)
for ($i = 0; $i -lt $showCount; $i++) {
    $r   = $releases[$i]
    $tag = $r.tag_name.PadRight(14)
    $dt  = ([datetime]$r.published_at).ToString("yyyy-MM-dd")
    $pre = if ($r.prerelease) { "  [pre-release]" } else { "" }
    Write-Host "  [$($i+1)] $tag  $dt$pre"
}

Write-Host ""
do {
    $input = Read-Host "릴리즈 번호 선택"
    $idx   = [int]$input - 1
} while ($idx -lt 0 -or $idx -ge $showCount)

$release = $releases[$idx]
Write-Ok "선택됨: $($release.tag_name)"

# ════════════════════════════════════════════════════════════════════════════
# 3. 설치 유형 선택
# ════════════════════════════════════════════════════════════════════════════
Write-Header "설치 유형"
Write-Host ""
Write-Host "  [1] 초기설치 (Full Flash)" -ForegroundColor Yellow
Write-Host "      부트로더 + 파티션 + 앱을 통째로 설치합니다." -ForegroundColor Gray
Write-Host "      처음 설치하거나 완전히 초기화할 때 사용하세요." -ForegroundColor Gray
Write-Host ""
Write-Host "  [2] 업데이트 (App Update)" -ForegroundColor Yellow
Write-Host "      앱 파티션(0x10000)만 덮어씁니다." -ForegroundColor Gray
Write-Host "      이미 OpenIris 가 설치된 기기의 펌웨어만 교체할 때 사용하세요." -ForegroundColor Gray
Write-Host ""

do {
    $installType = Read-Host "선택 (1 또는 2)"
} while ($installType -ne "1" -and $installType -ne "2")

$isFullInstall = ($installType -eq "1")
$filterExt     = if ($isFullInstall) { ".zip" } else { ".bin" }
$typeLabel     = if ($isFullInstall) { "초기설치 (Full Flash)" } else { "업데이트 (App Update)" }
Write-Ok "선택됨: $typeLabel"

# ════════════════════════════════════════════════════════════════════════════
# 4. 보드 / 파일 선택
# ════════════════════════════════════════════════════════════════════════════
Write-Header "보드 선택"

$assets = @($release.assets | Where-Object { $_.name.EndsWith($filterExt) })
if ($assets.Count -eq 0) { Pause-Exit "이 릴리즈에 '$filterExt' 파일이 없습니다." }

function Get-PioEnv { param($name) return ($name -replace '-v\d+\.\d+\.\d+.*', '') }

Write-Host ""
for ($i = 0; $i -lt $assets.Count; $i++) {
    $a    = $assets[$i]
    $env  = Get-PioEnv $a.name
    $kb   = [Math]::Round($a.size / 1024, 0)
    $note = if ($env.EndsWith("_release")) { " [릴리즈 빌드]" } else { " [디버그 빌드]" }
    Write-Host "  [$($i+1)] $($a.name.PadRight(60)) $($kb.ToString().PadLeft(6)) KB$note"
}

Write-Host ""
do {
    $input = Read-Host "파일 번호 선택"
    $idx   = [int]$input - 1
} while ($idx -lt 0 -or $idx -ge $assets.Count)

$asset   = $assets[$idx]
$pioEnv  = Get-PioEnv $asset.name
$noStub  = $NO_STUB_ENVS -contains $pioEnv

Write-Ok "선택됨: $($asset.name)"
if ($noStub) { Write-Info "→ --no-stub 플래그가 자동으로 적용됩니다 (이 보드 필요)" }

# ════════════════════════════════════════════════════════════════════════════
# 5. COM 포트 선택
# ════════════════════════════════════════════════════════════════════════════
Write-Header "COM 포트 선택"

$ports = @(Get-WmiObject Win32_PnPEntity |
    Where-Object { $_.Name -match "\(COM\d+\)" } |
    ForEach-Object {
        $p = [regex]::Match($_.Name, '\((COM\d+)\)').Groups[1].Value
        [PSCustomObject]@{ Port = $p; Desc = $_.Name }
    } | Sort-Object Port)

Write-Host ""
if ($ports.Count -eq 0) {
    Write-Warn "감지된 시리얼 포트가 없습니다. ESP32 가 연결되어 있는지 확인하세요."
    $selectedPort = Read-Host "COM 포트 직접 입력 (예: COM3)"
} else {
    for ($i = 0; $i -lt $ports.Count; $i++) {
        Write-Host "  [$($i+1)] $($ports[$i].Port.PadRight(6))  $($ports[$i].Desc)"
    }
    Write-Host "  [M] 직접 입력"
    Write-Host ""
    $choice = Read-Host "포트 선택"
    if ($choice -match '^[Mm]$') {
        $selectedPort = Read-Host "COM 포트 입력 (예: COM3)"
    } else {
        $idx = [int]$choice - 1
        if ($idx -lt 0 -or $idx -ge $ports.Count) { Pause-Exit "잘못된 선택" }
        $selectedPort = $ports[$idx].Port
    }
}

Write-Ok "포트: $selectedPort"

# ════════════════════════════════════════════════════════════════════════════
# 6. 다운로드
# ════════════════════════════════════════════════════════════════════════════
Write-Header "다운로드"

$tmpDir = Join-Path $env:TEMP "OpenIris_$(Get-Random)"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$dlPath = Join-Path $tmpDir $asset.name

Write-Info "URL : $($asset.browser_download_url)"
Write-Info "크기: $([Math]::Round($asset.size/1024, 0)) KB"
Write-Host ""

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
try {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($asset.browser_download_url, $dlPath)
} catch {
    Pause-Exit "다운로드 실패: $_"
}
Write-Ok "다운로드 완료"

# ════════════════════════════════════════════════════════════════════════════
# 7. esptool 플래싱
# ════════════════════════════════════════════════════════════════════════════
Write-Header "플래싱"

$flashArgs = [System.Collections.Generic.List[string]]::new()

if ($isFullInstall) {
    $extractDir = Join-Path $tmpDir "extracted"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($dlPath, $extractDir)

    $manifestFile = Join-Path $extractDir "manifest.json"
    $chipArg      = "auto"
    if (Test-Path $manifestFile) {
        $manifest = Get-Content $manifestFile | ConvertFrom-Json
        $raw      = $manifest.builds[0].chipFamily
        $chipArg  = $raw.ToLower().Replace("-", "")
        Write-Info "manifest 칩 패밀리: $raw → --chip $chipArg"
    }
    $flashArgs.Add("--chip"); $flashArgs.Add($chipArg)
} else {
    $flashArgs.Add("--chip"); $flashArgs.Add("auto")
}

if ($noStub) { $flashArgs.Add("--no-stub") }
$flashArgs.Add("--port");  $flashArgs.Add($selectedPort)
$flashArgs.Add("--baud");  $flashArgs.Add("921600")
$flashArgs.Add("write_flash")
$flashArgs.Add("--flash_mode"); $flashArgs.Add("keep")
$flashArgs.Add("--flash_freq"); $flashArgs.Add("keep")
$flashArgs.Add("--flash_size"); $flashArgs.Add("keep")

if ($isFullInstall) {
    $mergedBin = Join-Path $extractDir "merged-firmware.bin"
    if (-not (Test-Path $mergedBin)) { Pause-Exit "merged-firmware.bin 이 zip 안에 없습니다." }
    $flashArgs.Add("0x0"); $flashArgs.Add($mergedBin)
} else {
    $flashArgs.Add("0x10000"); $flashArgs.Add($dlPath)
}

Write-Host ""
Write-Info "명령어 미리보기:"
Write-Info "  $pythonCmd -m esptool $($flashArgs -join ' ')"
Write-Host ""
Write-Warn "플래싱 중에는 ESP32 전원과 케이블을 절대 분리하지 마세요!"
Write-Host ""

& $pythonCmd -m esptool @flashArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Ok "플래싱 성공! ESP32 를 재시작하면 됩니다."
} else {
    Write-Host ""
    Write-Fail "esptool 종료 코드: $LASTEXITCODE"
    Write-Host ""
    Write-Host "  문제 해결 팁:" -ForegroundColor Yellow
    Write-Host "  - ESP32 의 BOOT 버튼을 누른 채로 연결한 뒤 다시 시도" -ForegroundColor Gray
    Write-Host "  - 다른 USB 케이블 또는 포트 사용" -ForegroundColor Gray
    Write-Host "  - 보드 리셋 후 재시도" -ForegroundColor Gray
}

Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Read-Host "아무 키나 눌러 종료"

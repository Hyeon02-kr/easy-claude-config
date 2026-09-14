# setup.ps1 — Claude Code 환경 동기화 스크립트
#
# 멱등하다. 몇 번 돌려도 결과가 같고, 이미 맞는 항목은 건너뛴다.
#
# .claude/settings.json 은 git이 다루지 않는다(로컬 라이브 설정이 진실 원천).
# 이미 있으면 절대 건드리지 않고, 없을 때만 settings.example.json 을 복사해 만든다.
#
# 사용법:
#   .\setup.ps1                  변경을 적용한다
#   .\setup.ps1 -Check           아무것도 바꾸지 않고 선언과 실제의 차이만 보고한다 (-c, --check 도 동일)
#   .\setup.ps1 -Force           선언과 어긋난 MCP 서버를 지우고 매니페스트대로 다시 등록한다 (-f, --force 도 동일)
#
# 비밀값 취급 규칙. 어기면 키가 터미널 기록과 대화 로그에 남는다.
#   - mcp-secrets.json 의 "값"을 화면에 출력하지 않는다. 키 이름만 출력한다.
#   - claude mcp get 을 호출하지 않는다. env 와 header 를 평문으로 뱉는다.
#   - claude mcp add 에 넘기는 인자 배열을 출력하지 않는다.
#   - JSON 파싱 예외를 그대로 출력하지 않는다. 예외 메시지에 파일 내용이 실려 온다.

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Force,
    # PowerShell 파라미터 바인딩은 -Check/-Force(단일 대시)만 인식하고 --check/--force
    # 같은 GNU 스타일 이중 대시 인자는 "일치하는 파라미터 없음" 오류로 죽는다. 여기서
    # 안 묶인 인자를 전부 받아 아래에서 직접 해석한다.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

foreach ($a in $ExtraArgs) {
    switch ($a) {
        { $_ -in @("--force", "-f") } { $Force = $true }
        { $_ -in @("--check", "-c") } { $Check = $true }
        default { Write-Host "알 수 없는 인자: $a (무시함)" -ForegroundColor Yellow }
    }
}

$ErrorActionPreference = "Continue"

$repoRoot       = $PSScriptRoot
$claudeDir      = Join-Path $repoRoot ".claude"
$manifestPath   = Join-Path $claudeDir "mcp-servers.json"
$secretsPath    = Join-Path $claudeDir "mcp-secrets.json"
$discordCfg     = Join-Path $claudeDir "scripts\discord-config.json"
$settingsPath   = Join-Path $claudeDir "settings.json"
$settingsExPath = Join-Path $claudeDir "settings.example.json"
$claudeJson     = Join-Path $HOME ".claude.json"

$changed = New-Object System.Collections.Generic.List[string]
$skipped = New-Object System.Collections.Generic.List[string]
$warned  = New-Object System.Collections.Generic.List[string]
$manual  = New-Object System.Collections.Generic.List[string]

function Write-Section($text) {
    Write-Host ""
    Write-Host $text -ForegroundColor Yellow
}

function Test-CommandExists($name) {
    try {
        Get-Command $name -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# y/n 확인. 빈 입력(엔터만)은 $defaultYes 를 따른다. 대소문자 구분 안 함.
function Confirm-YesNo($prompt, [bool]$defaultYes = $false) {
    $suffix = if ($defaultYes) { "(Y/n)" } else { "(y/N)" }
    $answer = Read-Host "$prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $defaultYes }
    return $answer -match '^(y|yes)$'
}

function Get-PropNames($obj) {
    if ($null -eq $obj) { return @() }
    return @($obj.PSObject.Properties | ForEach-Object { $_.Name })
}

# mcp-secrets.json 에서 서버 하나의 비밀 묶음을 꺼낸다. 없으면 $null.
function Get-SecretEntry($secrets, $name) {
    if ($null -eq $secrets) { return $null }
    $prop = $secrets.PSObject.Properties | Where-Object { $_.Name -eq $name }
    if ($prop) { return $prop.Value }
    return $null
}

# 매니페스트가 요구하는데 mcp-secrets.json 에 없는 항목의 "이름"만 돌려준다.
function Get-MissingSecret($server, $entry) {
    $missing = @()
    $envNames = @()
    $hdrNames = @()
    if ($entry) {
        $envNames = Get-PropNames $entry.env
        $hdrNames = Get-PropNames $entry.headers
    }
    foreach ($k in @($server.requiresEnv)) {
        if ([string]::IsNullOrWhiteSpace($k)) { continue }
        if ($envNames -notcontains $k) { $missing += "env:$k" }
    }
    foreach ($k in @($server.requiresHeaders)) {
        if ([string]::IsNullOrWhiteSpace($k)) { continue }
        if ($hdrNames -notcontains $k) { $missing += "header:$k" }
    }
    return $missing
}

# claude mcp add 인자 배열. 반환값에 비밀값이 들어 있으므로 절대 출력하지 않는다.
# $resolvedCommand 는 {claudeDir} 같은 토큰이 이미 실제 경로로 치환된 command 배열이다.
function Get-AddArgs($manifest, $server, $entry, $resolvedCommand) {
    $a = @("mcp", "add", $server.name, "-s", $manifest.scope)
    if ($entry -and $entry.env) {
        foreach ($p in $entry.env.PSObject.Properties) { $a += @("-e", "$($p.Name)=$($p.Value)") }
    }
    if ($entry -and $entry.headers) {
        foreach ($p in $entry.headers.PSObject.Properties) { $a += @("-H", "$($p.Name): $($p.Value)") }
    }
    if ($server.transport -eq "http") {
        $a += @("--transport", "http", $server.url)
    } else {
        $a += @("--") + $resolvedCommand
    }
    return ,$a
}

# command 배열의 {claudeDir} 토큰을 실제 경로로 치환한다. npm 전역 설치가 아니라
# GitHub 릴리스 바이너리처럼 기계마다 절대경로가 갈리는 서버에 쓴다.
function Resolve-CommandTokens($command, $dir) {
    if (-not $command) { return $command }
    return @($command | ForEach-Object { $_.Replace('{claudeDir}', $dir) })
}

# install 필드가 있는 서버는 npm 패키지가 아니라 GitHub 릴리스 바이너리다.
# 이미 있으면 통과, 없으면 받을지 물어보고, 받으면 SHA256SUMS.txt로 무결성을
# 검증한 뒤에만 설치한다. 검증에 실패하면 절대 설치하지 않는다.
function Ensure-LocalBinary($server) {
    $install = $server.install
    $destDir = Join-Path $claudeDir $install.extractTo

    if (Get-ChildItem -Path $destDir -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1) {
        Write-Host "   있음    $($server.name) 바이너리" -ForegroundColor Gray
        $skipped.Add("로컬 바이너리: $($server.name)")
        return $true
    }

    if ($Check) {
        Write-Host "   없음    $($server.name) 바이너리" -ForegroundColor Red
        $warned.Add("로컬 바이너리 없음: $($server.name) - setup.ps1 실행 시 다운로드 여부를 묻습니다")
        return $false
    }

    Write-Host ""
    Write-Host "   $($server.name)은 npm 패키지가 아니라 GitHub 릴리스 바이너리입니다." -ForegroundColor Yellow
    Write-Host "   저장소: https://github.com/$($install.repo)" -ForegroundColor Gray
    Write-Host "   받을 파일: $($install.assetPattern) (다운로드 후 SHA256 검증, 불일치 시 설치 안 함)" -ForegroundColor Gray
    if (-not (Confirm-YesNo "   지금 받아서 설치할까요?" $false)) {
        Write-Host "   건너뜀" -ForegroundColor Gray
        $warned.Add("로컬 바이너리 미설치: $($server.name) - MCP 서버가 등록되지 않습니다")
        return $false
    }
    if (-not (Test-CommandExists "gh")) {
        Write-Host "   gh CLI가 없어 받을 수 없습니다." -ForegroundColor Red
        $warned.Add("gh 없음 -> $($server.name) 바이너리를 받지 못했습니다")
        return $false
    }

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "claude-setup-$($server.name)-$(Get-Random)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    try {
        gh release download --repo $install.repo --pattern $install.assetPattern --pattern $install.checksumAsset --dir $tmpDir --clobber
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   다운로드 실패" -ForegroundColor Red
            $warned.Add("$($server.name) 다운로드 실패")
            return $false
        }

        $archive  = Get-ChildItem -Path $tmpDir -Filter "*.zip" | Select-Object -First 1
        $sumsPath = Join-Path $tmpDir $install.checksumAsset
        if (-not $archive -or -not (Test-Path $sumsPath)) {
            Write-Host "   릴리스 자산 구성이 예상과 다릅니다." -ForegroundColor Red
            $warned.Add("$($server.name) 자산 구성 불일치 - 수동 설치가 필요합니다 (https://github.com/$($install.repo)/releases)")
            return $false
        }

        $expectedLine = Get-Content $sumsPath | Where-Object { $_ -match [regex]::Escape($archive.Name) }
        $expectedHash = ($expectedLine -split '\s+')[0]
        $actualHash   = (Get-FileHash $archive.FullName -Algorithm SHA256).Hash

        if (-not $expectedHash -or $actualHash -ine $expectedHash) {
            Write-Host "   체크섬 불일치 - 설치를 중단합니다." -ForegroundColor Red
            $warned.Add("$($server.name) 체크섬 불일치 - 설치 중단 (파일 손상 또는 변조 가능성, 수동 확인 필요)")
            return $false
        }
        Write-Host "   체크섬 확인됨" -ForegroundColor Green

        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Expand-Archive -Path $archive.FullName -DestinationPath $destDir -Force
        Write-Host "   설치    $($server.name) -> $destDir" -ForegroundColor Green
        $changed.Add("로컬 바이너리 설치: $($server.name)")
        return $true
    } finally {
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    }
}

# ~/.claude.json 에서 서버별 env/header 의 "키 이름"만 읽는다. 값은 읽지 않는다.
# claude mcp get 은 값을 평문 출력하므로 쓰지 않는다.
# ConvertFrom-Json 은 이 파일을 못 읽는다. projects 섹션에 대소문자만 다른
# 중복 키가 있어 예외가 난다. JavaScriptSerializer 는 뒤 값으로 덮어쓰고 넘어간다.
function Get-LiveSecretKeys($path) {
    if (-not (Test-Path $path)) { return $null }
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        $obj = $ser.DeserializeObject([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
        if (-not $obj.ContainsKey('mcpServers')) { return @{} }

        $result = @{}
        foreach ($n in $obj['mcpServers'].Keys) {
            $e = $obj['mcpServers'][$n]
            $ek = @()
            $hk = @()
            if ($e.ContainsKey('env')     -and $e['env'])     { $ek = @($e['env'].Keys) }
            if ($e.ContainsKey('headers') -and $e['headers']) { $hk = @($e['headers'].Keys) }
            $result[$n] = @{ env = $ek; headers = $hk }
        }
        return $result
    } catch {
        return $null
    }
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "   Claude Code 환경 동기화" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
if ($Check) {
    Write-Host "   점검 모드: 아무것도 변경하지 않습니다" -ForegroundColor Cyan
}

# ── 0. settings.json 부트스트랩 ────────────────────
# settings.json 은 git이 다루지 않는다(로컬 라이브 설정이 진실 원천). 없을 때만
# settings.example.json 을 그대로 복사해 최초 1회 만든다. 이미 있으면 절대 건드리지
# 않는다 - 예전에 git이 이 파일을 동기화하다가 라이브 설정을 예제로 덮어쓴 사고가 있었다.
Write-Section "[1/6] Claude Code 설정 파일"

if (Test-Path $settingsPath) {
    Write-Host "   있음    settings.json" -ForegroundColor Gray
    $skipped.Add("설정 파일: settings.json")
} elseif (-not (Test-Path $settingsExPath)) {
    Write-Host "   settings.example.json 이 없어 settings.json 을 만들지 못했습니다." -ForegroundColor Red
    $warned.Add("settings.example.json 없음 -> settings.json 을 만들지 못했습니다")
} elseif ($Check) {
    Write-Host "   없음    settings.json" -ForegroundColor Red
    $warned.Add("settings.json 없음 -> setup.ps1 실행 시 settings.example.json 에서 생성합니다")
} else {
    Copy-Item $settingsExPath $settingsPath
    Write-Host "   생성    settings.json (settings.example.json 에서 복사)" -ForegroundColor Green
    $changed.Add("설정 파일 생성: settings.json")
}

# ── 매니페스트 로드 ────────────────────────────────
if (-not (Test-Path $manifestPath)) {
    Write-Host ""
    Write-Host "매니페스트가 없습니다: $manifestPath" -ForegroundColor Red
    Write-Host "레포 루트에서 실행했는지 확인하세요." -ForegroundColor Red
    exit 1
}
$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ── 비밀값 로드 ────────────────────────────────────
# 없어도 진행한다. 키를 요구하는 서버만 나중에 건너뛴다.
# 파싱 예외를 출력하면 안 된다. PowerShell 의 JSON 오류 메시지는 파일 내용을 통째로 싣는다.
$secrets = $null
if (Test-Path $secretsPath) {
    try {
        $secrets = (Get-Content $secretsPath -Raw -Encoding UTF8 | ConvertFrom-Json).secrets
    } catch {
        Write-Host ""
        Write-Host "mcp-secrets.json 을 파싱하지 못했습니다. JSON 문법을 확인하세요." -ForegroundColor Red
        Write-Host "(내용에 비밀값이 있어 오류 원문은 표시하지 않습니다)" -ForegroundColor Gray
        exit 1
    }
}

# ── 선택 설치 목록 ─────────────────────────────────
# 기본값은 전체 설치다. -Check 에서는 프롬프트 없이 전부 선택된 것으로 보고 점검한다.
Write-Section "[2/6] 설치 옵션 선택"

$components = New-Object System.Collections.Generic.List[object]
foreach ($s in $manifest.servers) {
    $components.Add([PSCustomObject]@{ Name = $s.name; Label = "$($s.name) - $($s.purpose)" })
}
$components.Add([PSCustomObject]@{ Name = "discord"; Label = "discord - Stop/Notification/PermissionRequest/PostCompact 이벤트를 Discord webhook으로 알림" })

$excluded = @{}

if ($Check) {
    Write-Host "   점검 모드 - 전체 선택된 것으로 보고 점검합니다." -ForegroundColor Gray
} else {
    Write-Host "   기본값은 전체 설치입니다:" -ForegroundColor Gray
    for ($i = 0; $i -lt $components.Count; $i++) {
        Write-Host ("   {0,2}. {1}" -f ($i + 1), $components[$i].Label) -ForegroundColor Gray
    }
    $answer = Read-Host "   전부 기본값대로 설치할까요? (Y/n/o, o=제외할 항목 고르기)"
    if ($answer -match '^n') {
        foreach ($c in $components) { $excluded[$c.Name] = $true }
        Write-Host "   선택 설치 항목 전체 건너뜀" -ForegroundColor Gray
    } elseif ($answer -match '^o') {
        $pick = Read-Host "   제외할 번호를 쉼표로 입력하세요 (없으면 그냥 Enter)"
        if (-not [string]::IsNullOrWhiteSpace($pick)) {
            foreach ($tok in ($pick -split ',')) {
                $idx = 0
                if ([int]::TryParse($tok.Trim(), [ref]$idx) -and $idx -ge 1 -and $idx -le $components.Count) {
                    $excluded[$components[$idx - 1].Name] = $true
                }
            }
        }
    }
}

$selectedServerNames = @($manifest.servers | Where-Object { -not $excluded.ContainsKey($_.name) } | ForEach-Object { $_.name })
$installDiscord = -not $excluded.ContainsKey("discord")

foreach ($name in $excluded.Keys) {
    $skipped.Add("선택 안 함: $name")
}

# ── 1. 사전 프로그램 점검 ──────────────────────────
Write-Section "[3/6] 사전 프로그램"

$prereqs = @(
    @{ cmd = "python"; hint = "winget install Python.Python.3" },
    @{ cmd = "node";   hint = "winget install OpenJS.NodeJS.LTS" },
    @{ cmd = "npm";    hint = "winget install OpenJS.NodeJS.LTS" },
    @{ cmd = "git";    hint = "winget install Git.Git" },
    @{ cmd = "gh";     hint = "winget install GitHub.cli" },
    @{ cmd = "claude"; hint = "https://claude.ai/code 참조" }
)
foreach ($p in $prereqs) {
    if (Test-CommandExists $p.cmd) {
        Write-Host "   있음    $($p.cmd)" -ForegroundColor Green
        $skipped.Add("사전 프로그램: $($p.cmd)")
    } else {
        Write-Host "   없음    $($p.cmd)" -ForegroundColor Red
        $warned.Add("$($p.cmd) 없음 -> $($p.hint)")
    }
}

# ── 2. 전역 npm 패키지 ─────────────────────────────
Write-Section "[4/6] 전역 npm 패키지"

$needed = @()
foreach ($s in $manifest.servers) {
    if ($selectedServerNames -notcontains $s.name) { continue }
    if ($s.globalPackages) {
        $needed += $s.globalPackages
    }
}
$needed = @($needed | Select-Object -Unique)

if ($needed.Count -eq 0) {
    Write-Host "   필요한 전역 패키지가 없습니다." -ForegroundColor Gray
} else {
    $installed = @()
    try {
        $parsed = npm ls -g --depth=0 --json | ConvertFrom-Json
        if ($parsed.dependencies) {
            $installed = @($parsed.dependencies.PSObject.Properties.Name)
        }
    } catch {
        $warned.Add("npm ls -g 파싱 실패 - 전역 패키지 상태를 확인하지 못했습니다")
    }

    foreach ($pkg in $needed) {
        if ($installed -contains $pkg) {
            Write-Host "   있음    $pkg" -ForegroundColor Gray
            $skipped.Add("전역 패키지: $pkg")
        } elseif ($Check) {
            Write-Host "   없음    $pkg" -ForegroundColor Red
            $warned.Add("전역 패키지 없음: $pkg")
        } else {
            Write-Host "   설치    $pkg ..." -ForegroundColor Cyan
            npm install -g $pkg
            if ($LASTEXITCODE -eq 0) {
                $changed.Add("전역 패키지 설치: $pkg")
            } else {
                $warned.Add("전역 패키지 설치 실패: $pkg")
            }
        }
    }
}

# ── 3. MCP 서버 ────────────────────────────────────
Write-Section "[5/6] MCP 서버"

$live = @{}
if (Test-CommandExists "claude") {
    $listRaw = claude mcp list
    foreach ($line in @($listRaw -split "`r?`n")) {
        if ($line -match '^(?<name>.+?):\s(?<target>.+?)\s-\s(?<status>.+)$') {
            $live[$matches['name'].Trim()] = @{
                target = $matches['target'].Trim()
                status = $matches['status'].Trim()
            }
        }
    }
} else {
    $warned.Add("claude CLI가 없어 MCP 상태를 확인하지 못했습니다")
}

# 등록된 비밀의 "키 이름"만 읽는다. 값은 읽지 않는다.
$liveSecretKeys = Get-LiveSecretKeys $claudeJson
if ($null -eq $liveSecretKeys) {
    $warned.Add("$claudeJson 을 읽지 못해 비밀값 주입 여부를 검증하지 못했습니다")
}

# -Force 는 매니페스트를 진실로 보고 덮어쓴다. 매니페스트가 낡았으면 잘 돌던
# 등록을 파괴하므로, 무엇이 지워질지 먼저 보여주고 확인을 받는다.
$forceOk = $false
if ($Force -and -not $Check) {
    $toReplace = @()
    foreach ($s in $manifest.servers) {
        if ($selectedServerNames -notcontains $s.name) { continue }
        if (-not $live.ContainsKey($s.name)) { continue }
        $cmd = Resolve-CommandTokens $s.command $claudeDir
        if ($s.transport -eq "http") { $exp = $s.url } else { $exp = ($cmd -join " ") }
        if (($live[$s.name].target -replace '\s+\(HTTP\)$', '') -ne $exp) { $toReplace += $s.name }
    }
    if ($toReplace.Count -eq 0) {
        $forceOk = $true
    } else {
        Write-Host "   -Force: 아래 서버를 지우고 매니페스트대로 다시 등록합니다." -ForegroundColor Yellow
        foreach ($n in $toReplace) { Write-Host "           - $n" -ForegroundColor Gray }
        Write-Host "   매니페스트가 낡았다면 잘 돌던 등록이 깨집니다." -ForegroundColor Yellow
        if (Confirm-YesNo "   계속할까요?" $false) {
            $forceOk = $true
        } else {
            Write-Host "   건너뜀 - 경고만 표시합니다." -ForegroundColor Gray
        }
    }
}

foreach ($s in $manifest.servers) {
    if ($selectedServerNames -notcontains $s.name) {
        Write-Host "   건너뜀  $($s.name) (선택 안 함)" -ForegroundColor Gray
        continue
    }

    if ($s.install) {
        $binOk = Ensure-LocalBinary $s
        if (-not $binOk) { continue }
    }

    $resolvedCommand = Resolve-CommandTokens $s.command $claudeDir

    if ($s.transport -eq "http") {
        $expected = $s.url
    } else {
        $expected = ($resolvedCommand -join " ")
    }

    $entry   = Get-SecretEntry $secrets $s.name
    $missing = Get-MissingSecret $s $entry

    # 키가 빠졌으면 등록하지 않는다. 키 없이 등록하면 연결에 실패하는 껍데기가 남는다.
    if ($missing.Count -gt 0) {
        Write-Host "   비밀누락 $($s.name)" -ForegroundColor Red
        Write-Host "           mcp-secrets.json 에 없음: $($missing -join ', ')" -ForegroundColor Gray
        $warned.Add("비밀값 누락: $($s.name) - $($missing -join ', ') 를 mcp-secrets.json 에 채우세요")
        continue
    }

    if (-not $live.ContainsKey($s.name)) {
        if ($Check) {
            Write-Host "   미등록  $($s.name)" -ForegroundColor Red
            $warned.Add("MCP 미등록: $($s.name)")
        } else {
            Write-Host "   등록    $($s.name) ..." -ForegroundColor Cyan
            $addArgs = Get-AddArgs $manifest $s $entry $resolvedCommand   # 출력 금지
            & claude @addArgs
            if ($LASTEXITCODE -eq 0) {
                $changed.Add("MCP 등록: $($s.name)")
            } else {
                $warned.Add("MCP 등록 실패: $($s.name)")
            }
        }
        continue
    }

    $liveTarget = $live[$s.name].target -replace '\s+\(HTTP\)$', ''
    if ($liveTarget -eq $expected) {
        Write-Host "   일치    $($s.name)" -ForegroundColor Green
        $skipped.Add("MCP: $($s.name)")
    } elseif ($forceOk) {
        Write-Host "   재등록  $($s.name) ..." -ForegroundColor Cyan
        claude mcp remove $s.name -s $manifest.scope | Out-Null
        $addArgs = Get-AddArgs $manifest $s $entry $resolvedCommand       # 출력 금지
        & claude @addArgs
        if ($LASTEXITCODE -eq 0) {
            $changed.Add("MCP 재등록: $($s.name)")
        } else {
            $warned.Add("MCP 재등록 실패: $($s.name)")
        }
        continue
    } else {
        Write-Host "   불일치  $($s.name)" -ForegroundColor Yellow
        Write-Host "           선언: $expected" -ForegroundColor Gray
        Write-Host "           실제: $liveTarget" -ForegroundColor Gray
        $warned.Add("MCP 명령 불일치: $($s.name) - 선언이 맞으면 .\setup.ps1 -Force, 실제가 맞으면 mcp-servers.json 을 고치세요")
    }

    # 요구한 키가 실제 등록에 들어갔는지 이름만 대조한다.
    if ($null -ne $liveSecretKeys -and $liveSecretKeys.ContainsKey($s.name)) {
        $notInjected = @()
        foreach ($k in @($s.requiresEnv)) {
            if ([string]::IsNullOrWhiteSpace($k)) { continue }
            if ($liveSecretKeys[$s.name].env -notcontains $k) { $notInjected += "env:$k" }
        }
        foreach ($k in @($s.requiresHeaders)) {
            if ([string]::IsNullOrWhiteSpace($k)) { continue }
            if ($liveSecretKeys[$s.name].headers -notcontains $k) { $notInjected += "header:$k" }
        }
        if ($notInjected.Count -gt 0) {
            Write-Host "           비밀 미주입: $($notInjected -join ', ')" -ForegroundColor Yellow
            $warned.Add("비밀값 미주입: $($s.name) - $($notInjected -join ', ') 가 등록에 없습니다. .\setup.ps1 -Force 로 재등록하세요")
        }
    }

    if ($live[$s.name].status -notmatch 'Connected') {
        Write-Host "           연결 실패: $($live[$s.name].status)" -ForegroundColor Red
        $warned.Add("MCP 연결 실패: $($s.name) - $($live[$s.name].status)")
    }
}

# 선언에 없는데 등록된 서버
$declared = @($manifest.servers | ForEach-Object { $_.name })
$external = @($manifest.externallyManaged | ForEach-Object { $_.name })
foreach ($name in $live.Keys) {
    if (($declared -notcontains $name) -and ($external -notcontains $name)) {
        Write-Host "   미선언  $name" -ForegroundColor Yellow
        $warned.Add("선언에 없는 MCP 서버: $name - 의도한 것이면 mcp-servers.json에 추가")
    }
}

# ── 4. 비밀 파일 ───────────────────────────────────
Write-Section "[6/6] 비밀 파일"

# 이 파일은 스크립트가 만들지 않는다. mcp-secrets.example.json 을 보고 사람이 직접 채운다.
if (Test-Path $secretsPath) {
    Write-Host "   있음    mcp-secrets.json" -ForegroundColor Gray
    $skipped.Add("비밀 파일: mcp-secrets.json")
} else {
    $needsSecret = @($manifest.servers | Where-Object { ($selectedServerNames -contains $_.name) -and ($_.requiresEnv -or $_.requiresHeaders) })
    if ($needsSecret.Count -eq 0) {
        Write-Host "   불필요  mcp-secrets.json (키를 요구하는 서버가 없습니다)" -ForegroundColor Gray
    } else {
        Write-Host "   없음    mcp-secrets.json" -ForegroundColor Red
        Write-Host "           mcp-secrets.example.json 을 복사해 직접 채우세요." -ForegroundColor Gray
        $warned.Add("mcp-secrets.json 없음 -> 키가 필요한 서버($($needsSecret.name -join ', '))가 등록되지 않습니다")
    }
}

if (-not $installDiscord) {
    Write-Host "   건너뜀  discord-config.json (선택 안 함)" -ForegroundColor Gray
} elseif (Test-Path $discordCfg) {
    Write-Host "   있음    discord-config.json" -ForegroundColor Gray
    $skipped.Add("비밀 파일: discord-config.json")
} elseif ($Check) {
    Write-Host "   없음    discord-config.json" -ForegroundColor Red
    $warned.Add("discord-config.json 없음 -> 훅이 발화할 때마다 discord-notify.py가 죽습니다")
} else {
    Write-Host "   Discord Webhook URL을 입력하세요. 비우면 건너뜁니다." -ForegroundColor Cyan
    Write-Host "   (Discord 채널 설정 -> 연동 -> 웹후크)" -ForegroundColor Gray
    $webhookUrl = Read-Host "   URL"
    if ([string]::IsNullOrWhiteSpace($webhookUrl)) {
        Write-Host "   건너뜀" -ForegroundColor Gray
        $warned.Add("discord-config.json 미생성 -> 훅이 발화할 때마다 discord-notify.py가 죽습니다")
    } else {
        $json = @{ webhook_url = $webhookUrl.Trim() } | ConvertTo-Json -Compress
        # BOM 없는 UTF-8로 써야 한다. [System.Text.Encoding]::UTF8 은 BOM을 붙이고,
        # discord-notify.py 가 그 BOM을 만나면 JSONDecodeError 로 죽는다.
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($discordCfg, $json, $utf8NoBom)
        Write-Host "   생성    discord-config.json" -ForegroundColor Green
        $changed.Add("비밀 파일 생성: discord-config.json")
    }
}

# ── 5. 수동 작업 (목록만 구성, 출력은 맨 아래 결과 뒤에서 한다) ──
foreach ($s in $manifest.servers) {
    if ($s.auth -eq "oauth") {
        $manual.Add("$($s.name) 인증: Claude Code에서 /mcp -> $($s.name) 선택 -> 브라우저 인증")
    }
}
$manual.Add("superpowers 플러그인: /plugin install superpowers@claude-plugins-official")
$manual.Add("GitHub CLI 인증: gh auth login")

# ── 요약 ───────────────────────────────────────────
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
if ($Check) {
    Write-Host "   점검 결과" -ForegroundColor Cyan
} else {
    Write-Host "   실행 결과" -ForegroundColor Cyan
}
Write-Host "======================================" -ForegroundColor Cyan

if (-not $Check) {
    Write-Host ""
    Write-Host "변경 ($($changed.Count))" -ForegroundColor Green
    foreach ($c in $changed) { Write-Host "   + $c" }
}

Write-Host ""
Write-Host "이미 맞음 ($($skipped.Count))" -ForegroundColor Gray
foreach ($s in $skipped) { Write-Host "   = $s" }

Write-Host ""
if ($warned.Count -eq 0) {
    Write-Host "경고 없음 - 선언과 실제가 일치합니다." -ForegroundColor Green
} else {
    Write-Host "경고 ($($warned.Count))" -ForegroundColor Yellow
    foreach ($w in $warned) { Write-Host "   ! $w" }
}

Write-Section "다음 할 일 (스크립트가 자동화할 수 없는 것들)"
foreach ($m in $manual) {
    Write-Host "   - $m" -ForegroundColor Cyan
}
Write-Host ""

if ($warned.Count -gt 0) {
    exit 1
}
exit 0

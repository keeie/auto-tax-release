# auto-tax 설치 매니저. install.cmd 를 더블클릭해 실행한다.
#  1) Node.js 20 이상이 없으면 설치(winget 우선, 없으면 공식 설치 파일)
#  2) 배포 파일(zip)을 받아 체크섬과 서명을 확인
#  3) 설치 폴더에 풀고 config.json 과 패키지(npm install)를 준비
#  4) 바탕화면 바로가기 생성
# 이 파일은 배포 도구가 템플릿에서 만든다(공개 키와 업데이트 주소가 들어 있음).
param(
  [string]$InstallDir = (Join-Path $env:USERPROFILE 'auto-tax'),
  [string]$LocalZip = '',
  [string]$LocalManifest = '',
  [switch]$SkipNpm,
  [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ManifestUrl = 'https://github.com/keeie/auto-tax-release/raw/main/latest.json'
$PublicKeyPem = @'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAfYNGshkVXygBtv8ZVipd2Swcq6LcFjHFMpE3vNPyvTI=
-----END PUBLIC KEY-----
'@
$MinNodeMajor = 20

# 체크섬과 서명을 확인하는 작은 스크립트(Node 의 crypto 사용). 종료 코드 0 이면 통과.
$VerifyScript = @'
const fs = require('fs');
const crypto = require('crypto');
const [zipPath, manifestPath, keyPath] = process.argv.slice(2);
const zip = fs.readFileSync(zipPath);
const m = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const sha = crypto.createHash('sha256').update(zip).digest('hex');
if (sha !== String(m.sha256).toLowerCase()) { console.error('checksum mismatch'); process.exit(2); }
const key = crypto.createPublicKey(fs.readFileSync(keyPath, 'utf8'));
if (!crypto.verify(null, zip, key, Buffer.from(m.signature, 'base64'))) { console.error('signature mismatch'); process.exit(3); }
console.log('verified ' + m.version);
'@

function Write-Step([string]$msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Get-NodeMajor {
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return 0 }
  $v = & node -p "process.versions.node.split('.')[0]" 2>$null
  if ($LASTEXITCODE -ne 0) { return 0 }
  return [int]$v
}

function Install-Node {
  Write-Step 'Node.js 설치'
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    & winget install -e --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
    Refresh-Path
    if ((Get-NodeMajor) -ge $MinNodeMajor) { return }
    Write-Host 'winget 으로 설치하지 못했습니다. 공식 설치 파일로 다시 시도합니다.'
  }
  $index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json'
  $lts = $index | Where-Object { $_.lts -and ($_.files -contains 'win-x64-msi') } | Select-Object -First 1
  $url = "https://nodejs.org/dist/$($lts.version)/node-$($lts.version)-x64.msi"
  $msi = Join-Path $env:TEMP "node-$($lts.version)-x64.msi"
  Write-Host "Node.js $($lts.version) 내려받는 중..."
  Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing
  Write-Host '설치 창이 뜨면 관리자 권한 요청에 "예"를 눌러 주세요.'
  $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$msi`" /qb /norestart" -Verb RunAs -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "Node.js 설치가 끝나지 않았습니다(코드 $($p.ExitCode))." }
  Refresh-Path
}

# ---------- 실행 ----------
Write-Step '1. Node.js 확인'
if ((Get-NodeMajor) -lt $MinNodeMajor) { Install-Node }
if ((Get-NodeMajor) -lt $MinNodeMajor) {
  throw "Node.js $MinNodeMajor 이상을 찾지 못했습니다. 설치 후 새 창을 열어 다시 실행해 보세요."
}
Write-Host "Node.js $(& node -v) 사용"

Write-Step '2. 배포 파일 내려받기와 확인'
if (Test-Path (Join-Path $InstallDir 'package.json')) {
  throw "이미 설치되어 있습니다: $InstallDir`n업데이트는 프로그램 화면의 '업데이트' 버튼을 사용하세요."
}
$work = Join-Path $env:TEMP ('autotax-setup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $manifestPath = Join-Path $work 'latest.json'
  $zipPath = Join-Path $work 'package.zip'
  $keyPath = Join-Path $work 'public.pem'
  $verifyPath = Join-Path $work 'verify.js'
  [IO.File]::WriteAllText($keyPath, $PublicKeyPem)
  [IO.File]::WriteAllText($verifyPath, $VerifyScript)

  if ($LocalManifest) { Copy-Item $LocalManifest $manifestPath } else { Invoke-WebRequest -Uri $ManifestUrl -OutFile $manifestPath -UseBasicParsing }
  $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
  if ($LocalZip) { Copy-Item $LocalZip $zipPath } else { Invoke-WebRequest -Uri $manifest.zipUrl -OutFile $zipPath -UseBasicParsing }

  & node $verifyPath $zipPath $manifestPath $keyPath
  if ($LASTEXITCODE -ne 0) { throw '다운로드한 파일의 체크섬 또는 서명이 맞지 않습니다. 설치를 중단했습니다.' }

  Write-Step "3. 프로그램 풀기: $InstallDir"
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Expand-Archive -LiteralPath $zipPath -DestinationPath $InstallDir -Force

  Write-Step '4. 설정 파일 만들기'
  $configPath = Join-Path $InstallDir 'config.json'
  if (-not (Test-Path $configPath)) {
    $config = [ordered]@{
      folders = @()
      options = [ordered]@{
        headless = $false; slowMo = 100; outputDir = './data'; maxMailsPerFolder = 50; onlyUnread = $false
        updateManifestUrl = $ManifestUrl
      }
    }
    # Windows PowerShell 의 Set-Content -Encoding utf8 는 BOM 을 붙여 JSON 읽기가 깨지므로 직접 쓴다.
    [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
  }
  New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'data') | Out-Null

  if (-not $SkipNpm) {
    Write-Step '5. 패키지 설치 (몇 분 걸릴 수 있습니다)'
    Push-Location $InstallDir
    try {
      cmd /c 'npm install --no-audit --no-fund'
      if ($LASTEXITCODE -ne 0) { throw 'npm install 에 실패했습니다.' }
      Write-Step '6. 자동 수집용 브라우저 내려받기'
      cmd /c 'npx playwright install chromium'
      if ($LASTEXITCODE -ne 0) { throw 'Playwright 브라우저 설치에 실패했습니다. 인터넷 연결을 확인해 다시 실행하세요.' }
    } finally { Pop-Location }
  }

  if (-not $NoShortcut) {
    Write-Step '7. 바탕화면 바로가기'
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut((Join-Path $desktop 'auto-tax.lnk'))
    $lnk.TargetPath = Join-Path $InstallDir 'auto-tax.vbs'
    $lnk.WorkingDirectory = $InstallDir
    $lnk.Save()
  }

  Write-Host "`n✅ 설치가 끝났습니다: $InstallDir" -ForegroundColor Green
  Write-Host '바탕화면의 auto-tax 를 실행하세요. 업데이트는 프로그램 화면의 버튼으로 받습니다.'
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

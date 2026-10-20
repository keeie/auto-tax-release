# auto-tax 삭제 매니저. uninstall.cmd 를 더블클릭해 실행한다.
#  1) 실행 중인 서버를 끈다
#  2) 데이터(발전소, 수집 데이터, 사업자 정보, 인증서·비밀번호)를 남길지 묻는다(기본: 남김)
#  3) 프로그램 폴더와 바탕화면 바로가기를 지운다
param(
  [string]$InstallDir = (Join-Path $env:USERPROFILE 'auto-tax')
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

$InstallDir = [IO.Path]::GetFullPath($InstallDir)
$pkgPath = Join-Path $InstallDir 'package.json'
if (-not (Test-Path $pkgPath)) {
  throw "설치된 auto-tax 를 찾지 못했습니다: $InstallDir"
}
# 안전장치: 다른 프로그램의 폴더를 지우지 않도록 auto-tax 가 맞는지 확인한다.
$pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
if ($pkg.name -ne 'auto-tax') { throw "이 폴더는 auto-tax 설치 폴더가 아닙니다: $InstallDir" }

Write-Step '1. 실행 중인 서버 끄기'
# 이 스크립트 자신이나 다른 프로그램을 끄지 않도록, launcher 의 PID 파일과 서버 포트의 프로세스만 확인한다.
$targets = @()
$pidFile = Join-Path $InstallDir '.run\server.pid'
if (Test-Path $pidFile) {
  $savedPid = Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($savedPid -match '^\d+$') { $targets += [int]$savedPid }
}
$port = if ($env:PORT) { [int]$env:PORT } else { 3000 }
$listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
  $owner = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
  if ($owner -and $owner.CommandLine -match 'src[\/]index\.ts') { $targets += [int]$listener.OwningProcess }
}
$stopped = 0
foreach ($t in ($targets | Select-Object -Unique)) {
  if ($t -ne $PID) {
    cmd /c "taskkill /T /F /PID $t >nul 2>&1"
    $stopped++
  }
}
if (Test-Path $pidFile) { Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue }
Write-Host "끈 서버 프로세스: $stopped 개"

Write-Step '2. 데이터 처리'
Write-Host '데이터: config.json, data 폴더(수집 데이터), secrets 폴더(인증서·비밀번호)'
$keep = Read-Host '데이터를 남길까요? 남기면 사용자 폴더의 auto-tax-data 로 옮깁니다. [Y/n]'
$keepData = ($keep -eq '' -or $keep -match '^(y|yes|예)$')
$dataItems = @('config.json', 'data', 'secrets') | ForEach-Object { Join-Path $InstallDir $_ } | Where-Object { Test-Path $_ }

if ($keepData) {
  $backup = Join-Path $env:USERPROFILE 'auto-tax-data'
  if (Test-Path $backup) { $backup = $backup + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') }
  New-Item -ItemType Directory -Path $backup | Out-Null
  foreach ($item in $dataItems) { Move-Item -LiteralPath $item -Destination $backup }
  Write-Host "데이터를 옮겼습니다: $backup"
} else {
  $confirm = Read-Host '데이터를 완전히 지웁니다(되돌릴 수 없음). 계속하려면 "삭제" 또는 DELETE 를 입력하세요'
  if ($confirm -notin @('삭제', 'DELETE')) { Write-Host '취소했습니다. 아무것도 지우지 않았습니다.'; return }
  foreach ($item in $dataItems) { Remove-Item -LiteralPath $item -Recurse -Force }
  Write-Host '데이터를 지웠습니다.'
}

Write-Step '3. 프로그램 지우기'
Remove-Item -LiteralPath $InstallDir -Recurse -Force
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'auto-tax.lnk'
if (Test-Path $lnk) { Remove-Item -LiteralPath $lnk -Force }

Write-Host "`n✅ auto-tax 를 삭제했습니다." -ForegroundColor Green

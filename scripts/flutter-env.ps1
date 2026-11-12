# 用法（PowerShell，必须用点号 source 才会影响当前会话）：
#     . .\scripts\flutter-env.ps1
#
# 作用：把 Flutter SDK、JDK 17、Android SDK、pub 缓存、Gradle 缓存、临时目录、
#       APPDATA 全部指到 E:\renwu\toolchain 下，保证编译全过程不往 C 盘写东西。

$projectRoot = Split-Path $PSScriptRoot -Parent          # E:\renwu\codepad
$workspace   = Split-Path $projectRoot -Parent           # E:\renwu
$toolchain   = Join-Path $workspace 'toolchain'          # E:\renwu\toolchain

foreach ($dir in @('tmp', 'appdata', 'localappdata', 'home', 'pub-cache', 'gradle', 'logs')) {
  $full = Join-Path $toolchain $dir
  if (-not (Test-Path $full)) { New-Item -ItemType Directory -Path $full -Force | Out-Null }
}

$env:TMP                      = Join-Path $toolchain 'tmp'
$env:TEMP                     = Join-Path $toolchain 'tmp'
$env:HOME                     = Join-Path $toolchain 'home'
$env:APPDATA                  = Join-Path $toolchain 'appdata'
$env:LOCALAPPDATA             = Join-Path $toolchain 'localappdata'
$env:PUB_CACHE                = Join-Path $toolchain 'pub-cache'
$env:GRADLE_USER_HOME         = Join-Path $toolchain 'gradle'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL           = 'https://pub.flutter-io.cn'

# --- JDK 17（Temurin 17.0.21，用于 Gradle / AGP）---
$jdkHome = Join-Path $toolchain 'jdk'
$env:JAVA_HOME = $jdkHome

# --- Android SDK（platform-tools + android-36 + build-tools 36.0.0）---
$androidSdk = Join-Path $toolchain 'android-sdk'
$env:ANDROID_SDK_ROOT = $androidSdk
$env:ANDROID_HOME     = $androidSdk

$pathEntries = @(
  (Join-Path $toolchain 'flutter-sdk\bin'),
  (Join-Path $jdkHome 'bin'),
  (Join-Path $androidSdk 'platform-tools')
)
foreach ($entry in $pathEntries) {
  if ($env:Path -notlike "*$entry*") {
    $env:Path = "$entry;" + $env:Path
  }
}

Write-Host "[flutter-env] Flutter SDK : $toolchain\flutter-sdk" -ForegroundColor Cyan
Write-Host "[flutter-env] JAVA_HOME   : $env:JAVA_HOME" -ForegroundColor Cyan
Write-Host "[flutter-env] ANDROID_SDK : $env:ANDROID_SDK_ROOT" -ForegroundColor Cyan
Write-Host "[flutter-env] PUB_CACHE   : $env:PUB_CACHE" -ForegroundColor Cyan
Write-Host "[flutter-env] TMP/TEMP    : $env:TMP" -ForegroundColor Cyan
Write-Host "[flutter-env] 下一步可以执行: flutter pub get / analyze / test / build apk --debug" -ForegroundColor DarkGray

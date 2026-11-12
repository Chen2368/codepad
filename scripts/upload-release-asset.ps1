# 用 GitHub API 上传 Release 附件（网页上传失败时的替代方案）
#
# 用法:
#   .\scripts\upload-release-asset.ps1 -Token <你的PAT> -Tag v1.0.0 -File .\dist\CodePad-1.0.0-release-arm64.apk
#
# Token 只需 repo 权限（classic）或 Contents: Read and write（fine-grained）。
# 脚本不会保存 Token；上传完可在 https://github.com/settings/tokens 撤销。

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Token,
  [string]$Owner = 'Chen2368',
  [string]$Repo  = 'codepad',
  [string]$Tag   = 'v1.0.0',
  [Parameter(Mandatory = $true)][string]$File,
  [string]$AssetName = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $File)) { throw "找不到文件：$File" }
$item = Get-Item $File
if ([string]::IsNullOrWhiteSpace($AssetName)) { $AssetName = $item.Name }

$headers = @{
  Authorization          = "Bearer $Token"
  Accept                 = 'application/vnd.github+json'
  'User-Agent'           = 'codepad-release-uploader'
  'X-GitHub-Api-Version' = '2022-11-28'
}

function Step($n, $t) { Write-Host "`n[$n] $t" -ForegroundColor Cyan }
function Ok($t) { Write-Host "    OK  $t" -ForegroundColor Green }

# 1. 找到 Release
Step 1 "定位 Release $Tag"
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Tag" -Headers $headers -TimeoutSec 30
Ok "release id=$($release.id)  标题=$($release.name)  现有资产 $($release.assets.Count) 个"

# 2. 已有同名资产先删掉（避免 422 already_exists）
$existing = $release.assets | Where-Object { $_.name -eq $AssetName }
if ($existing) {
  Step 2 "删除同名旧资产 $AssetName"
  Invoke-RestMethod -Method Delete -Uri "https://api.github.com/repos/$Owner/$Repo/releases/assets/$($existing.id)" -Headers $headers -TimeoutSec 30 | Out-Null
  Ok '已删除'
} else {
  Step 2 '没有同名旧资产，跳过'
}

# 3. 上传（单次 PUT，带重试）
Step 3 "上传 $AssetName（{0:N1} MB）" -f ($item.Length / 1MB)
$uploadBase = "https://uploads.github.com/repos/$Owner/$Repo/releases/$($release.id)/assets"
$url = "$uploadBase`?name=$([uri]::EscapeDataString($AssetName))"

$bytes = [System.IO.File]::ReadAllBytes($item.FullName)
$asset = $null
for ($i = 1; $i -le 3; $i++) {
  try {
    $asset = Invoke-RestMethod -Method Post -Uri $url -Headers $headers `
      -ContentType 'application/octet-stream' -Body $bytes -TimeoutSec 600
    break
  } catch {
    Write-Host "    第 $i 次失败：$($_.Exception.Message)" -ForegroundColor Yellow
    if ($i -eq 3) { throw }
    Start-Sleep -Seconds 3
  }
}
Ok "asset id=$($asset.id)  服务端大小=$([Math]::Round($asset.size/1MB,1)) MB"

# 4. 校验：下载回来比大小与哈希
Step 4 '校验下载'
$downloadUrl = $asset.browser_download_url
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "verify-$($asset.id).apk"
Invoke-WebRequest -Uri $downloadUrl -Headers @{ 'User-Agent' = 'codepad-check' } -OutFile $tmp -TimeoutSec 600
$localHash = (Get-FileHash $item.FullName -Algorithm SHA256).Hash
$remoteHash = (Get-FileHash $tmp -Algorithm SHA256).Hash
Remove-Item $tmp -Force
if ($localHash -eq $remoteHash) {
  Ok "哈希一致 sha256=$localHash"
} else {
  Write-Host "    ! 哈希不一致：本地 $localHash / 远端 $remoteHash" -ForegroundColor Red
}

Write-Host "`n下载地址：" -ForegroundColor Cyan
Write-Host "  $downloadUrl"
Write-Host "Release 页面：" -ForegroundColor Cyan
Write-Host "  https://github.com/$Owner/$Repo/releases/tag/$Tag"

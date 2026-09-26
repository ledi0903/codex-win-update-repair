[CmdletBinding()]
param(
  [switch]$AuditOnly,
  [switch]$Launch,
  [string]$PackageRoot,
  [string]$RuntimeRoot
)

$ErrorActionPreference = 'Stop'

function Get-ManifestVersion([string]$Directory) {
  $manifestPath = Join-Path $Directory 'manifest.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $null }
  try { return [string]((Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).runtime_archive_version) }
  catch { return $null }
}

function Test-RuntimeComplete([string]$Directory) {
  $required = @('manifest.json', 'bin\node.exe', 'bin\node_repl.exe')
  foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $Directory $relative) -PathType Leaf)) { return $false }
  }
  return $true
}

function Get-TreeManifest([string]$Directory) {
  $base = [IO.Path]::GetFullPath($Directory).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  $files = Get-ChildItem -LiteralPath $Directory -Recurse -File -Force | ForEach-Object {
    $fullPath = [IO.Path]::GetFullPath($_.FullName)
    if (-not $fullPath.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
      throw "File escaped runtime tree while verifying: $fullPath"
    }
    [pscustomobject]@{
      RelativePath = $fullPath.Substring($base.Length)
      Length = $_.Length
      Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
  }
  return @($files | Sort-Object RelativePath)
}

function Copy-TreeBytes([string]$Source, [string]$Destination) {
  $sourceBase = [IO.Path]::GetFullPath($Source).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  Get-ChildItem -LiteralPath $Source -Recurse -File -Force | ForEach-Object {
    $fullPath = [IO.Path]::GetFullPath($_.FullName)
    if (-not $fullPath.StartsWith($sourceBase, [StringComparison]::OrdinalIgnoreCase)) {
      throw "File escaped package runtime tree while copying: $fullPath"
    }
    $relative = $fullPath.Substring($sourceBase.Length)
    $target = Join-Path $Destination $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    $inputStream = [IO.File]::OpenRead($_.FullName)
    try {
      $outputStream = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
      try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
    }
    finally { $inputStream.Dispose() }
  }
}

function Start-CodexDesktop([string]$PackageFamilyName) {
  if (-not $PackageFamilyName) { throw 'Cannot launch Codex because the AppX package identity is unavailable.' }
  Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$PackageFamilyName!App"
  $window = $null
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    $window = Get-Process ChatGPT -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($window) { break }
  }
  if ($window) { Write-Output "launch=visible pid=$($window.Id) hwnd=$($window.MainWindowHandle)" }
  else { Write-Output 'launch=not-yet-visible; runtime check succeeded, but window startup was not confirmed within 30 seconds.' }
}

if (-not $RuntimeRoot) { $RuntimeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node' }
if (-not $PackageRoot) {
  $package = Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1
  if (-not $package) { throw 'OpenAI.Codex AppX package is not installed.' }
  $PackageRoot = Join-Path $package.InstallLocation 'app\resources\cua_node'
  $packageVersion = [string]$package.Version
  $packageFamilyName = [string]$package.PackageFamilyName
}
else {
  $package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
  $packageVersion = if ($package) { [string]$package.Version } else { 'fixture' }
  $packageFamilyName = if ($package) { [string]$package.PackageFamilyName } else { 'OpenAI.Codex_2p2nqsd0c76g0' }
}

$runtimeVersion = Get-ManifestVersion $PackageRoot
if (-not $runtimeVersion) { throw "Bundled runtime manifest is missing or invalid: $(Join-Path $PackageRoot 'manifest.json')" }
if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot 'bin\node.exe')) -or
    -not (Test-Path -LiteralPath (Join-Path $PackageRoot 'bin\node_repl.exe'))) {
  throw "Bundled runtime is missing required node binaries: $PackageRoot"
}

Write-Output "package=$packageVersion runtime=$runtimeVersion"

$complete = Get-ChildItem -LiteralPath $RuntimeRoot -Directory -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike '.staging-*' -and (Get-ManifestVersion $_.FullName) -eq $runtimeVersion -and (Test-RuntimeComplete $_.FullName) } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($complete) {
  Write-Output "runtime=complete path=$($complete.FullName)"
  if ($Launch) { Start-CodexDesktop $packageFamilyName }
  exit 0
}

$staging = Get-ChildItem -LiteralPath $RuntimeRoot -Directory -Filter '.staging-*' -Force -ErrorAction SilentlyContinue |
  Where-Object { (Get-ManifestVersion $_.FullName) -eq $runtimeVersion -and $_.Name -match '^\.staging-([a-fA-F0-9]{16})-' } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $staging) {
  Write-Output 'runtime=incomplete; matching staging directory not found. Do not guess the runtime ID; retry after one normal launch has created a current-version staging directory.'
  exit 3
}

$runtimeId = [regex]::Match($staging.Name, '^\.staging-([a-fA-F0-9]{16})-').Groups[1].Value.ToLowerInvariant()
$destination = Join-Path $RuntimeRoot $runtimeId
if (Test-Path -LiteralPath $destination) {
  throw "A final directory already exists but is incomplete; preserving it and stopping: $destination"
}

$running = Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith((Split-Path -Parent (Split-Path -Parent $PackageRoot)), [StringComparison]::OrdinalIgnoreCase) }
if ($running) { throw 'Codex Desktop processes are running. Close Codex completely, then rerun; the repair will not terminate user processes.' }

if ($AuditOnly) {
  Write-Output "runtime=incomplete stage=$($staging.FullName) expected=$destination"
  exit 2
}

$repairTemp = Join-Path $RuntimeRoot ".repair-$runtimeId-$([guid]::NewGuid().ToString('N'))"
try {
  Copy-TreeBytes $PackageRoot $repairTemp
  $sourceFiles = Get-TreeManifest $PackageRoot
  $copiedFiles = Get-TreeManifest $repairTemp
  if ($sourceFiles.Count -ne $copiedFiles.Count) { throw "File-count mismatch: source=$($sourceFiles.Count), copied=$($copiedFiles.Count)" }
  for ($i = 0; $i -lt $sourceFiles.Count; $i++) {
    if ($sourceFiles[$i].RelativePath -ne $copiedFiles[$i].RelativePath -or
        $sourceFiles[$i].Length -ne $copiedFiles[$i].Length -or
        $sourceFiles[$i].Hash -ne $copiedFiles[$i].Hash) {
      throw "Runtime verification mismatch at relative path: $($sourceFiles[$i].RelativePath)"
    }
  }
  if (-not (Test-RuntimeComplete $repairTemp)) { throw 'Required runtime files are missing after copy.' }
  Move-Item -LiteralPath $repairTemp -Destination $destination
  Write-Output "runtime=complete id=$runtimeId files=$($sourceFiles.Count) verified=sha256 destination=$destination"
}
catch {
  if (Test-Path -LiteralPath $repairTemp) { Remove-Item -LiteralPath $repairTemp -Recurse -Force -ErrorAction SilentlyContinue }
  throw
}

if ($Launch -and $package) {
  Start-CodexDesktop $packageFamilyName
}

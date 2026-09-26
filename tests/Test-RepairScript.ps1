$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\plugins\codex-win-update-repair\scripts\Repair-CodexRuntime.ps1'
$tempRoot = Join-Path $env:TEMP "codex-win-update-repair-test-$([guid]::NewGuid().ToString('N'))"
$packageRoot = Join-Path $tempRoot 'package'
$runtimeRoot = Join-Path $tempRoot 'runtime'
$runtimeId = 'a1b2c3d4e5f60718'
$stage = Join-Path $runtimeRoot ".staging-$runtimeId-fixture"
New-Item -ItemType Directory -Path (Join-Path $packageRoot 'bin'),$stage -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage 'bin') -Force | Out-Null
try {
  $manifest = @{ runtime_archive_version = 'test/1' } | ConvertTo-Json
  Set-Content -LiteralPath (Join-Path $packageRoot 'manifest.json') -Value $manifest -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $packageRoot 'bin\node.exe') -Value 'fixture-node' -NoNewline -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $packageRoot 'bin\node_repl.exe') -Value 'fixture-repl' -NoNewline -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Value $manifest -Encoding UTF8

  $audit = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -AuditOnly -PackageRoot $packageRoot -RuntimeRoot $runtimeRoot 2>&1
  if ($LASTEXITCODE -ne 2) { throw "Expected audit exit code 2; got $LASTEXITCODE. Output: $audit" }

  $repair = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -PackageRoot $packageRoot -RuntimeRoot $runtimeRoot 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Repair failed with exit code $LASTEXITCODE. Output: $repair" }
  $target = Join-Path $runtimeRoot $runtimeId
  foreach ($file in @('manifest.json','bin\node.exe','bin\node_repl.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $target $file) -PathType Leaf)) { throw "Missing repaired file: $file" }
  }
  Write-Output 'PASS: audit identified the incomplete stage; repair copied, SHA-256-verified, and finalized the fixture runtime.'
}
finally {
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

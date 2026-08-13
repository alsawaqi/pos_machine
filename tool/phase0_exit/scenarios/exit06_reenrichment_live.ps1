# Phase 0 exit gate - EXIT-06 (machine geofence re-enrichment against the LIVE
# harness API, test-only).
#
# Thin wrapper: the real driver is the Dart integrated test being built in a
# parallel lane at test/phase0_exit/integrated/exit06_reenrichment_live_test.dart
# (pos_machine). It runs the machine's own payload builders / re-enrichment
# path against the fenced fixture device (900116, branch 900115 'P0 Fenced')
# and asserts the enriched replay is accepted exactly once by the harness API.
#
# Contract (fixed): `flutter test <file> --reporter expanded` with env
#   PHASE0_INTEGRATED=1
#   PHASE0_BASE_URL=http://127.0.0.1:58000/api/v1
#   PHASE0_DEVICE_TOKEN=phase0-mdev-machine-fenced
#   PHASE0_SALES_N=5  PHASE0_PRODUCT_ID=900141
#   PHASE0_CUSTOMER_ID=900130  PHASE0_STAFF_ID=900120
#
# While the Dart driver has not landed yet this wrapper reports NOT-READY
# (the gate records it as a failure - a missing driver is never a pass).

function Invoke-Scenario {
  param($Dc, $Db, $Art, $CharityDb)

  $repo = 'C:\src\projects\pos_machine'
  $testFile = Join-Path $repo 'test\phase0_exit\integrated\exit06_reenrichment_live_test.dart'
  if (-not (Test-Path $testFile)) {
    return New-ScenarioResult -Id 'exit06_reenrichment_live' -Result 'NOT-READY' `
      -Detail "Dart integrated driver not present yet: $testFile (built in a parallel lane; wrapper is armed and will run it as-is)" `
      -Before (Get-EffectCounts -Db $Db -CharityDb $CharityDb) -After $null -ExpectedDelta $null
  }
  if ($null -eq (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "flutter CLI not found on PATH - cannot run the Dart integrated driver $testFile"
  }

  $before = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  $outFile = Join-Path $Art 'exit06_flutter.txt'
  $errFile = Join-Path $Art 'exit06_flutter_err.txt'

  $saved = @{}
  $envMap = @{
    PHASE0_INTEGRATED = '1'
    PHASE0_BASE_URL = 'http://127.0.0.1:58000/api/v1'
    PHASE0_DEVICE_TOKEN = 'phase0-mdev-machine-fenced'
    PHASE0_SALES_N = '5'
    PHASE0_PRODUCT_ID = '900141'
    PHASE0_CUSTOMER_ID = '900130'
    PHASE0_STAFF_ID = '900120'
  }
  foreach ($k in $envMap.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $envMap[$k]) }
  try {
    $p = Start-Process -FilePath 'cmd.exe' `
      -ArgumentList '/d', '/c', 'flutter', 'test', $testFile, '--reporter', 'expanded' `
      -WorkingDirectory $repo -NoNewWindow -PassThru `
      -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    # PS 5.1: without touching .Handle before exit, ExitCode stays $null.
    $null = $p.Handle
    $deadline = (Get-Date).AddSeconds(420)
    while (-not $p.HasExited) {
      if ((Get-Date) -gt $deadline) { try { $p.Kill() } catch {}; throw "exit06 Dart driver exceeded its 420s bound - killed (see $outFile)" }
      Start-Sleep -Milliseconds 500
    }
    $code = $p.ExitCode
  } finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  }

  $tail = ''
  if (Test-Path $outFile) { $tail = (@(Get-Content $outFile -ErrorAction SilentlyContinue | Select-Object -Last 8) -join ' // ') }
  if ($code -ne 0) {
    throw "exit06 Dart driver exited $code - the machine re-enrichment live scenario FAILED. Tail: $tail (full output: $outFile)"
  }

  $after = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  return New-ScenarioResult -Id 'exit06_reenrichment_live' -Result 'PASS' `
    -Detail "machine Dart driver green against the live harness API (fenced device 900116). Tail: $tail" `
    -Before $before -After $after -ExpectedDelta $null
}

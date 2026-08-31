# Runs the Pester suite with code coverage against the SOURCE tree and prints a percentage per
# source file plus every missed command.
#
# Usage (from the repo root):
#   ./tasks.ps1 coverage [-MinimumPercent 90]
#   pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Tools/coverage.ps1
#
# Coverage is measured per host. Compare hosts before calling a line untested.

param(
  # Exit non-zero when coverage falls below this percentage. 0 disables the gate.
  [double]$MinimumPercent = 0
)

$ErrorActionPreference = 'Stop'

# Build first so a run can never verify a stale artifact.
. $(Join-Path $PSScriptRoot 'build.ps1')

. $(Join-Path $PSScriptRoot 'module_info.ps1')
$info = Get-ModuleInfo

$sourceFiles = @(Get-ChildItem -Path $info.SourceRoot -Recurse -Filter '*.ps1' -File |
  Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object { $_.FullName })
if (-not $sourceFiles.Count) {
  Write-Host "No *.ps1 files under '$($info.SourceRoot)' yet; running the suite without coverage."
}

Remove-Module Pester -Force -ErrorAction SilentlyContinue
Import-Module Pester -MinimumVersion 5.0.0 -Force

$c = New-PesterConfiguration
$c.Run.Path = Join-Path $info.RepoRoot 'Tests'
$c.Run.PassThru = $true
$c.Output.Verbosity = 'None'
if ($sourceFiles.Count) {
  $c.CodeCoverage.Enabled = $true
  $c.CodeCoverage.Path = $sourceFiles
}

$strict = $ErrorActionPreference
$targetVariable = Get-TestTargetVariableName
$previousTarget = [Environment]::GetEnvironmentVariable($targetVariable)
try {
  $ErrorActionPreference = 'Continue'
  [Environment]::SetEnvironmentVariable($targetVariable, 'Source')
  $r = Invoke-Pester -Configuration $c
} finally {
  [Environment]::SetEnvironmentVariable($targetVariable, $previousTarget)
  $ErrorActionPreference = $strict
}

Write-Host ("Tests: {0} passed, {1} failed" -f $r.PassedCount, $r.FailedCount)
if ($r.FailedCount -gt 0) { exit 1 }
if (-not $sourceFiles.Count) { return }

$cc = $r.CodeCoverage
$pct = if ($cc.CommandsAnalyzedCount) { $cc.CommandsExecutedCount / $cc.CommandsAnalyzedCount * 100 } else { 0 }

Write-Host ("Coverage: {0}/{1} = {2:N1}%" -f $cc.CommandsExecutedCount, $cc.CommandsAnalyzedCount, $pct)

$perFile = @{}
foreach ($pair in @(@{ Set = $cc.CommandsExecuted; Hit = $true }, @{ Set = $cc.CommandsMissed; Hit = $false })) {
  foreach ($command in @($pair.Set)) {
    $name = Split-Path -Leaf $command.File
    if (-not $perFile.ContainsKey($name)) { $perFile[$name] = @{ Executed = 0; Analyzed = 0 } }
    $perFile[$name].Analyzed++
    if ($pair.Hit) { $perFile[$name].Executed++ }
  }
}

Write-Host "--- Per file ---"
foreach ($name in ($perFile.Keys | Sort-Object)) {
  $file = $perFile[$name]
  Write-Host ("  {0,6:N1}%  {1,4}/{2,-4} {3}" -f (($file.Executed / $file.Analyzed) * 100), $file.Executed, $file.Analyzed, $name)
}

if ($cc.CommandsMissed.Count) {
  Write-Host "--- Missed ---"
  $cc.CommandsMissed | Sort-Object File, Line | ForEach-Object {
    Write-Host ("  {0}:{1}: {2}" -f (Split-Path -Leaf $_.File), $_.Line, $_.Command)
  }
}

if ($pct -lt $MinimumPercent) {
  Write-Host ("Coverage {0:N1}% is below the {1:N1}% threshold." -f $pct, $MinimumPercent)
  exit 1
}

# Builds the module, then runs the Pester suite against the tree -Target names. Throws on any
# test failure, so it can gate a release or a CI job.
#
# Usage (from the repo root):
#   ./tasks.ps1 test
#   ./tasks.ps1 test -Target Dist -Path Tests/Module.Tests.ps1
#   pwsh -File Tools/tests.ps1 [-Target Source|Dist] [-Path <tests>] [-PassThru]

param(
  # Which tree the behaviour suite imports. The artifact tests always read the build output.
  [ValidateSet('Source', 'Dist')]
  [string]$Target = 'Source',

  # Which tests to run, a file or a directory. Defaults to the whole test directory.
  [string]$Path,

  # Emit the Pester result object as well, for a caller that wants the counts.
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

. $(Join-Path $PSScriptRoot 'module_info.ps1')

# Build first so a run can never verify a stale artifact.
. $(Join-Path $PSScriptRoot 'build.ps1')

# Force Pester v5+. On Windows PowerShell 5.1 the built-in Pester 3.4 would otherwise load and
# New-PesterConfiguration would not exist, silently skipping the whole suite.
Remove-Module Pester -Force -ErrorAction SilentlyContinue
Import-Module Pester -MinimumVersion 5.0.0 -Force

# Join-Path's 3-argument form is PowerShell 7+ only; nest for Windows PowerShell 5.1.
$requested = if ($Path) { $Path } else { Join-Path (Join-Path $PSScriptRoot '..') 'Tests' }
$testPath = Resolve-Path -Path $requested -ErrorAction SilentlyContinue
if (-not $testPath) {
  throw "Test path '$requested' does not exist. Refusing to report success on an empty run."
}
$found = if (Test-Path -LiteralPath $testPath.Path -PathType Container) {
  Get-ChildItem -Path $testPath.Path -Filter '*.Tests.ps1' -Recurse -ErrorAction SilentlyContinue
} else {
  Get-Item -LiteralPath $testPath.Path -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.Tests.ps1' }
}
if (-not $found) {
  throw "No *.Tests.ps1 files found under '$($testPath.Path)'. Refusing to report success on an empty run."
}

$config = New-PesterConfiguration
$config.Run.Path = $testPath.Path
# Always PassThru: the result object is how this script decides its own exit status. Run.Exit
# is deliberately left off, because it would kill the caller's whole session rather than
# letting the throw below propagate.
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'

$strict = $ErrorActionPreference
$targetVariable = Get-TestTargetVariableName
$previousTarget = [Environment]::GetEnvironmentVariable($targetVariable)
try {
  $ErrorActionPreference = 'Continue'
  [Environment]::SetEnvironmentVariable($targetVariable, $Target)
  $result = Invoke-Pester -Configuration $config
} finally {
  [Environment]::SetEnvironmentVariable($targetVariable, $previousTarget)
  $ErrorActionPreference = $strict
}

if (-not $result -or $result.FailedCount -gt 0) {
  throw "Tests failed ($($result.FailedCount) failed / $($result.TotalCount) total)."
}

if ($PassThru.IsPresent) {
  $result
}

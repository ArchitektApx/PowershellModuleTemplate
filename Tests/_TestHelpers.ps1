# Shared by every *.Tests.ps1: target selection and import helpers. Dot-sourced in BeforeAll,
# and at top level where a -Skip: expression needs it. Names and paths come from
# Tools/module_info.ps1, so nothing here breaks when prepare renames the module.
. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools') 'module_info.ps1')

# 'Source' or 'Dist'. An environment variable, not a parameter: Pester evaluates -Skip:
# expressions at discovery time. Set via -Target on ./tasks.ps1 test.
function Get-TestTarget {
  [OutputType([string])]
  param()
  $value = [Environment]::GetEnvironmentVariable((Get-TestTargetVariableName))
  if ($value -eq 'Dist') { 'Dist' } else { 'Source' }
}

function Get-ModuleUnderTestPath {
  [OutputType([string])]
  param()
  if ((Get-TestTarget) -eq 'Dist') { Get-BuiltManifestPath } else { (Get-ModuleInfo).SourceManifest }
}

function Import-ModuleUnderTest {
  Import-OneModule -Manifest (Get-ModuleUnderTestPath)
}

function Import-BuiltModule {
  Import-OneModule -Manifest (Get-BuiltManifestPath)
}

# Unload by name first: Import-Module -Force loads a second module beside one imported from
# another path, leaving two modules of one name with doubled exports.
function Import-OneModule {
  param(
    [Parameter(Mandatory)]
    [string] $Manifest
  )
  Remove-Module -Name (Get-ModuleInfo).ModuleName -Force -ErrorAction SilentlyContinue
  Import-Module $Manifest -Force
}

# $null when the build is fresh, otherwise the sentence the artifact test fails with. Catches
# Pester run by hand against yesterday's build; ./tasks.ps1 test builds first anyway.
function Get-StaleBuildReason {
  [OutputType([string])]
  param()
  $info = Get-ModuleInfo
  $built = Get-ChildItem -Path $info.DistRoot -Recurse -Filter "$($info.ModuleName).psm1" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $built) {
    return "No built module under '$($info.DistRoot)'. Run './tasks.ps1 build'."
  }
  $newest = Get-ChildItem -Path $info.SourceRoot -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($newest -and $newest.LastWriteTime -gt $built.LastWriteTime) {
    return ("The built module is older than the source. '$($built.Name)' was built {0}, " -f $built.LastWriteTime.ToString('o')) +
      ("'$($newest.Name)' was changed {0}. Run './tasks.ps1 build'." -f $newest.LastWriteTime.ToString('o'))
  }
  $null
}

# Host check for -Skip: expressions; works on Windows PowerShell 5.1 where $IsWindows
# does not exist.
function Test-OnWindowsHost {
  [OutputType([bool])]
  param()
  ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows
}

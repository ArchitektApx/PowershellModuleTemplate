# The artifact tests, the only file that reads the build output. Green on a fresh clone;
# behaviour tests go in their own <Area>.Tests.ps1 and import via Import-ModuleUnderTest.

# Top level too, not just BeforeAll: -Skip: expressions run at discovery time.
. $PSScriptRoot/_TestHelpers.ps1

# A fresh clone defines no functions; the function-level checks skip then.
$SourceFunctionFiles = @(Get-ChildItem -Path (Get-ModuleInfo).SourceRoot -Recurse -Filter '*.ps1' -File |
    Where-Object { $_.Name -ne "$((Get-ModuleInfo).ModuleName).psm1" })
$SourceDefinesFunctions = [bool]($SourceFunctionFiles | Where-Object {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref] $null, [ref] $null)
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
  })

BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltModule
}

Describe 'Built module' {
  It 'was built from the source tree as it stands now' {
    $stale = Get-StaleBuildReason
    $stale | Should -BeNullOrEmpty -Because "$stale"
  }

  It 'produced a manifest under Dist' {
    Get-BuiltManifestPath | Should -Exist
  }

  It 'has a valid manifest' {
    { Test-ModuleManifest -Path (Get-BuiltManifestPath) } | Should -Not -Throw
  }

  It 'imports' {
    Get-Module -Name (Get-ModuleInfo).ModuleName | Should -Not -BeNullOrEmpty
  }
}

# A function the build misses only fails on a real install; catch it here instead.
Describe 'Every function in the source tree reaches the built module' -Skip:(-not $SourceDefinesFunctions) {
  BeforeAll {
    $script:Info = Get-ModuleInfo

    function script:Get-DefinedFunction {
      [OutputType([string[]])]
      param([string[]] $Path)

      $names = [System.Collections.Generic.HashSet[string]]::new()
      foreach ($file in $Path) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref] $null, [ref] $null)
        foreach ($function in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
          [void] $names.Add($function.Name)
        }
      }
      [string[]] $names
    }

    $script:InSource = @(Get-DefinedFunction -Path @(Get-ChildItem -Path $script:Info.SourceRoot -Recurse -Filter '*.ps1' -File |
        ForEach-Object { $_.FullName }))
    $script:InBuild = @(Get-DefinedFunction -Path @(Join-Path (Split-Path -Parent (Get-BuiltManifestPath)) "$($script:Info.ModuleName).psm1"))
  }

  It 'finds functions on both sides at all' {
    $script:InSource.Count | Should -BeGreaterThan 0
    $script:InBuild.Count | Should -BeGreaterThan 0
  }

  It 'defines every function the source tree defines' {
    $missing = @($script:InSource | Where-Object { $_ -notin $script:InBuild } | Sort-Object)
    $missing | Should -BeNullOrEmpty -Because "the source tree defines these and the built module does not: $($missing -join ', ')"
  }
}

# Nothing else keeps build.psd1's directory list and the dev loader's loop in step.
Describe 'The build configuration and the development loader' {
  BeforeAll {
    $script:Info = Get-ModuleInfo
    $script:Configured = @((Import-PowerShellDataFile -LiteralPath (Join-Path $script:Info.RepoRoot 'build.psd1')).SourceDirectories)

    $loader = Join-Path $script:Info.SourceRoot "$($script:Info.ModuleName).psm1"
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($loader, [ref] $null, [ref] $null)
    $loop = $ast.Find({
        param($n)
        $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Variable.VariablePath.UserPath -eq 'dir'
      }, $true)
    $script:Loaded = @($loop.Condition.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
        ForEach-Object { $_.Value })
  }

  It 'walks the same source directories on both sides' {
    $script:Configured.Count | Should -BeGreaterThan 0
    $both = "build.psd1 builds from '$($script:Configured -join ', ')' and the development loader dot-sources '$($script:Loaded -join ', ')'"
    @($script:Loaded | Sort-Object) | Should -Be @($script:Configured | Sort-Object) -Because $both
  }
}

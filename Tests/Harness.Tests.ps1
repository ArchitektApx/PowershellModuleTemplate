# Tests for the test harness itself, not for the module.

Describe 'Test runner' {
  # Regression test: tests.ps1 must lower $ErrorActionPreference to 'Continue' around
  # Invoke-Pester, or Write-Error below throws instead of writing to the stream.
  It 'lets a command write a non-terminating error to the stream' {
    function Invoke-ErrorWriter { [CmdletBinding()] param() Write-Error 'expected'; 'result' }
    $out = Invoke-ErrorWriter 2>&1
    $errors = @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $errors.Count | Should -Be 1
    $errors[0].ToString() | Should -Match 'expected'
    $out | Where-Object { $_ -eq 'result' } | Should -Not -BeNullOrEmpty
  }
}

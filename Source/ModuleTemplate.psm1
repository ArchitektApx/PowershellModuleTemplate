# Dot-sources the source tree when the module is imported straight from Source/ during
# development. ModuleBuilder concatenates these same files into the built .psm1 in Dist/,
# so this loop does not run for an installed module.
foreach ($dir in 'Enum', 'Classes', 'Private', 'Public') {
  $path = Join-Path $PSScriptRoot $dir
  if (Test-Path -LiteralPath $path) {
    # -Recurse and Sort-Object FullName mirror how ModuleBuilder walks and concatenates the
    # tree, so source and built module load files (and thus classes) in the same order.
    foreach ($file in Get-ChildItem -Path $path -Filter '*.ps1' -Recurse | Sort-Object FullName) {
      . $file.FullName
    }
  }
}

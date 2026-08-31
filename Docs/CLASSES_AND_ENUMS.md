# Classes and enums

`Source/Enum/` and `Source/Classes/` hold one `.ps1` file per type. PowerShell classes follow
rules that plain functions do not, and each one costs an afternoon when you hit it blind.
This file documents the template, so `./tasks.ps1 prepare` deletes it; a short version
survives in the generated README.

## Rules

**Files must be `.ps1`.** ModuleBuilder and the development loader both ignore `.psm1` files
in the source directories. `using module` pointed at a `.ps1` file always fails, with an error
that misleadingly names a type inside the target file. Together that means one class file can
never `using module` another; load order is what makes cross-file references work.

**Load order is alphabetical by full path, on both trees.** Nothing sorts by dependency. A base
class must sort before its derived class or the import dies with `Unable to find type [Base]`,
even inside the concatenated `.psm1`: forward references to a base class do not resolve. Use
numeric prefixes (`01-Message.ps1`) or numeric subdirectories (`Classes/00_Base/` sorts before
`Classes/Alert.ps1`). One edge case: `Message.Alert.ps1` sorts before `Message.ps1`, because
`.` sorts before letters. Enums already load before classes via the `SourceDirectories` order
in `build.psd1`.

**Callers do not see your types.** `Import-Module` never exposes classes or enums; that is a
PowerShell rule. `using module` on the built manifest does, but never on the source manifest,
because dot-sourced classes stay invisible to it. So behaviour tests that go through public
functions run against either tree, while a test that writes `[Alert]::new(...)` belongs in
`Tests/Module.Tests.ps1`, the artifact suite, with `using module` on `Get-BuiltManifestPath`.
If callers should get your types from plain `Import-Module`, see
[Export classes with type accelerators](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_classes#export-classes-with-type-accelerators); it works from both trees but adds a session-global registration you
maintain by hand, so the template leaves it out.

**`using namespace` in source files is fine.** ModuleBuilder hoists `using` statements to the
top of the built `.psm1`, and a dot-sourced file applies its own, so it works in both trees.

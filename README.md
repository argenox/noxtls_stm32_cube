# NoxTLS STM32Cube Pack

This repository tracks the STM32Cube Expansion Pack project for **Argenox NoxTLS**.

## Current layout

- `NoxTLS/Files/Argenox.NoxTLS.pdsc` - package descriptor (source of truth)
- `NoxTLS/.project/` - STM32PackCreator project metadata
- `NoxTLS/Files/Include/` - public headers for packaged components
- `NoxTLS/Files/Source/` - library source files for packaged components

## Suggested workflow

1. Add NoxTLS headers/sources under `NoxTLS/Files/Include` and `NoxTLS/Files/Source`.
2. Update `NoxTLS/Files/Argenox.NoxTLS.pdsc` with components and file entries.
3. Build new `.pack` releases from STM32PackCreator.
4. Commit descriptor/project/source changes to git.
5. Optionally tag releases with `vX.Y.Z`.

## Notes

- Generated `.pack` archives are ignored by git (reproducible build output).
- Keep versioning and release notes inside the `.pdsc` in sync with git tags.
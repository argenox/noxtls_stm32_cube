# NoxTLS STM32Cube Pack

This repository tracks the STM32Cube Expansion Pack project for **Argenox NoxTLS**.

## Current layout

- `third_party/noxtls/` - upstream NoxTLS tracked as a git submodule
- `NoxTLS/.project/` - STM32PackCreator project metadata
- `NoxTLS/Files/Argenox.NoxTLS.pdsc` - package descriptor (synced file list)
- `NoxTLS/Files/Include/` - staged headers for the pack
- `NoxTLS/Files/Source/` - staged source files for the pack
- `scripts/sync-noxtls.ps1` - sync automation (copy curated files + update `.pdsc`)

## Sync workflow

1. Update upstream code:
   - `git submodule update --init --recursive`
   - `git -C third_party/noxtls fetch --tags`
   - `git -C third_party/noxtls checkout <tag-or-commit>`
2. Run sync:
   - Windows PowerShell:
     `powershell -ExecutionPolicy Bypass -File .\scripts\sync-noxtls.ps1`
   - Linux/macOS bash:
     `bash ./scripts/sync-noxtls.sh`
3. Build a new `.pack` from STM32PackCreator.
4. Commit:
   - submodule pointer update
   - staged files under `NoxTLS/Files`
   - updated `.pdsc`

## Notes

- Generated `.pack` archives are ignored by git (reproducible build output).
- The sync script excludes test sources named `test_*.c`.
- Linux script option: `--skip-pdsc-update`
- PowerShell script option: `-SkipPdscUpdate`
- Keep `.pdsc` release versions in sync with your git tag strategy.
- GUI workflow is unchanged: you can still open the `.project` in STM32PackCreator and use **Save & Generate Pack**.

## CI Pack Build

- Workflow file: `.github/workflows/pack.yml`
- Triggered on:
  - pushes to `master` affecting pack/script files
  - pull requests affecting pack/script files
  - manual `workflow_dispatch`
- Pipeline steps:
  1. checkout repo with submodules
  2. run `./scripts/sync-noxtls.sh`
  3. run `./scripts/build-pack.sh`
  4. upload artifacts from `artifacts/pack/`

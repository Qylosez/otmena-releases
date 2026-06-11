# AGENTS.md

## Cursor Cloud specific instructions

This repository is **documentation-only**. The entire tracked tree is a single file: `README.md`
(Russian-language docs for **Otmena**, a Windows-only desktop GUI app that unblocks
Discord/YouTube/Telegram).

Key facts for future agents:

- There is **no application source code, package manifest, build system, test suite, lint
  config, or runnable service** committed to this repo. Do not spend time searching for one.
- The actual product is a Windows binary (`Otmena.exe`) built from PowerShell scripts
  (`app/build-app.ps1`, `utils/publish-update.ps1`) that are **not present here** — they live
  upstream / in release archives (see `README.md`). It depends on a WinDivert kernel driver and
  Windows administrator rights, so it **cannot be built or run on this Linux VM**.
- Consequently there is **nothing to install, build, lint, test, or run** for a development
  environment, and no update script is needed. Changes here are limited to editing `README.md`
  (and this file).

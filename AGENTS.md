# AGENTS.md

## Cursor Cloud specific instructions

**Otmena** is a Windows-only desktop anti-censorship tool (unblocks Discord / YouTube / Telegram,
and — see below — Cursor). The source lives here; release zips bundle the binaries.

### What runs where
- **GUI app** — `app/ZapretApp.cs` compiled to `Otmena.exe` by `app/build-app.ps1` (PowerShell + C#,
  WinForms). **Builds and runs only on Windows.** It cannot be built or run on this Linux VM.
- **Bypass engine (Discord/YouTube)** — `bin/winws.exe` + WinDivert kernel driver (zapret).
  Windows + admin only.
- **Encrypted tunnel (Telegram + Cursor/AI)** — `xray.exe` reading `telegram-vless/config.json`.
  **xray-core is cross-platform**, so the tunnel config CAN be validated and tested from Linux.

### Binaries are gitignored
`Otmena.exe`, `bin/*.exe|*.sys|*.dll|*.bin`, and `telegram-vless/bin/xray.exe` are NOT committed
(see `.gitignore`). They ship in the GitHub release zips (e.g. `Otmena-update.zip`,
`xray-windows-64.zip`) and are downloaded at runtime by `utils/ensure-xray.ps1`. To get them for
local inspection: `gh release download <tag> --repo Qylosez/otmena-releases`.

### Testing the tunnel without Windows (how this was verified)
The xray config can be exercised on Linux:
```
# install xray-core linux-64, then:
xray run -test -config telegram-vless/config.json     # validate
xray run -config telegram-vless/config.json &          # run
curl -x http://127.0.0.1:10809 https://ipinfo.io/json  # should exit in Poland (Warsaw)
```
PowerShell scripts can be syntax-checked with `pwsh` via
`[System.Management.Automation.Language.Parser]::ParseFile(...)`.

### Non-obvious gotchas
- **Reality fingerprint must stay `qq`.** The Poland server rejects other uTLS fingerprints
  (`chrome` fails with `REALITY: received real certificate`). Do not "upgrade" it without testing
  against the live server.
- **Tunnel egress is Poland (`45.144.48.81`, Warsaw).** That is the "always Europe" exit.
- **xray serves multiple local inbounds from one process:** `10808` (Telegram SOCKS),
  `10809` (Cursor HTTP), `10810` (Cursor SOCKS). All route to the `proxy` (Poland) outbound.
- **Cursor routing** is set by `utils/cursor-proxy.ps1`, which writes `http.proxy` into
  `%APPDATA%\Cursor\User\settings.json` (backed up to `*.otmena.bak`). `launcher.ps1 start` enables
  it only when port `10809` is actually listening; `launcher.ps1 stop` removes it. Cursor must be
  restarted for the proxy change to take effect.
- General system/MTS traffic stays **direct** (`utils/disable-system-proxy.ps1`); only apps pointed
  at the local inbounds go through Europe, so normal browsing/MTS is not broken.

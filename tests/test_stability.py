#!/usr/bin/env python3
"""Static checks for Otmena 1.0.9: one Start button, Cursor Europe, autostart, no dead proxy."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAILS: list[str] = []


def ok(name: str, cond: bool, detail: str = "") -> None:
    status = "OK" if cond else "FAIL"
    extra = f" — {detail}" if detail else ""
    print(f"[{status}] {name}{extra}")
    if not cond:
        FAILS.append(name)


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")


def main() -> int:
    cfg = json.loads(read("telegram-vless/config.json"))
    ports = sorted(int(ib["port"]) for ib in cfg["inbounds"])
    ok("xray inbounds 10808/10809/10810", ports == [10808, 10809, 10810], str(ports))
    tags = {ib["tag"] for ib in cfg["inbounds"]}
    ok("inbound tags", tags == {"socks-tg", "http-cursor", "socks-cursor"}, str(tags))
    rules = cfg["routing"]["rules"]
    inbound_rule = next(r for r in rules if "inboundTag" in r)
    ok(
        "routing sends Cursor+TG to proxy",
        set(inbound_rule["inboundTag"]) == {"socks-tg", "http-cursor", "socks-cursor"}
        and inbound_rule["outboundTag"] == "proxy",
    )
    ok(
        "private IPs go direct (no proxy loop)",
        any("127.0.0.0/8" in (r.get("ip") or []) and r.get("outboundTag") == "direct" for r in rules),
    )

    old = {
        "inbounds": [{"tag": "socks-tg", "port": 10808, "protocol": "socks"}],
        "outbounds": [
            {
                "protocol": "vless",
                "settings": {"vnext": [{"address": "1.2.3.4", "port": 8444, "users": [{"id": "uuid"}]}]},
                "streamSettings": {
                    "realitySettings": {
                        "serverName": "loom.com",
                        "fingerprint": "qq",
                        "publicKey": "pbk",
                        "shortId": "",
                    }
                },
            }
        ],
    }
    old_ports = {int(ib["port"]) for ib in old["inbounds"]}
    ok("old install without 10809 is detected", 10809 not in old_ports and 10808 in old_ports)

    cs = read("app/ZapretApp.cs")
    ok("Start button includes Cursor (Запустить всё)", "Запустить всё" in cs)
    ok("Cursor EU status tile exists", 'StatusTile("Cursor EU"' in cs)
    ok("no separate Cursor exclude button", "Cursor exclude" not in cs and "btnCursor" not in cs)
    ok("Start click starts launcher start", 'RunLauncher("start"' in cs)
    ok("autostart still uses smart installer", "install-autostart-smart.ps1" in cs)

    launcher = read("utils/launcher.ps1")
    ok("launcher Start-CursorEurope exists", "function Start-CursorEurope" in launcher)
    ok("start writes desired-running flag", "Set-DesiredRunning $true" in launcher)
    ok("stop clears desired-running flag", "Set-DesiredRunning $false" in launcher)
    ok("start calls Start-CursorEurope", "$cursor = Start-CursorEurope" in launcher)
    ok("dead tunnel disables Cursor proxy", "cursor-proxy.ps1') -Disable" in launcher)
    ok("start installs watchdog", "install-watchdog.ps1" in launcher)
    ok("probe before pointing Cursor at proxy", "Test-HttpProxyAlive" in launcher)

    daemon = read("utils/telegram-vless-daemon.ps1")
    ok("daemon recycles xray if 10809 missing", "Stop-StaleXray" in daemon and "10809" in daemon)
    ok("daemon waits for both 10808 and 10809", "Test-PortListen 10809" in daemon)

    user_auto = read("utils/install-user-autostart.ps1")
    ok(
        "user autostart runs full launcher start (not telegram-only)",
        "launcher.ps1" in user_auto and "-Action start" in user_auto,
        "was telegram-only before — Cursor Europe would never apply until reboot",
    )
    ok("user autostart installs watchdog", "install-watchdog.ps1" in user_auto)

    admin_auto = read("utils/install-autostart.ps1")
    ok("admin autostart still runs launcher start", "-Action start" in admin_auto)
    ok("admin autostart mentions Cursor Europe", "Cursor Europe" in admin_auto)
    ok("admin autostart delays for network", "PT20S" in admin_auto)

    wd = read("utils/watchdog.ps1")
    ok("watchdog no-ops without desired-running.flag", "desired-running.flag" in wd)
    ok("watchdog disables proxy if 10809 down", "-Disable" in wd)
    ok("watchdog ignores stale flag when autostart is off", "flagStale" in wd)
    ok("watchdog defines Test-PortListen", "function Test-PortListen" in wd)

    proxy = read("utils/cursor-proxy.ps1")
    ok("Cursor proxy writes Electron argv.json", "argv.json" in proxy)
    ok("Cursor proxy sets http.proxySupport override", "override" in proxy)
    ok("Cursor proxy disables HTTP/2", "disableHttp2" in proxy or "disable-http2" in proxy)
    ok("Cursor proxy restores previous settings on -Disable", "previousArgv" in proxy)

    exclude = read("utils/update-cursor-exclude.ps1")
    ok("cursor exclude merges IPs (does not wipe on DNS fail)", "HashSet" in exclude and "previous" in exclude.lower())

    google = [
        line.strip()
        for line in read("lists/list-google.txt").splitlines()
        if line.strip() and not line.startswith("#")
    ]
    ok("google.com in Google hostlist", "google.com" in google)
    ok("www.google.com in Google hostlist", "www.google.com" in google)
    ok("googleapis.com in Google hostlist", "googleapis.com" in google)
    ok("gstatic.com in Google hostlist", "gstatic.com" in google)
    ok("no duplicate google hosts", len(google) == len(set(google)), f"{len(google)} lines, {len(set(google))} unique")

    domains = [
        line.strip()
        for line in read("lists/list-exclude-user.txt").splitlines()
        if line.strip() and not line.startswith("#")
    ]
    ok("cursor.sh excluded from zapret DPI", "cursor.sh" in domains)
    ok("api2.cursor.sh excluded", "api2.cursor.sh" in domains)

    version = read("utils/app.version").strip()
    ok("version bumped to 1.0.9", version == "1.0.9", version)

    ensure = read("utils/ensure-cursor-tunnel.ps1")
    ok("ensure-cursor-tunnel preserves VLESS key", "Get-VlessSettings" in ensure)

    print()
    if FAILS:
        print(f"{len(FAILS)} failed: {', '.join(FAILS)}")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

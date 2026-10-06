#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
FAILS = []

def ok(name, cond, detail=""):
    print(f"[{'OK' if cond else 'FAIL'}] {name}" + (f" — {detail}" if detail else ""))
    if not cond:
        FAILS.append(name)

def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")

cs = read("app/ZapretApp.cs")
ok("Запустить всё", "Запустить всё" in cs)
ok("Cursor EU tile", 'StatusTile("Cursor EU"' in cs)
ok("no Cursor Europe button", "btnCursor" not in cs and "Cursor → Europe" not in cs)
ok("version 1.1.27", read("utils/app.version").strip() == "1.1.27")
launcher = read("utils/launcher.ps1")
ok("Start-CursorEurope", "function Start-CursorEurope" in launcher)
ok("start calls Cursor Europe", "$cursor = Start-CursorEurope" in launcher)
ok("no unsafe tg-fallback", "tg-fallback" not in read("utils/cursor-tunnel.ps1"))
ok("argv.json", "argv.json" in read("utils/cursor-proxy.ps1"))
ok("watchdog 20s", "$intervalSec = 20" in read("utils/cursor-watch.ps1"))
ok("user autostart launcher start", "-Action start" in read("utils/install-user-autostart.ps1"))
ok("gstatic in google list", "gstatic.com" in read("lists/list-google.txt"))
common = read("utils/otmena-common.ps1")
proxy_i = common.find("https://gh-proxy.com/'")
origin_i = common.find("[void]$list.Add($origin)")
ok("mirrors gh-proxy first", proxy_i != -1 and origin_i != -1 and proxy_i < origin_i)
ok("download timeout short", "$sec = 10" in common or "TimeoutSec = 10" in common)
apply = read("utils/apply-update.ps1")
ok("download before kill xray", apply.find("Save-Package -source") < apply.find("Get-Process -Name winws, xray"))
ok("bootstrap-update.ps1", (ROOT / "utils/bootstrap-update.ps1").is_file())
ok("FIX-UPDATE.bat", (ROOT / "FIX-UPDATE.bat").is_file())
ok("OTMENA-UPDATE.bat", (ROOT / "OTMENA-UPDATE.bat").is_file())
ok("bootstrap in GUI", "bootstrap-update.ps1" in cs)
chk = read("utils/check-updates.ps1")
ok("check-updates gh-proxy", "gh-proxy.com" in chk and "Save-UpdateZipQuick" in chk)
ok("check-updates local zip", "UPDATE_METHOD=local-zip" in chk)
ok("GUI check timeout 45s", 'RunScriptCapture("check-updates.ps1", "-Quiet", 45000)' in cs)
vless = read("telegram-vless/config.json")
ok("lithuania vpn.dance IP", "84.32.109.157" in vless)
ok("lithuania vpn.dance uuid", "5d29f4f3-d732-4c5a-8def-4d03acc59fb3" in vless)
ok("Reality SNI yandex.ru", '"serverName": "yandex.ru"' in vless)
ok("old Poland IP gone", "31.56.188.10" not in vless)
ok("RU direct telemost", "telemost.yandex.ru" in vless and "domain:gosuslugi.ru" in vless)
ok("direct list file", "telemost.yandex.ru" in read("lists/list-direct-ru.txt"))
ok("exclude telemost", "telemost.yandex.ru" in read("lists/list-exclude.txt"))
ok("exclude government.ru", "government.ru" in read("lists/list-exclude.txt"))
ok("clean-stale-install.ps1", (ROOT / "utils/clean-stale-install.ps1").is_file())
ok("apply-update cleans stale", "clean-stale-install.ps1" in apply)
ok("proxy override helper", "Get-OtmenaProxyOverride" in common)
ok("cache not preserved on update", "subscription.cache.txt" not in read("utils/otmena-common.ps1"))
print()
if FAILS:
    print("failed:", ", ".join(FAILS)); sys.exit(1)
print("all checks passed"); sys.exit(0)

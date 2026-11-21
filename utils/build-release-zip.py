#!/usr/bin/env python3
"""Pack an Otmena folder into a zip the installed 1.1.25 updater can extract.

Windows PowerShell 5.1 Expand-Archive writes root files, then throws on a
nested "/" entry and leaves Otmena.exe behind. apply-update then calls
ExtractToDirectory, which fails with "file already exists" and the button
shows "apply-update exit 1".

This zip writes directory entries first and nested files before root files.
If Expand-Archive throws on the first nested file, nothing is written yet
and ExtractToDirectory still succeeds. Non-ASCII entry names are omitted:
they abort that same cmdlet on some PCs.
"""
import os
import sys
import time
import zipfile


def _win_rel(path):
    return path.replace("/", "\\")


def pack_stage(stage, zip_path):
    stage = os.path.abspath(stage)
    pending = os.path.join(stage, "utils", "update-clean.pending")
    os.makedirs(os.path.dirname(pending), exist_ok=True)
    with open(pending, "w", encoding="ascii", newline="\n") as fh:
        fh.write("1\n")

    dirs = set()
    files = []
    for root, dirnames, filenames in os.walk(stage):
        rel = os.path.relpath(root, stage)
        if rel != ".":
            if any(ord(ch) > 127 for ch in rel):
                continue
            dirs.add(rel.replace("\\", "/"))
        for name in filenames:
            relf = name if rel == "." else os.path.join(rel, name).replace("\\", "/")
            if any(ord(ch) > 127 for ch in relf):
                continue
            files.append(relf)

    manifest_rel = "utils/payload-manifest.txt"
    if manifest_rel not in files:
        files.append(manifest_rel)
    manifest_path = os.path.join(stage, "utils", "payload-manifest.txt")
    with open(manifest_path, "w", encoding="utf-8-sig", newline="\r\n") as fh:
        for line in sorted({_win_rel(p) for p in files}, key=str.lower):
            fh.write(line + "\r\n")

    now = time.localtime()[:6]
    nested = sorted((p for p in set(files) if "/" in p), key=str.lower)
    roots = sorted((p for p in set(files) if "/" not in p), key=str.lower)
    with zipfile.ZipFile(zip_path, "w") as zf:
        for folder in sorted(dirs, key=lambda s: (s.count("/"), s.lower())):
            info = zipfile.ZipInfo(folder + "/", date_time=now)
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = (0o40755 << 16) | 0x10
            zf.writestr(info, b"")
        for rel in nested + roots:
            full = os.path.join(stage, *rel.split("/"))
            info = zipfile.ZipInfo(rel, date_time=now)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            with open(full, "rb") as fh:
                zf.writestr(info, fh.read())


def main(argv):
    if len(argv) != 3:
        print("usage: build-release-zip.py STAGE OUT.zip", file=sys.stderr)
        return 2
    pack_stage(argv[1], argv[2])
    with zipfile.ZipFile(argv[2]) as zf:
        names = zf.namelist()
    dirs = [n for n in names if n.endswith("/")]
    nested = [n for n in names if "/" in n and not n.endswith("/")]
    if not dirs or not nested:
        print("zip missing directory entries", file=sys.stderr)
        return 1
    first_file = next(n for n in names if not n.endswith("/"))
    if "/" not in first_file:
        print("first file must be nested, got " + first_file, file=sys.stderr)
        return 1
    print("entries", len(names), "dirs", len(dirs), "bytes", os.path.getsize(argv[2]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

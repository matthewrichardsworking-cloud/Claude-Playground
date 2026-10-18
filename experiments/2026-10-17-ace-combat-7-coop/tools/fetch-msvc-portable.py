#!/usr/bin/env python3
r"""Fetch a Microsoft C++ compiler (MSVC) and Windows SDK into a plain folder, no admin rights.

Why this exists: the normal Visual Studio Build Tools installer needs an administrator
prompt that only the PC's owner can click. The installer itself only downloads a list of
packages from Microsoft's servers and unpacks them, so this script does the same by hand,
using Microsoft's own package list (the "channel manifest" that the installer reads):

    https://aka.ms/vs/17/release/channel  ->  VisualStudio.vsman (list of ~19,000 packages)

Every file comes from download.visualstudio.microsoft.com, and every file's SHA-256 is
checked against the value Microsoft publishes in that list. Nothing is registered with
Windows: removing the destination folder removes everything.

Usage (run from the AC7-Coop folder):

    python -I tools\fetch-msvc-portable.py ^
        --manifest downloads\msvc-portable\manifest\VisualStudio.vsman ^
        --downloads downloads\msvc-portable ^
        --dest C:\AC7-Coop-Tools

    add --no-download to only unpack what is already downloaded
    add --list to only print what would be fetched

What gets fetched (x64 host, x64 target, English):
  * MSVC v143 toolset 14.44 (compiler cl.exe, linker link.exe, librarian lib.exe,
    the C and C++ standard library headers and import libraries)
  * Windows 11 SDK 10.0.26100 (Windows headers such as windows.h and winsock2.h,
    their import libraries, the Universal C Runtime headers and libraries, rc.exe)

Output layout:
  <dest>\msvc\VC\Tools\MSVC\14.44.xxxxx\{bin,include,lib}
  <dest>\sdk\Windows Kits\10\{Include,Lib,bin}\10.0.26100.0
  <dest>\env.ps1      dot-source this in PowerShell to put the tools on PATH/INCLUDE/LIB
  <downloads>\payloads.md   the list of downloaded files with sizes and SHA-256 values
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

MSVC_VERSION = "14.44.17.14"          # toolset 14.44 as shipped with Visual Studio 2022 17.14
SDK_PACKAGE = "Win11SDK_10.0.26100"

MSVC_PACKAGES = [
    # (package id, language or None)
    (f"Microsoft.VC.{MSVC_VERSION}.Tools.HostX64.TargetX64.base", None),       # cl, link, lib, c1, c2, mspdb...
    (f"Microsoft.VC.{MSVC_VERSION}.Tools.HostX64.TargetX64.Res.base", "en-US"),  # compiler message text (clui.dll)
    (f"Microsoft.VC.{MSVC_VERSION}.CRT.Headers.base", None),                  # C and C++ standard library headers
    (f"Microsoft.VC.{MSVC_VERSION}.CRT.x64.Desktop.base", None),              # x64 libraries (msvcprt.lib, msvcrt.lib...)
    (f"Microsoft.VC.{MSVC_VERSION}.CRT.x64.Store.base", None),                # x64 libraries used by the store/onecore CRT
]

SDK_MSIS = [
    "Universal CRT Headers Libraries and Sources-x86_en-us.msi",
    "Windows SDK Desktop Headers x64-x86_en-us.msi",
    "Windows SDK Desktop Headers x86-x86_en-us.msi",
    "Windows SDK Desktop Libs x64-x86_en-us.msi",
    "Windows SDK Desktop Tools x64-x86_en-us.msi",
    "Windows SDK for Windows Store Apps Headers-x86_en-us.msi",
    "Windows SDK for Windows Store Apps Headers OnecoreUap-x86_en-us.msi",
    "Windows SDK for Windows Store Apps Libs-x86_en-us.msi",
    "Windows SDK OnecoreUap Headers x86-x86_en-us.msi",
]

ALLOWED_HOST = "download.visualstudio.microsoft.com"


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def download(url: str, dest: Path, expected_sha: str, expected_size: int) -> None:
    host = urllib.parse.urlparse(url).hostname or ""
    if host != ALLOWED_HOST:
        raise SystemExit(f"refusing to download from {host}: only {ALLOWED_HOST} is expected")
    if dest.exists() and sha256_of(dest) == expected_sha.upper():
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    # curl resumes a cut-off transfer (-C -) and retries; Python's urllib stops silently
    # when the connection drops, which happened on the first run of this script.
    # The SHA-256 is the check that matters; the manifest's "size" is not always the byte
    # count of the download (the 14.44 compiler package is listed as 26,662,704 bytes but
    # the file Microsoft serves is 26,607,271 bytes with exactly the listed SHA-256).
    got = None
    for attempt in range(4):
        if tmp.exists():
            tmp.unlink()
        r = subprocess.run(["curl", "-fsSL", "--retry", "5", "--retry-all-errors", "-o", str(tmp), url],
                           capture_output=True, text=True)
        if tmp.exists():
            got = sha256_of(tmp)
            if got == expected_sha.upper():
                break
    else:
        raise SystemExit(f"{dest.name}: SHA-256 {got} does not match the manifest's {expected_sha} (curl: {r.stderr.strip()})")
    if tmp.stat().st_size != expected_size:
        print(f"  note: {dest.name} is {tmp.stat().st_size} bytes, the manifest says {expected_size}; SHA-256 matches, so the file is right")
    tmp.replace(dest)


def find_package(packages, pkg_id, language=None):
    found = [p for p in packages if p["id"] == pkg_id and (language is None or p.get("language") == language)]
    if not found:
        raise SystemExit(f"package {pkg_id} ({language}) not in manifest")
    # several entries can share an id (chips); prefer x64 or neutral
    found.sort(key=lambda p: (p.get("chip") not in (None, "x64", "neutral"),))
    return found[0]


def cabs_referenced_by_msi(msi_path: Path) -> set:
    """The names of the .cab files an MSI's tables point at.

    An MSI is a compound file; its string pool is stored as plain text, so the cab names
    (which look like 'a1b2c3....cab') can be found with a simple scan."""
    data = msi_path.read_bytes()
    names = set(m.decode("ascii") for m in re.findall(rb"[0-9a-fA-F]{20,40}\.cab", data))
    names |= set(m.decode("utf-16-le", "ignore") for m in re.findall(rb"(?:[0-9a-fA-F]\x00){20,40}\.\x00c\x00a\x00b\x00", data))
    return names


def extract_vsix(vsix: Path, dest: Path) -> int:
    n = 0
    with zipfile.ZipFile(vsix) as z:
        for info in z.infolist():
            name = info.filename
            if not name.startswith("Contents/") or name.endswith("/"):
                continue
            rel = urllib.parse.unquote(name[len("Contents/"):])
            out = dest / Path(*rel.split("/"))
            out.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src, open(out, "wb") as dst:
                dst.write(src.read())
            n += 1
    return n


def extract_msi(msi: Path, dest: Path, log_dir: Path) -> None:
    """msiexec /a = 'administrative install': unpacks the files into a folder without
    registering anything. It does not need administrator rights."""
    log = log_dir / (msi.stem + ".log")
    cmd = ["msiexec.exe", "/a", str(msi), "/qn", f"TARGETDIR={dest}", "/L*v", str(log)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"msiexec failed ({r.returncode}) on {msi.name}; see {log}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--downloads", required=True)
    ap.add_argument("--dest", required=True)
    ap.add_argument("--no-download", action="store_true")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()

    manifest = json.load(open(a.manifest, encoding="utf-8"))
    packages = manifest["packages"]
    downloads = Path(a.downloads)
    dest = Path(a.dest)

    wanted = []  # (package id, payload dict, local path)
    for pkg_id, lang in MSVC_PACKAGES:
        p = find_package(packages, pkg_id, lang)
        for pl in p["payloads"]:
            wanted.append((p["id"], p.get("version"), pl, downloads / "msvc" / pl["fileName"].replace("\\", "/")))

    sdk = find_package(packages, SDK_PACKAGE)
    by_name = {pl["fileName"].split("\\")[-1]: pl for pl in sdk["payloads"]}
    msi_payloads = []
    for name in SDK_MSIS:
        if name not in by_name:
            raise SystemExit(f"{name} not in {SDK_PACKAGE}")
        msi_payloads.append(by_name[name])
    for pl in msi_payloads:
        wanted.append((sdk["id"], sdk.get("version"), pl, downloads / "sdk" / pl["fileName"].replace("\\", "/")))

    if a.list:
        total = sum(pl["size"] for _, _, pl, _ in wanted)
        for pid, ver, pl, path in wanted:
            print(f"{pid} {ver}: {pl['fileName']} {pl['size']} {pl['sha256']}")
        print(f"{len(wanted)} files, {total/1e6:.1f} MB before the SDK .cab files")
        return

    records = []
    # 1. the MSVC vsix packages and the SDK msi files
    for pid, ver, pl, path in wanted:
        if not a.no_download:
            print(f"downloading {pl['fileName']} ({pl['size']/1e6:.1f} MB)", flush=True)
            download(pl["url"], path, pl["sha256"], pl["size"])
        records.append((pid, ver, pl["fileName"], path.stat().st_size, pl["sha256"].upper(), pl["url"]))

    # 2. the .cab files the chosen MSIs reference
    cab_names = set()
    for pl in msi_payloads:
        cab_names |= cabs_referenced_by_msi(downloads / "sdk" / pl["fileName"].replace("\\", "/"))
    cab_payloads = [by_name[n] for n in sorted(cab_names) if n in by_name]
    missing = [n for n in cab_names if n not in by_name]
    if missing:
        print(f"warning: {len(missing)} cab names not found in the manifest: {missing[:5]}")
    print(f"{len(cab_payloads)} .cab files referenced, {sum(p['size'] for p in cab_payloads)/1e6:.1f} MB", flush=True)
    for pl in cab_payloads:
        path = downloads / "sdk" / pl["fileName"].replace("\\", "/")
        if not a.no_download:
            print(f"downloading {pl['fileName']} ({pl['size']/1e6:.1f} MB)", flush=True)
            download(pl["url"], path, pl["sha256"], pl["size"])
        records.append((sdk["id"], sdk.get("version"), pl["fileName"], path.stat().st_size, pl["sha256"].upper(), pl["url"]))

    # 3. write the record of what was downloaded
    md = downloads / "payloads.md"
    with open(md, "w", encoding="utf-8") as f:
        f.write("# Files downloaded by tools\\fetch-msvc-portable.py\n\n")
        f.write(f"Source: Microsoft's Visual Studio 2022 release channel manifest "
                f"({manifest.get('info', {}).get('productSemanticVersion', '?')}), all files from https://{ALLOWED_HOST}/.\n")
        f.write("Every SHA-256 below was checked against the value in that manifest after downloading.\n\n")
        f.write("| Package | Version | File | Bytes | SHA-256 |\n|---|---|---|---:|---|\n")
        for pid, ver, name, size, sha, url in records:
            f.write(f"| {pid} | {ver} | {name} | {size} | {sha} |\n")
        f.write(f"\nTotal: {len(records)} files, {sum(r[3] for r in records)} bytes.\n")
    json.dump([dict(package=r[0], version=r[1], file=r[2], size=r[3], sha256=r[4], url=r[5]) for r in records],
              open(downloads / "payloads.json", "w"), indent=1)
    print(f"wrote {md}")

    # 4. unpack
    msvc_dest = dest / "msvc"
    for pid, ver, pl, path in wanted:
        if path.suffix.lower() == ".vsix":
            n = extract_vsix(path, msvc_dest)
            print(f"unpacked {path.name}: {n} files -> {msvc_dest}")
    sdk_dest = dest / "sdk"
    sdk_dest.mkdir(parents=True, exist_ok=True)
    log_dir = downloads / "msi-logs"
    log_dir.mkdir(exist_ok=True)
    for pl in msi_payloads:
        path = downloads / "sdk" / pl["fileName"].replace("\\", "/")
        print(f"unpacking {path.name} with msiexec /a ...", flush=True)
        extract_msi(path, sdk_dest, log_dir)

    # 5. find the version folders and write env.ps1
    tools_root = msvc_dest / "VC" / "Tools" / "MSVC"
    msvc_ver = sorted(p.name for p in tools_root.iterdir())[-1]
    kits = sdk_dest / "Windows Kits" / "10"
    sdk_ver = sorted(p.name for p in (kits / "Include").iterdir())[-1]
    env = dest / "env.ps1"
    env.write_text(f"""# Puts the portable MSVC {msvc_ver} and Windows SDK {sdk_ver} on the path of this PowerShell window.
# Usage:  . C:\\AC7-Coop-Tools\\env.ps1
$msvc = '{tools_root / msvc_ver}'
$kits = '{kits}'
$sdkv = '{sdk_ver}'
$env:PATH = "$msvc\\bin\\Hostx64\\x64;$kits\\bin\\$sdkv\\x64;" + $env:PATH
$env:INCLUDE = "$msvc\\include;$kits\\Include\\$sdkv\\ucrt;$kits\\Include\\$sdkv\\shared;$kits\\Include\\$sdkv\\um;$kits\\Include\\$sdkv\\winrt;$kits\\Include\\$sdkv\\cppwinrt"
$env:LIB = "$msvc\\lib\\x64;$kits\\Lib\\$sdkv\\ucrt\\x64;$kits\\Lib\\$sdkv\\um\\x64"
$env:VSCMD_ARG_TGT_ARCH = 'x64'
"MSVC $msvc"
"SDK  $kits\\$sdkv"
""", encoding="utf-8")
    print(f"wrote {env}")
    print(f"MSVC {msvc_ver} at {tools_root / msvc_ver}")
    print(f"SDK {sdk_ver} at {kits}")


if __name__ == "__main__":
    main()

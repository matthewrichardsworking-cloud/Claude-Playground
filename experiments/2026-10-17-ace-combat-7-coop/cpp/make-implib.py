#!/usr/bin/env python3
r"""Write a linker .def file listing everything UE4SS.dll exports.

A C++ mod calls into UE4SS.dll (for example the CppUserModBase constructor, the log
output and the Lua helpers). The linker needs an "import library" (UE4SS.lib) to resolve
those calls; UE4SS's own build produces one, but building UE4SS needs private Unreal
headers we do not have. The import library can be made from the DLL itself instead: this
script reads the DLL's export table and writes it as a .def file, and build.ps1 turns
that into UE4SS.lib with the librarian (lib.exe /def).

    python -I cpp\make-implib.py C:\AC7-Coop-Game\ue4ss\UE4SS.dll cpp\build\UE4SS.def
"""
import struct
import sys
from pathlib import Path


def exports(path: Path):
    data = path.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    secoff = opt + struct.unpack_from("<H", data, pe + 20)[0]
    secs = []
    for i in range(nsec):
        s = data[secoff + 40 * i : secoff + 40 * i + 40]
        vsz, va, rsz, ra = struct.unpack_from("<IIII", s, 8)
        secs.append((va, vsz, ra, rsz))

    def rva2off(r):
        for va, vsz, ra, rsz in secs:
            if va <= r < va + max(vsz, rsz):
                return ra + (r - va)
        raise ValueError(f"rva {r:#x} outside all sections")

    ddoff = opt + (112 if magic == 0x20B else 96)
    erva, esz = struct.unpack_from("<II", data, ddoff)
    eo = rva2off(erva)
    nnames = struct.unpack_from("<I", data, eo + 24)[0]
    names_rva = struct.unpack_from("<I", data, eo + 32)[0]
    no = rva2off(names_rva)
    out = []
    for i in range(nnames):
        o = rva2off(struct.unpack_from("<I", data, no + 4 * i)[0])
        out.append(data[o : data.index(b"\0", o)].decode("ascii"))
    return out


def is_data_symbol(name: str) -> bool:
    """MSVC-decorated names: after the final '@@' a digit 0-4 means a variable (static
    member or global), a letter means a function. Variables must be marked DATA in a
    .def file; getting a function wrong would make the linker build a bad call thunk."""
    i = name.rfind("@@")
    if i < 0 or i + 2 >= len(name):
        return False
    return name[i + 2] in "01234"


def main():
    dll = Path(sys.argv[1])
    out = Path(sys.argv[2])
    names = exports(dll)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="ascii") as f:
        f.write(f"LIBRARY {dll.name}\nEXPORTS\n")
        ndata = 0
        for n in names:
            if is_data_symbol(n):
                f.write(f"    {n} DATA\n")
                ndata += 1
            else:
                f.write(f"    {n}\n")
    print(f"{dll}: {len(names)} exports ({ndata} marked DATA) -> {out}")


if __name__ == "__main__":
    main()

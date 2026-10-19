r"""read-game-code.py: reads code out of the RUNNING test copy of Ace Combat 7 so a
session can understand a function by name, prove what a crash site does, or find which
functions use a string. Read-only: it opens the game process with read rights only and
never writes into it (no WriteProcessMemory anywhere in this file).

It only ever opens the copy at C:\AC7-Coop-Game\Ace7Game.exe. An Ace7Game.exe started
from anywhere else (the real install) is refused by name.

Rules it follows (README "Addendum, 18 Oct 2026"): the bytes of single functions may be
saved for analysis (AC7-Coop\code\<name>.bin, capped at 64 KB, 256 KB with --size);
whole code sections or an unscrambled exe are never written to disk.

Needs: Python 3 (written on 3.15) and, for the disassembly, the capstone package
(python -m pip install capstone; 5.0.9 was installed on 18 Oct 2026). Without capstone
the tool still reads, saves and prints the bytes as hex, and "refs" still works for the
unverified scan.

    python tools\read-game-code.py info
        which process was opened, its live base address, sections, import counts,
        whether the code is unpacked, and which object dump and base are in use

    python tools\read-game-code.py read exe+0x1da3319
    python tools\read-game-code.py read 0x7ff68c1f3319
    python tools\read-game-code.py read Object:ExecuteUbergraph
        read the function containing that address (or the UE4SS object-dump function
        with that name), save its bytes to code\<name>.bin and the listing to
        code\<name>.txt, and print the disassembly with call targets, imports, strings
        and jump targets named.  --size N reads exactly N bytes from the address
        instead of stopping at the function's end.  --no-save prints only.

    python tools\read-game-code.py refs SNL_P2P_HOST "%sSaveGames/%llu" exe+0x3054768
        find every instruction in the game's code that refers to that string (ASCII or
        UTF-16, as found in the game's data) or to that data address, and list the
        referencing functions with their nearest known name.

    python tools\read-game-code.py strings SNL_P2P
        list the strings in the game's data that contain the text (ASCII and UTF-16)

    python tools\read-game-code.py name exe+0x1da32e0
        just name an address: dump function, class vtable slot, containing function

Options for all commands:
    --dump FILE        UE4SS object dump to take function names from (default: the
                       newest UE4SS_ObjectDump.txt under AC7-Coop\dumps)
    --dump-base HEX    the exe's base address when that dump was written (the
                       "MainExe @ 0x..." line of that run's UE4SS.log). Found
                       automatically from a UE4SS.log next to the dump, else from the
                       copy's ue4ss\UE4SS.log, and checked against the live code range.
    --pid N            which process, if more than one copy is running
    --no-rtti          skip the class-name (RTTI) scan, a few seconds faster
"""

import argparse
import bisect
import ctypes
import ctypes.wintypes as wt
import os
import re
import struct
import sys
import time

COPY_EXE = r'C:\AC7-Coop-Game\Ace7Game.exe'
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CODE_DIR = os.path.join(PROJECT, 'code')
DUMPS_DIR = os.path.join(PROJECT, 'dumps')
GAME_LOG = r'C:\AC7-Coop-Game\ue4ss\UE4SS.log'
MAX_FUNC_BYTES = 64 * 1024
MAX_SIZE_OPTION = 256 * 1024

try:
    import capstone
    HAVE_CAPSTONE = True
except ImportError:  # pragma: no cover
    capstone = None
    HAVE_CAPSTONE = False


# ----------------------------------------------------------------------------- Win32

k32 = ctypes.WinDLL('kernel32', use_last_error=True)
try:
    psapi = ctypes.WinDLL('psapi', use_last_error=True)
except OSError:  # pragma: no cover
    psapi = k32

PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010
LIST_MODULES_ALL = 0x03

k32.OpenProcess.restype = wt.HANDLE
k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.CloseHandle.argtypes = [wt.HANDLE]
k32.ReadProcessMemory.restype = wt.BOOL
k32.ReadProcessMemory.argtypes = [wt.HANDLE, wt.LPCVOID, wt.LPVOID, ctypes.c_size_t,
                                  ctypes.POINTER(ctypes.c_size_t)]
k32.QueryFullProcessImageNameW.restype = wt.BOOL
k32.QueryFullProcessImageNameW.argtypes = [wt.HANDLE, wt.DWORD, wt.LPWSTR,
                                           ctypes.POINTER(wt.DWORD)]
k32.GetProcessTimes.argtypes = [wt.HANDLE, ctypes.POINTER(wt.FILETIME),
                                ctypes.POINTER(wt.FILETIME), ctypes.POINTER(wt.FILETIME),
                                ctypes.POINTER(wt.FILETIME)]

psapi.EnumProcesses.restype = wt.BOOL
psapi.EnumProcesses.argtypes = [ctypes.POINTER(wt.DWORD), wt.DWORD, ctypes.POINTER(wt.DWORD)]
psapi.EnumProcessModulesEx.restype = wt.BOOL
psapi.EnumProcessModulesEx.argtypes = [wt.HANDLE, ctypes.POINTER(wt.HMODULE), wt.DWORD,
                                       ctypes.POINTER(wt.DWORD), wt.DWORD]
psapi.GetModuleFileNameExW.restype = wt.DWORD
psapi.GetModuleFileNameExW.argtypes = [wt.HANDLE, wt.HMODULE, wt.LPWSTR, wt.DWORD]


class MODULEINFO(ctypes.Structure):
    _fields_ = [('lpBaseOfDll', ctypes.c_void_p), ('SizeOfImage', wt.DWORD),
                ('EntryPoint', ctypes.c_void_p)]


psapi.GetModuleInformation.restype = wt.BOOL
psapi.GetModuleInformation.argtypes = [wt.HANDLE, wt.HMODULE, ctypes.POINTER(MODULEINFO), wt.DWORD]


def process_image_path(pid):
    h = k32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return None
    try:
        buf = ctypes.create_unicode_buffer(1024)
        n = wt.DWORD(1024)
        if k32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(n)):
            return buf.value
        return None
    finally:
        k32.CloseHandle(h)


def find_copy_processes():
    """Every running process whose exe is the copy's. Refuses other Ace7Game.exe."""
    count = 4096
    arr = (wt.DWORD * count)()
    got = wt.DWORD(0)
    if not psapi.EnumProcesses(arr, ctypes.sizeof(arr), ctypes.byref(got)):
        raise OSError('EnumProcesses failed: %d' % ctypes.get_last_error())
    ok, refused = [], []
    for i in range(got.value // 4):
        pid = arr[i]
        if pid == 0:
            continue
        path = process_image_path(pid)
        if not path or os.path.basename(path).lower() != 'ace7game.exe':
            continue
        if os.path.normcase(path) == os.path.normcase(COPY_EXE):
            ok.append(pid)
        else:
            refused.append((pid, path))
    return ok, refused


class Process:
    def __init__(self, pid):
        self.pid = pid
        self.h = k32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
        if not self.h:
            raise OSError('OpenProcess(%d) failed: error %d (read rights only were asked for)'
                          % (pid, ctypes.get_last_error()))
        self.modules = self._modules()
        self.exe = self.modules[0]
        if os.path.normcase(self.exe[2]) != os.path.normcase(COPY_EXE):
            raise RuntimeError('first module is not the copy exe: %s' % self.exe[2])

    def _modules(self):
        needed = wt.DWORD(0)
        psapi.EnumProcessModulesEx(self.h, None, 0, ctypes.byref(needed), LIST_MODULES_ALL)
        n = needed.value // ctypes.sizeof(wt.HMODULE)
        arr = (wt.HMODULE * max(n, 1))()
        if not psapi.EnumProcessModulesEx(self.h, arr, ctypes.sizeof(arr), ctypes.byref(needed),
                                          LIST_MODULES_ALL):
            raise OSError('EnumProcessModulesEx failed: %d' % ctypes.get_last_error())
        out = []
        for i in range(needed.value // ctypes.sizeof(wt.HMODULE)):
            mi = MODULEINFO()
            psapi.GetModuleInformation(self.h, arr[i], ctypes.byref(mi), ctypes.sizeof(mi))
            buf = ctypes.create_unicode_buffer(1024)
            psapi.GetModuleFileNameExW(self.h, arr[i], buf, 1024)
            out.append((mi.lpBaseOfDll or 0, mi.SizeOfImage, buf.value))
        return out

    def started(self):
        c, e, k, u = wt.FILETIME(), wt.FILETIME(), wt.FILETIME(), wt.FILETIME()
        k32.GetProcessTimes(self.h, ctypes.byref(c), ctypes.byref(e), ctypes.byref(k), ctypes.byref(u))
        t = (c.dwHighDateTime << 32 | c.dwLowDateTime) / 1e7 - 11644473600
        return time.strftime('%H:%M:%S', time.localtime(t))

    def read(self, addr, size):
        """Read size bytes; pages that cannot be read come back as zeros."""
        out = bytearray()
        chunk = 1 << 20
        pos = addr
        end = addr + size
        while pos < end:
            n = min(chunk, end - pos)
            buf = ctypes.create_string_buffer(n)
            got = ctypes.c_size_t(0)
            if k32.ReadProcessMemory(self.h, ctypes.c_void_p(pos), buf, n, ctypes.byref(got)) and got.value == n:
                out += buf.raw
            else:
                # fall back page by page so one unreadable page does not lose the rest
                p = pos
                while p < pos + n:
                    m = min(0x1000 - (p & 0xfff), pos + n - p)
                    b2 = ctypes.create_string_buffer(m)
                    g2 = ctypes.c_size_t(0)
                    if k32.ReadProcessMemory(self.h, ctypes.c_void_p(p), b2, m, ctypes.byref(g2)) and g2.value == m:
                        out += b2.raw
                    else:
                        out += b'\0' * m
                    p += m
            pos += n
        return bytes(out)

    def module_of(self, addr):
        for base, size, path in self.modules:
            if base <= addr < base + size:
                return base, size, path
        return None

    def close(self):
        if self.h:
            k32.CloseHandle(self.h)
            self.h = None


# ----------------------------------------------------------------------------- PE on disk (exports)

def pe_exports(path):
    """{rva: name} of a DLL's export table, read from the file on disk (as in
    read-crash-dump-details.py). Forwarders are included by name."""
    try:
        d = open(path, 'rb').read()
    except OSError:
        return {}
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    nsec = struct.unpack_from('<H', d, pe + 6)[0]
    optsz = struct.unpack_from('<H', d, pe + 20)[0]
    opt = pe + 24
    exp_rva, exp_sz = struct.unpack_from('<II', d, opt + 112)
    if not exp_rva:
        return {}
    secs = []
    for i in range(nsec):
        s = pe + 24 + optsz + 40 * i
        vsz, va, rsz, rp = struct.unpack_from('<IIII', d, s + 8)
        secs.append((va, vsz, rp, rsz))

    def r2o(rva):
        for va, vsz, rp, rsz in secs:
            if va <= rva < va + max(vsz, rsz):
                return rva - va + rp
        return None

    e = r2o(exp_rva)
    if e is None:
        return {}
    nfunc, nnames, addr_t, name_t, ord_t = struct.unpack_from('<IIIII', d, e + 20)
    out = {}
    for i in range(nnames):
        nrva = struct.unpack_from('<I', d, r2o(name_t) + 4 * i)[0]
        o = struct.unpack_from('<H', d, r2o(ord_t) + 2 * i)[0]
        frva = struct.unpack_from('<I', d, r2o(addr_t) + 4 * o)[0]
        no = r2o(nrva)
        out[frva] = d[no:d.index(b'\0', no)].decode('latin1')
    return out


# ----------------------------------------------------------------------------- the live exe

class LiveExe:
    """The exe as it is in the running process: sections, imports, exception table,
    data strings, names from the object dump and from the class (RTTI) data."""

    def __init__(self, proc, dump=None, dump_base=None, rtti=True, quiet=False):
        self.proc = proc
        self.base, self.size, self.path = proc.exe
        self.say = (lambda *a: None) if quiet else (lambda *a: print(*a, file=sys.stderr))
        hdr = proc.read(self.base, 0x1000)
        pe = struct.unpack_from('<I', hdr, 0x3c)[0]
        nsec = struct.unpack_from('<H', hdr, pe + 6)[0]
        optsz = struct.unpack_from('<H', hdr, pe + 20)[0]
        opt = pe + 24
        self.entry_rva = struct.unpack_from('<I', hdr, opt + 16)[0]
        self.dirs = [struct.unpack_from('<II', hdr, opt + 112 + 8 * i) for i in range(16)]
        self.sections = []
        for i in range(nsec):
            s = pe + 24 + optsz + 40 * i
            name = hdr[s:s + 8].rstrip(b'\0').decode('latin1')
            vsz, va, rsz, rp = struct.unpack_from('<IIII', hdr, s + 8)
            flags = struct.unpack_from('<I', hdr, s + 36)[0]
            self.sections.append((name, va, vsz, rsz, flags))
        self.text = self.section('.text')
        self.text_lo = self.base + self.text[1]
        self.text_hi = self.text_lo + self.text[2]
        self._text_bytes = None
        self._data_cache = {}
        self._exports = {}
        self.imports = {}        # slot address -> 'DLL!name'
        self._load_imports()
        self._load_pdata()
        self.names = {}          # address -> [names]  (dump functions, exact)
        self.dump_file = None
        self.dump_base = None
        self.dump_delta = 0
        if dump:
            self._load_dump(dump, dump_base)
        self.vtable_names = {}   # address -> 'Class::vtbl[slot]'
        self.classes = 0
        if rtti:
            self._scan_rtti()
        self._sorted_names = None

    # --- sections and reads

    def section(self, name):
        for s in self.sections:
            if s[0] == name:
                return s
        return None

    def section_of(self, addr):
        rva = addr - self.base
        for s in self.sections:
            if s[1] <= rva < s[1] + max(s[2], s[3]):
                return s
        return None

    def in_text(self, addr):
        return self.text_lo <= addr < self.text_hi

    def text_bytes(self):
        if self._text_bytes is None:
            self.say('reading the live code section (%.1f MB) into memory, not to disk...'
                     % (self.text[2] / 1048576))
            self._text_bytes = self.proc.read(self.text_lo, self.text[2])
        return self._text_bytes

    def section_bytes(self, name):
        if name not in self._data_cache:
            s = self.section(name)
            self._data_cache[name] = self.proc.read(self.base + s[1], s[2]) if s else b''
        return self._data_cache[name]

    def read(self, addr, n):
        if self.in_text(addr) and self._text_bytes is not None and addr + n <= self.text_hi:
            o = addr - self.text_lo
            return self._text_bytes[o:o + n]
        return self.proc.read(addr, n)

    def rva(self, addr):
        return addr - self.base

    def fmt(self, addr):
        if self.base <= addr < self.base + self.size:
            return 'exe+0x%x' % (addr - self.base)
        m = self.proc.module_of(addr)
        if m:
            return '%s+0x%x' % (os.path.basename(m[2]), addr - m[0])
        return '0x%x' % addr

    # --- imports (static and delay-load) from live memory

    def _cstr(self, addr, limit=256):
        b = self.proc.read(addr, limit)
        i = b.find(b'\0')
        return b[:i if i >= 0 else limit].decode('latin1')

    def _load_imports(self):
        imp_rva, imp_sz = self.dirs[1]
        if imp_rva:
            desc = self.proc.read(self.base + imp_rva, imp_sz + 20)
            o = 0
            while o + 20 <= len(desc):
                oft, ts, fc, name, iat = struct.unpack_from('<IIIII', desc, o)
                if name == 0:
                    break
                self._walk_thunks(self._cstr(self.base + name), self.base + (oft or iat), self.base + iat)
                o += 20
        dl_rva, dl_sz = self.dirs[13]
        if dl_rva:
            desc = self.proc.read(self.base + dl_rva, dl_sz + 32)
            o = 0
            while o + 32 <= len(desc):
                attr, name, hmod, iat, int_, biat, uiat, ts = struct.unpack_from('<8I', desc, o)
                if name == 0:
                    break
                dll = self._cstr(self.base + name)
                self._walk_thunks(dll, self.base + int_, self.base + iat, delay=True)
                o += 32

    def _walk_thunks(self, dll, names_at, slots_at, delay=False):
        n = 0
        while True:
            v = struct.unpack_from('<Q', self.proc.read(names_at + 8 * n, 8))[0]
            if v == 0 or n > 4096:
                break
            if v >> 63:
                nm = '#%d' % (v & 0xffff)
            else:
                nm = self._cstr(self.base + (v & 0x7fffffff) + 2)
            self.imports[slots_at + 8 * n] = '%s!%s%s' % (dll, nm, ' (delay-load)' if delay else '')
            n += 1

    def export_name(self, ptr):
        """'dll!name' when ptr is an exported function of a loaded module, else None."""
        m = self.proc.module_of(ptr)
        if not m or m[0] == self.base:
            return None
        if m[0] not in self._exports:
            self._exports[m[0]] = pe_exports(m[2])
        nm = self._exports[m[0]].get(ptr - m[0])
        short = os.path.basename(m[2])
        return '%s!%s' % (short, nm) if nm else '%s+0x%x' % (short, ptr - m[0])

    # --- exception table (function boundaries)

    def _load_pdata(self):
        rva, sz = self.dirs[3]
        self.funcs = []     # (begin, end, unwind) as absolute addresses
        if not rva:
            return
        d = self.proc.read(self.base + rva, sz)
        n = sz // 12
        b = self.base
        self.funcs = [(b + s, b + e, b + u) for s, e, u in struct.iter_unpack('<III', d[:n * 12])]
        self.funcs.sort()
        self.func_starts = [f[0] for f in self.funcs]

    def function_at(self, addr):
        """(begin, end, primary_begin) of the function whose exception entry holds
        addr, or None (leaf functions have no entry)."""
        i = bisect.bisect_right(self.func_starts, addr) - 1
        if i < 0:
            return None
        begin, end, unwind = self.funcs[i]
        if not (begin <= addr < end):
            return None
        primary = begin
        info = self.proc.read(unwind, 4)
        flags = info[0] >> 3
        if flags & 4:   # chained: the primary function's entry follows the unwind codes
            ncodes = info[2]
            pb = struct.unpack_from('<I', self.proc.read(unwind + 4 + ((ncodes + 1) & ~1) * 2, 4))[0]
            primary = self.base + pb
        return begin, end, primary

    def function_extent(self, primary):
        """[begin, end) of a function including the chunks that directly follow it
        in the exception table and chain back to it."""
        i = bisect.bisect_left(self.func_starts, primary)
        if i >= len(self.funcs) or self.funcs[i][0] != primary:
            return None
        end = self.funcs[i][1]
        j = i + 1
        while j < len(self.funcs) and self.funcs[j][0] == end:
            info = self.proc.read(self.funcs[j][2], 4)
            if not (info[0] >> 3) & 4:
                break
            ncodes = info[2]
            pb = struct.unpack_from('<I', self.proc.read(self.funcs[j][2] + 4 + ((ncodes + 1) & ~1) * 2, 4))[0]
            if self.base + pb != primary:
                break
            end = self.funcs[j][1]
            j += 1
        return primary, end

    def find_data_pointers(self, target):
        """Addresses in the data sections holding target as an 8-byte pointer."""
        out = []
        pat = struct.pack('<Q', target)
        for secname in ('.rdata', '.data', '_RDATA'):
            sec = self.section(secname)
            if not sec:
                continue
            d = self.section_bytes(secname)
            i = d.find(pat)
            while i != -1:
                if (sec[1] + i) % 8 == 0:
                    out.append(self.base + sec[1] + i)
                i = d.find(pat, i + 1)
        return out

    def guess_function(self, addr, limit=MAX_FUNC_BYTES):
        """For an address with no exception entry: back to the previous padding or
        function end, forward to a ret/jmp followed by int3 padding."""
        i = bisect.bisect_right(self.func_starts, addr) - 1
        prev_end = self.funcs[i][1] if i >= 0 else self.text_lo
        nxt = self.funcs[i + 1][0] if i + 1 < len(self.funcs) else self.text_hi
        back = self.read(max(prev_end, addr - limit), addr - max(prev_end, addr - limit))
        j = back.rfind(b'\xcc\xcc')
        start = (max(prev_end, addr - limit) + j + 2) if j >= 0 else prev_end
        # skip remaining padding
        while self.read(start, 1) == b'\xcc' and start < addr:
            start += 1
        end = self._scan_end(start, min(nxt, start + limit))
        return start, end, start

    def _scan_end(self, start, hard_end):
        """Walk instructions from start; stop after a ret or jmp that is followed by
        int3 padding or a 16-byte boundary with no forward jump pending."""
        if not HAVE_CAPSTONE:
            return hard_end
        md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
        md.detail = True
        code = self.read(start, hard_end - start)
        furthest = start
        for insn in md.disasm(code, start):
            nxt = insn.address + insn.size
            if insn.group(capstone.CS_GRP_JUMP) and insn.operands and insn.operands[0].type == capstone.CS_OP_IMM:
                t = insn.operands[0].imm
                if start <= t < hard_end:
                    furthest = max(furthest, t)
            if insn.mnemonic in ('ret', 'retn', 'int3') or (insn.mnemonic == 'jmp' and not (insn.operands and insn.operands[0].type == capstone.CS_OP_IMM and start <= insn.operands[0].imm < hard_end)):
                if nxt > furthest:
                    after = code[nxt - start:nxt - start + 1]
                    if after == b'\xcc' or nxt % 16 == 0 or nxt >= hard_end:
                        return nxt
        return hard_end

    # --- object dump names

    def _load_dump(self, path, dump_base):
        rx = re.compile(r'\] Function (\S+) .*\[f: ([0-9A-Fa-f]+)\]')
        raw = {}
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                m = rx.search(line)
                if m:
                    raw.setdefault(int(m.group(2), 16), []).append(m.group(1))
        self.dump_file = path
        # Candidate bases: the option, "MainExe @" lines from UE4SS logs (next to the
        # dump, anywhere under dumps\, the copy's own), the live base, and finally a
        # base inferred from the exception table. Each is checked the same way: with
        # the right base, dump functions land exactly on function starts in the
        # live exception table; with a wrong one, almost none do.
        candidates = []
        if dump_base:
            candidates.append((dump_base, '--dump-base'))
        logs = [(os.path.join(os.path.dirname(os.path.abspath(path)), 'UE4SS.log'), 'the UE4SS.log next to the dump')]
        for root, dirs, files in os.walk(DUMPS_DIR):
            for fn in files:
                if fn.lower() == 'ue4ss.log':
                    logs.append((os.path.join(root, fn), 'dumps\\%s\\UE4SS.log' % os.path.basename(root)))
        logs.append((GAME_LOG, "the copy's ue4ss\\UE4SS.log"))
        seen = set()
        for logpath, why in logs:
            if os.path.exists(logpath) and logpath not in seen:
                seen.add(logpath)
                for line in open(logpath, 'r', encoding='utf-8', errors='replace'):
                    m = re.search(r'MainExe @ 0x([0-9a-fA-F]+)', line)
                    if m:
                        candidates.append((int(m.group(1), 16), why + ' (' + line.split(']')[0].strip('[') + ')'))
        candidates.append((self.base, 'the live base (no rebasing)'))
        inferred = self._infer_dump_base(raw)
        if inferred:
            candidates.append((inferred, 'inferred from the exception table'))
        starts = set(self.func_starts)
        best = None
        for cand, why in candidates:
            delta = self.base - cand
            exact = sum(1 for a in raw if a + delta in starts)
            if best is None or exact > best[2]:
                best = (cand, why, exact)
        if not best or best[2] < 0.5 * len(raw):
            raise SystemExit('could not find a base address for the dump: the best candidate puts only %d of %d '
                             'dump functions on function starts of the live exe; give --dump-base from that '
                             'run\'s UE4SS.log' % (best[2] if best else 0, len(raw)))
        self.dump_base, why, exact = best
        self.dump_delta = self.base - self.dump_base
        for a, names in raw.items():
            self.names[a + self.dump_delta] = names
        self.say('object dump: %s (%d functions at %d addresses), base 0x%x from %s;'
                 ' live base 0x%x, delta %s0x%x; check: %d of %d dump functions start exactly on a function in the'
                 ' live exception table' % (os.path.relpath(path, PROJECT) if path.startswith(PROJECT) else path,
                                            sum(len(v) for v in raw.values()), len(raw), self.dump_base, why,
                                            self.base, '-' if self.dump_delta < 0 else '+', abs(self.dump_delta),
                                            exact, len(raw)))

    def _infer_dump_base(self, raw):
        """Base the dump was written with, found by voting: for a sample of dump
        functions, every live function start that is a whole number of 64 KB away
        (Windows moves images in 64 KB steps) votes for one base; the right base
        wins by a wide margin."""
        from collections import Counter
        sample = sorted(raw)[::max(1, len(raw) // 24)][:24]
        votes = Counter()
        for a in sample:
            for b in self.func_starts:
                d = b - a
                if d % 0x10000 == 0:
                    votes[self.base - d] += 1
        if not votes:
            return None
        base, n = votes.most_common(1)[0]
        return base if n >= len(sample) // 2 else None

    @staticmethod
    def short_name(full):
        return full.rsplit('/', 1)[-1]

    def dump_lookup(self, name):
        """Addresses of dump functions matching a name (full, short, or Class:Func)."""
        n = name.lower()
        hits = []
        for addr, names in self.names.items():
            for full in names:
                s = self.short_name(full).lower()
                if n in (full.lower(), s, s.split('.', 1)[-1]):
                    hits.append((addr, full))
        return hits

    # --- class names from RTTI (type descriptors in .data, locators and vtables in .rdata)

    @staticmethod
    def demangle_class(mangled):
        # '.?AVP2PSessionSteam@SNL@@' -> 'SNL::P2PSessionSteam'
        m = mangled[4:]
        if m.startswith('?$'):
            return m.rstrip('@')
        parts = m.split('@@')[0].split('@')
        return '::'.join(reversed([p for p in parts if p]))

    def _scan_rtti(self):
        t0 = time.time()
        rdata = self.section('.rdata')
        data = self.section('.data')
        if not rdata or not data:
            return
        rd = self.section_bytes('.rdata')
        dd = self.section_bytes('.data')
        tds = {}
        for m in re.finditer(rb'\.\?A[VU][^\0]{1,300}\0', dd):
            tds[data[1] + m.start() - 16] = self.demangle_class(m.group()[:-1].decode('latin1'))
        rd_rva = rdata[1]
        mv = memoryview(rd[:len(rd) - len(rd) % 4]).cast('I')
        cols = {}
        for i, v in enumerate(mv):
            if v == rd_rva + 4 * i - 20:
                col = 4 * i - 20
                if col >= 0 and mv[col // 4] == 1:
                    td = mv[col // 4 + 3]
                    if td in tds:
                        cols[self.base + rd_rva + col] = (tds[td], mv[col // 4 + 1])
        mv8 = memoryview(rd[:len(rd) - len(rd) % 8]).cast('Q')
        lo, hi = self.text_lo, self.text_hi
        vt_count = 0
        self.vtables = {}        # label -> (vtable address, [function addresses])
        for i, v in enumerate(mv8):
            if v in cols:
                cls, off = cols[v]
                label = cls if off == 0 else '%s@+0x%x' % (cls, off)
                vt_count += 1
                j = i + 1
                slot = 0
                funcs = []
                while j < len(mv8) and lo <= mv8[j] < hi:
                    f = mv8[j]
                    funcs.append(f)
                    if f not in self.vtable_names:
                        self.vtable_names[f] = '%s::vtbl[%d]' % (label, slot)
                    j += 1
                    slot += 1
                self.vtables.setdefault(label, (self.base + rd_rva + 8 * (i + 1), funcs))
        self.classes = len(cols)
        self.say('class data: %d type names, %d vtables, %d functions named by class and slot (%.1f s)'
                 % (len(tds), vt_count, len(self.vtable_names), time.time() - t0))

    # --- naming

    def sorted_names(self):
        if self._sorted_names is None:
            allnames = {}
            for a, ns in self.names.items():
                allnames[a] = self.short_name(ns[0]) + ('' if len(ns) == 1 else ' (+%d more names)' % (len(ns) - 1))
            for a, n in self.vtable_names.items():
                allnames.setdefault(a, n)
            self._sorted_names = sorted(allnames.items())
            self._sorted_addrs = [a for a, _ in self._sorted_names]
        return self._sorted_names

    def nearest_name(self, addr):
        """(name, distance) of the closest named function at or before addr."""
        names = self.sorted_names()
        i = bisect.bisect_right(self._sorted_addrs, addr) - 1
        if i < 0:
            return None, None
        a, n = names[i]
        return n, addr - a

    def name_exact(self, addr):
        if addr in self.names:
            ns = self.names[addr]
            return self.short_name(ns[0]) + ('' if len(ns) == 1 else ' (+%d more names)' % (len(ns) - 1))
        if addr in self.vtable_names:
            return self.vtable_names[addr]
        return None

    def describe_code(self, addr):
        """Name a code address: exact name, else its function and the nearest name."""
        exact = self.name_exact(addr)
        if exact:
            return '%s = %s' % (self.fmt(addr), exact)
        f = self.function_at(addr)
        if f:
            begin, end, primary = f
            fn_exact = self.name_exact(primary)
            if fn_exact:
                return '%s = %s+0x%x' % (self.fmt(addr), fn_exact, addr - primary)
            n, dist = self.nearest_name(primary)
            near = ' (nearest name %s +0x%x)' % (n, dist) if n and dist < 0x100000 else ''
            if addr == begin:
                return '%s = function %s..%s%s' % (self.fmt(addr), self.fmt(begin), self.fmt(end), near)
            return '%s = function %s + 0x%x%s' % (self.fmt(addr), self.fmt(begin), addr - begin, near)
        n, dist = self.nearest_name(addr)
        near = ' (nearest name %s +0x%x)' % (n, dist) if n and dist < 0x100000 else ''
        return '%s (no exception entry)%s' % (self.fmt(addr), near)

    def string_at(self, addr, maxlen=120):
        """The printable string at addr (ASCII or UTF-16), or None."""
        b = self.read(addr, 2 * maxlen + 2)
        if len(b) < 2:
            return None
        if b[0] >= 0x20 and b[0] < 0x7f and b[1] == 0 and len(b) > 3 and 0x20 <= b[2] < 0x7f and b[3] == 0:
            u = b[:len(b) - len(b) % 2].decode('utf-16-le', 'replace')
            s = u.split('\0', 1)[0]
            if len(s) >= 2 and all(0x20 <= ord(c) < 0x7f for c in s):
                return 'L"%s"' % s
        s = b.split(b'\0', 1)[0]
        if len(s) >= 3 and all(0x20 <= c < 0x7f for c in s):
            return '"%s"' % s.decode('latin1')
        return None

    def describe_data(self, addr):
        if addr in self.imports:
            return 'import %s' % self.imports[addr]
        if self.in_text(addr):
            return self.describe_code(addr)
        sec = self.section_of(addr)
        s = self.string_at(addr)
        if s:
            return '%s %s' % (self.fmt(addr), s)
        if sec and sec[0] in ('.rdata', '.data', '_RDATA'):
            v = struct.unpack_from('<Q', self.read(addr, 8))[0] if addr + 8 <= self.base + self.size else 0
            exp = self.export_name(v) if v else None
            if exp:
                return '%s -> %s' % (self.fmt(addr), exp)
            if self.in_text(v):
                return '%s -> %s' % (self.fmt(addr), self.describe_code(v))
            if v in self.imports:
                return '%s -> slot of %s' % (self.fmt(addr), self.imports[v])
            s2 = self.string_at(v) if self.base <= v < self.base + self.size else None
            if s2:
                return '%s -> %s' % (self.fmt(addr), s2)
            return '%s (%s, holds 0x%x)' % (self.fmt(addr), sec[0], v)
        if sec:
            return '%s (%s)' % (self.fmt(addr), sec[0])
        return self.fmt(addr)

    # --- strings in data

    def find_strings(self, text, exact=False):
        """[(addr, kind, string)] for every ASCII or UTF-16 string in the data
        sections containing text (exact=True: the whole string equals text)."""
        out = []
        for secname in ('.rdata', '.data', '_RDATA'):
            sec = self.section(secname)
            if not sec:
                continue
            d = self.section_bytes(secname)
            base = self.base + sec[1]
            pat = re.escape(text.encode('latin1'))
            if exact:
                for m in re.finditer(rb'(?<![\x20-\x7e])' + pat + rb'\0', d):
                    out.append((base + m.start(), 'ascii', text))
                pat16 = re.escape(text.encode('utf-16-le'))
                for m in re.finditer(rb'(?<![\x20-\x7e])' + pat16 + rb'\0\0', d):
                    if m.start() % 2 == 0:
                        out.append((base + m.start(), 'utf16', text))
            else:
                for m in re.finditer(rb'[\x20-\x7e]*' + pat + rb'[\x20-\x7e]*', d):
                    out.append((base + m.start(), 'ascii', m.group().decode('latin1')))
                pat16 = re.escape(text.encode('utf-16-le'))
                for m in re.finditer(rb'(?:[\x20-\x7e]\0)*' + pat16 + rb'(?:[\x20-\x7e]\0)*', d):
                    if m.start() % 2 == 0:
                        out.append((base + m.start(), 'utf16', m.group().decode('utf-16-le')))
        return out

    # --- references from code to an address (x86-64 RIP-relative displacements)

    def find_refs(self, target):
        """Instruction addresses in .text whose RIP-relative displacement points at
        target. Candidates are found with a fast byte search, then checked by
        disassembling the containing function; unverified ones are flagged."""
        text = self.text_bytes()
        L = len(text)
        hits = {}
        for k in (0, 1, 4):   # bytes of immediate that may follow the displacement
            tprime = target - self.text_lo - 4 - k
            p = 0
            while p <= L - 4:
                u = (tprime - p) & 0xffffffff
                run = u & 0xffff          # positions p..p+run share the same high half
                stop = min(p + run, L - 4)
                pat = struct.pack('<H', u >> 16)
                i = text.find(pat, p + 2, stop + 4)
                while i != -1:
                    q = i - 2
                    if q <= stop and text[q:q + 4] == struct.pack('<I', (tprime - q) & 0xffffffff):
                        hits[q] = k
                    i = text.find(pat, i + 1, stop + 4)
                p = stop + 1
        refs = []
        for q, k in sorted(hits.items()):
            end = self.text_lo + q + 4 + k
            insn = self._verify_ref(q, end, target)
            if insn is not None:
                refs.append((insn.address, insn, True))
            else:
                refs.append((self.text_lo + q, None, False))
        return refs

    def _verify_ref(self, q, end, target):
        if not HAVE_CAPSTONE:
            return None
        md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
        md.detail = True
        f = self.function_at(self.text_lo + q)
        if f:
            begin = f[0]
            code = self.read(begin, min(f[1], end + 16) - begin)
            for insn in md.disasm(code, begin):
                if insn.address + insn.size == end and self._rip_target(insn) == target:
                    return insn
                if insn.address >= end:
                    break
            return None
        # no exception entry: try every plausible start before the displacement
        for s in range(q - 8, q + 1):
            if s < 0:
                continue
            code = self.read(self.text_lo + s, end - (self.text_lo + s))
            for insn in md.disasm(code, self.text_lo + s, 1):
                if insn.address + insn.size == end and self._rip_target(insn) == target:
                    return insn
        return None

    @staticmethod
    def _rip_target(insn):
        for op in insn.operands:
            if op.type == capstone.CS_OP_MEM and op.mem.base == capstone.x86.X86_REG_RIP:
                return insn.address + insn.size + op.mem.disp
        return None


# ----------------------------------------------------------------------------- Steam interfaces

# The game talks to Steam through the Steamworks SDK's C++ interfaces: it calls
# steam_api64!SteamInternal_ContextInit, which returns a table of interface pointers
# (CSteamAPIContext, SDK 1.39 layout: the crash of 17 Oct read slot +0x40, Networking),
# takes one slot, and calls a method through that interface's vtable. The slot names
# below are the SDK's declaration order; method names are given for the interfaces the
# online layer uses most and are best effort from the SDK headers (1.39).
STEAM_CTX = {0x00: 'ISteamClient', 0x08: 'ISteamUser', 0x10: 'ISteamFriends', 0x18: 'ISteamUtils',
             0x20: 'ISteamMatchmaking', 0x28: 'ISteamUserStats', 0x30: 'ISteamApps',
             0x38: 'ISteamMatchmakingServers', 0x40: 'ISteamNetworking', 0x48: 'ISteamRemoteStorage',
             0x50: 'ISteamScreenshots', 0x58: 'ISteamHTTP', 0x60: 'ISteamController', 0x68: 'ISteamUGC',
             0x70: 'ISteamAppList', 0x78: 'ISteamMusic', 0x80: 'ISteamMusicRemote', 0x88: 'ISteamHTMLSurface',
             0x90: 'ISteamInventory', 0x98: 'ISteamVideo', 0xa0: 'ISteamParentalSettings'}
STEAM_METHODS = {
    'ISteamNetworking': ['SendP2PPacket', 'IsP2PPacketAvailable', 'ReadP2PPacket', 'AcceptP2PSessionWithUser',
                         'CloseP2PSessionWithUser', 'CloseP2PChannelWithUser', 'GetP2PSessionState',
                         'AllowP2PPacketRelay', 'CreateListenSocket', 'CreateP2PConnectionSocket',
                         'CreateConnectionSocket', 'DestroySocket', 'DestroyListenSocket', 'SendDataOnSocket',
                         'IsDataAvailableOnSocket', 'RetrieveDataFromSocket', 'IsDataAvailable', 'RetrieveData',
                         'GetSocketInfo', 'GetListenSocketInfo', 'GetSocketConnectionType', 'GetMaxPacketSize'],
    'ISteamMatchmaking': ['GetFavoriteGameCount', 'GetFavoriteGame', 'AddFavoriteGame', 'RemoveFavoriteGame',
                          'RequestLobbyList', 'AddRequestLobbyListStringFilter', 'AddRequestLobbyListNumericalFilter',
                          'AddRequestLobbyListNearValueFilter', 'AddRequestLobbyListFilterSlotsAvailable',
                          'AddRequestLobbyListDistanceFilter', 'AddRequestLobbyListResultCountFilter',
                          'AddRequestLobbyListCompatibleMembersFilter', 'GetLobbyByIndex', 'CreateLobby', 'JoinLobby',
                          'LeaveLobby', 'InviteUserToLobby', 'GetNumLobbyMembers', 'GetLobbyMemberByIndex',
                          'GetLobbyData', 'SetLobbyData', 'GetLobbyDataCount', 'GetLobbyDataByIndex', 'DeleteLobbyData',
                          'GetLobbyMemberData', 'SetLobbyMemberData', 'SendLobbyChatMsg', 'GetLobbyChatEntry',
                          'RequestLobbyData', 'SetLobbyGameServer', 'GetLobbyGameServer', 'SetLobbyMemberLimit',
                          'GetLobbyMemberLimit', 'SetLobbyType', 'SetLobbyJoinable', 'GetLobbyOwner', 'SetLobbyOwner',
                          'SetLinkedLobby'],
    'ISteamUser': ['GetHSteamUser', 'BLoggedOn', 'GetSteamID', 'InitiateGameConnection', 'TerminateGameConnection',
                   'TrackAppUsageEvent', 'GetUserDataFolder', 'StartVoiceRecording', 'StopVoiceRecording',
                   'GetAvailableVoice', 'GetVoice', 'DecompressVoice', 'GetVoiceOptimalSampleRate', 'GetAuthSessionTicket',
                   'BeginAuthSession', 'EndAuthSession', 'CancelAuthTicket', 'UserHasLicenseForApp', 'BIsBehindNAT',
                   'AdvertiseGame', 'RequestEncryptedAppTicket', 'GetEncryptedAppTicket', 'GetGameBadgeLevel',
                   'GetPlayerSteamLevel', 'RequestStoreAuthURL', 'BIsPhoneVerified', 'BIsTwoFactorEnabled',
                   'BIsPhoneIdentifying', 'BIsPhoneRequiringVerification'],
    'ISteamUtils': ['GetSecondsSinceAppActive', 'GetSecondsSinceComputerActive', 'GetConnectedUniverse',
                    'GetServerRealTime', 'GetIPCountry', 'GetImageSize', 'GetImageRGBA', 'GetCSERIPPort',
                    'GetCurrentBatteryPower', 'GetAppID', 'SetOverlayNotificationPosition', 'IsAPICallCompleted',
                    'GetAPICallFailureReason', 'GetAPICallResult', 'RunFrame', 'GetIPCCallCount', 'SetWarningMessageHook',
                    'IsOverlayEnabled', 'BOverlayNeedsPresent', 'CheckFileSignature', 'ShowGamepadTextInput',
                    'GetEnteredGamepadTextLength', 'GetEnteredGamepadTextInput', 'GetSteamUILanguage',
                    'IsSteamRunningInVR', 'SetOverlayNotificationInset', 'IsSteamInBigPictureMode', 'StartVRDashboard'],
    'ISteamFriends': ['GetPersonaName', 'SetPersonaName', 'GetPersonaState', 'GetFriendCount', 'GetFriendByIndex',
                      'GetFriendRelationship', 'GetFriendPersonaState', 'GetFriendPersonaName', 'GetFriendGamePlayed',
                      'GetFriendPersonaNameHistory', 'GetFriendSteamLevel', 'GetPlayerNickname', 'GetFriendsGroupCount',
                      'GetFriendsGroupIDByIndex', 'GetFriendsGroupName', 'GetFriendsGroupMembersCount',
                      'GetFriendsGroupMembersList', 'HasFriend', 'GetClanCount', 'GetClanByIndex', 'GetClanName',
                      'GetClanTag', 'GetClanActivityCounts', 'DownloadClanActivityCounts', 'GetFriendCountFromSource',
                      'GetFriendFromSourceByIndex', 'IsUserInSource', 'SetInGameVoiceSpeaking', 'ActivateGameOverlay',
                      'ActivateGameOverlayToUser', 'ActivateGameOverlayToWebPage', 'ActivateGameOverlayToStore',
                      'SetPlayedWith', 'ActivateGameOverlayInviteDialog', 'GetSmallFriendAvatar', 'GetMediumFriendAvatar',
                      'GetLargeFriendAvatar', 'RequestUserInformation', 'RequestClanOfficerList', 'GetClanOwner',
                      'GetClanOfficerCount', 'GetClanOfficerByIndex', 'GetUserRestrictions', 'SetRichPresence',
                      'ClearRichPresence', 'GetFriendRichPresence', 'GetFriendRichPresenceKeyCount',
                      'GetFriendRichPresenceKeyByIndex', 'RequestFriendRichPresence', 'InviteUserToGame',
                      'GetCoplayFriendCount', 'GetCoplayFriend', 'GetFriendCoplayTime', 'GetFriendCoplayGame',
                      'JoinClanChatRoom', 'LeaveClanChatRoom', 'GetClanChatMemberCount', 'GetChatMemberByIndex',
                      'SendClanChatMessage', 'GetClanChatMessage', 'IsClanChatAdmin', 'IsClanChatWindowOpenInSteam',
                      'OpenClanChatWindowInSteam', 'CloseClanChatWindowInSteam', 'SetListenForFriendsMessages',
                      'ReplyToFriendMessage', 'GetFriendMessage', 'GetFollowerCount', 'IsFollowing', 'EnumerateFollowingList',
                      'IsClanPublic', 'IsClanOfficialGameGroup'],
}
VOLATILE = {'rax', 'rcx', 'rdx', 'r8', 'r9', 'r10', 'r11', 'eax', 'ecx', 'edx', 'r8d', 'r9d', 'r10d', 'r11d'}


def steam_method(iface, slot):
    names = STEAM_METHODS.get(iface, [])
    return '%s::%s' % (iface, names[slot] if slot < len(names) else 'slot%d' % slot)


# ----------------------------------------------------------------------------- disassembly listing

def listing(exe, start, code, func=None, mark=None):
    """Lines of disassembly with names for call/jump targets, imports, strings, and
    Steam interface calls (tracked from SteamInternal_ContextInit through the
    registers that hold the context, the interface and its vtable)."""
    lines = []
    if not HAVE_CAPSTONE:
        lines.append('(capstone is not installed: showing hex only; python -m pip install capstone)')
        for o in range(0, len(code), 16):
            lines.append('%-18s %s' % (exe.fmt(start + o), code[o:o + 16].hex(' ')))
        return lines
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True
    lo, hi = (func[0], func[1]) if func else (start, start + len(code))
    regs = {}            # register name -> ('ctx',) | ('iface', name) | ('vtbl', name)
    ctx_global = getattr(exe, 'steam_ctx_global', None)
    last_lea_rcx = None
    for insn in md.disasm(code, start):
        note = ''
        tgt = None
        ops = insn.operands
        rip = LiveExe._rip_target(insn)
        is_call = insn.group(capstone.CS_GRP_CALL)
        is_jump = insn.group(capstone.CS_GRP_JUMP)
        # --- Steam interface tracking (before the register state is updated)
        steam = None
        if (is_call or is_jump) and ops and ops[0].type == capstone.CS_OP_MEM and ops[0].mem.base:
            b = insn.reg_name(ops[0].mem.base)
            if regs.get(b, ('',))[0] == 'vtbl':
                steam = steam_method(regs[b][1], ops[0].mem.disp // 8)
        if ops and ops[0].type == capstone.CS_OP_IMM and (is_call or is_jump):
            tgt = ops[0].imm
            if lo <= tgt < hi and is_jump:
                note = '-> +0x%x (inside)' % (tgt - lo)
            else:
                note = '-> ' + exe.describe_code(tgt)
        elif rip is not None:
            if is_call or is_jump:
                d = exe.describe_data(rip)
                note = '-> ' + d
                if rip in exe.imports:
                    v = struct.unpack_from('<Q', exe.read(rip, 8))[0]
                    en = exe.export_name(v)
                    if en and en.split('!')[-1] not in d:
                        note += ' (now %s)' % en
            else:
                note = '; ' + exe.describe_data(rip)
                if ctx_global is not None and 0 <= rip - ctx_global <= 0xa0 and (rip - ctx_global) in STEAM_CTX \
                        and insn.mnemonic == 'mov' and ops[0].type == capstone.CS_OP_REG:
                    note = '; Steam context slot +0x%x = %s' % (rip - ctx_global, STEAM_CTX[rip - ctx_global])
        elif steam:
            note = '-> Steam %s' % steam
        # --- update the register state
        if insn.mnemonic == 'lea' and ops[0].type == capstone.CS_OP_REG and insn.reg_name(ops[0].reg) == 'rcx' and rip is not None:
            last_lea_rcx = rip
        written = set()
        try:
            _, wr = insn.regs_access()
            written = {insn.reg_name(r) for r in wr}
        except Exception:
            pass
        if is_call:
            for r in list(regs):
                if r in VOLATILE:
                    del regs[r]
        new = None
        if insn.mnemonic == 'mov' and len(ops) == 2 and ops[0].type == capstone.CS_OP_REG:
            dst = insn.reg_name(ops[0].reg)
            if ops[1].type == capstone.CS_OP_REG:
                src = insn.reg_name(ops[1].reg)
                if src in regs:
                    new = (dst, regs[src])
            elif ops[1].type == capstone.CS_OP_MEM and ops[1].mem.base:
                b = insn.reg_name(ops[1].mem.base)
                disp = ops[1].mem.disp
                if b == 'rip' and ctx_global is not None and (rip - ctx_global) in STEAM_CTX:
                    new = (dst, ('iface', STEAM_CTX[rip - ctx_global]))
                elif b in regs:
                    kind = regs[b]
                    if kind[0] == 'ctx' and disp in STEAM_CTX and not ops[1].mem.index:
                        new = (dst, ('iface', STEAM_CTX[disp]))
                        note = (note + '  ' if note else '') + '; Steam context slot +0x%x = %s' % (disp, STEAM_CTX[disp])
                    elif kind[0] == 'iface' and disp == 0 and not ops[1].mem.index:
                        new = (dst, ('vtbl', kind[1]))
        for r in written:
            regs.pop(r, None)
            # a 32-bit write clears the 64-bit register too
            regs.pop({'eax': 'rax', 'ecx': 'rcx', 'edx': 'rdx', 'ebx': 'rbx', 'esi': 'rsi', 'edi': 'rdi',
                      'ebp': 'rbp', 'r8d': 'r8', 'r9d': 'r9', 'r10d': 'r10', 'r11d': 'r11', 'r12d': 'r12',
                      'r13d': 'r13', 'r14d': 'r14', 'r15d': 'r15'}.get(r, r), None)
        if new:
            regs[new[0]] = new[1]
        if is_call and rip is not None and 'SteamInternal_ContextInit' in exe.imports.get(rip, ''):
            regs = {k: v for k, v in regs.items() if k not in VOLATILE}
            regs['rax'] = ('ctx',)
            if last_lea_rcx is not None and ctx_global is None:
                ctx_global = last_lea_rcx + 0x10
                exe.steam_ctx_global = ctx_global
            note += '  ; returns the Steam interface table'
        if is_call and ops and ops[0].type == capstone.CS_OP_IMM:
            regs = {k: v for k, v in regs.items() if k not in VOLATILE}
        flag = '>>' if mark is not None and insn.address <= mark < insn.address + insn.size else '  '
        lines.append('%s %-16s %-24s %-7s %-30s %s' % (flag, exe.fmt(insn.address), insn.bytes.hex(' '),
                                                      insn.mnemonic, insn.op_str, note))
    return lines


# ----------------------------------------------------------------------------- commands

def parse_target(exe, s):
    """exe+0xOFF, 0xADDR, or a dump function name -> (addr, label)."""
    t = s.strip()
    m = re.fullmatch(r'(?i)exe\s*\+\s*(0x)?([0-9a-f]+)', t)
    if m:
        return exe.base + int(m.group(2), 16), None
    m = re.fullmatch(r'(?i)(0x)?([0-9a-f]{9,16})', t)
    if m:
        return int(m.group(2), 16), None
    # an import, "steam_api64.dll!SteamAPI_Init" or just "SteamAPI_Init": its slot
    imp = [(slot, nm) for slot, nm in exe.imports.items()
           if nm.split(' ')[0].lower() == t.lower() or nm.split(' ')[0].split('!')[-1].lower() == t.lower()]
    if len(imp) == 1:
        return imp[0][0], None
    if len(imp) > 1:
        raise SystemExit('"%s" matches several imports: %s' % (s, ', '.join(nm for _, nm in imp)))
    hits = exe.dump_lookup(t)
    if not hits:
        raise SystemExit('"%s" is neither exe+offset, an address, nor a function in the object dump' % s)
    addrs = sorted(set(a for a, _ in hits))
    if len(addrs) > 1:
        print('"%s" matches %d different functions:' % (s, len(addrs)))
        for a, full in hits:
            print('   %s  %s' % (exe.fmt(a), full))
        raise SystemExit('give the full name or the address')
    return addrs[0], hits[0][1]


def safe_name(s):
    return re.sub(r'[^A-Za-z0-9_.+-]+', '_', s).strip('_')[:120]


def cmd_info(exe, args):
    p = exe.proc
    print('process %d, started %s: %s' % (p.pid, p.started(), exe.path))
    print('live base 0x%x, size 0x%x, entry exe+0x%x, %d modules loaded' % (exe.base, exe.size, exe.entry_rva, len(p.modules)))
    print('sections:')
    for name, va, vsz, rsz, flags in exe.sections:
        print('   %-8s exe+0x%08x .. exe+0x%08x  (%.1f MB)%s' % (name, va, va + vsz, vsz / 1048576,
                                                                 '  code' if flags & 0x20 else ''))
    # unpacked? the Steam wrapper leaves the code scrambled on disk; compare 4 KB at the entry of a known function
    probe = exe.text_lo + 0x1000
    live = exe.read(probe, 4096)
    try:
        with open(exe.path, 'rb') as f:
            raw = next(s for s in exe.sections if s[0] == '.text')
            # raw file offset of .text is in the header; read it again from disk
            d = f.read(0x1000)
            pe = struct.unpack_from('<I', d, 0x3c)[0]
            nsec = struct.unpack_from('<H', d, pe + 6)[0]
            optsz = struct.unpack_from('<H', d, pe + 20)[0]
            for i in range(nsec):
                s = pe + 24 + optsz + 40 * i
                if d[s:s + 8].rstrip(b'\0') == b'.text':
                    rp = struct.unpack_from('<I', d, s + 20)[0]
                    f.seek(rp + 0x1000)
                    disk = f.read(4096)
                    same = sum(1 for a, b in zip(live, disk) if a == b)
                    print('code in memory vs on disk (4 KB sample): %d of 4096 bytes equal -> %s'
                          % (same, 'UNPACKED, readable' if same < 1024 else 'same as the scrambled disk copy?!'))
    except OSError as e:
        print('could not compare with the disk copy:', e)
    cc = sum(1 for v in exe.imports.values() if '(delay-load)' not in v)
    dl = len(exe.imports) - cc
    print('imports: %d static, %d delay-load slots named; exception table: %d functions' % (cc, dl, len(exe.funcs)))
    if exe.dump_file:
        print('object dump: %s, %d named addresses, dump base 0x%x -> live base 0x%x' % (exe.dump_file, len(exe.names), exe.dump_base, exe.base))
    if exe.vtable_names:
        print('class data: %d vtable functions named from %d class locators' % (len(exe.vtable_names), exe.classes))
    print('Nothing was written into the game. The process was opened with read rights only.')


def cmd_name(exe, args):
    for t in args.targets:
        addr, label = parse_target(exe, t)
        print(exe.describe_code(addr) if exe.in_text(addr) else exe.describe_data(addr))


def cmd_peek(exe, args):
    """peek ADDR [N]: N bytes (default 64, at most 4096) of the game's memory at ADDR, as hex,
    with each 8-byte word also read as a pointer and named when it points into the exe.
    For looking at one live object (an address from the pilot's eval, UObject:GetAddress())."""
    addr = parse_target(exe, args.targets[0])[0]
    n = min(int(args.targets[1], 0) if len(args.targets) > 1 else 64, 4096)
    data = exe.proc.read(addr, n)
    for off in range(0, len(data), 16):
        row = data[off:off + 16]
        words = [struct.unpack_from('<Q', row, i)[0] for i in range(0, len(row) - 7, 8)]
        named = []
        for w in words:
            if exe.base <= w < exe.base + exe.size:
                named.append('exe+0x%x' % (w - exe.base))
        print('  +0x%03x  %-48s %s' % (off, ' '.join('%02x' % b for b in row), '  '.join(named)))


def cmd_vtslot(exe, args):
    """vtslot OBJADDR OFFSET...: the function in the object's virtual function table at each
    byte offset (as a 'call qword ptr [rax + OFFSET]' names it), with its name if known."""
    obj = parse_target(exe, args.targets[0])[0]
    vt = struct.unpack('<Q', exe.proc.read(obj, 8))[0]
    print('object 0x%x: vtable at %s' % (obj, ('exe+0x%x' % (vt - exe.base)) if exe.base <= vt < exe.base + exe.size else hex(vt)))
    for t in args.targets[1:]:
        off = int(t, 0)
        fn = struct.unpack('<Q', exe.proc.read(vt + off, 8))[0]
        print('  [+0x%x] -> %s' % (off, exe.describe_code(fn) if exe.in_text(fn) else hex(fn)))


def cmd_read(exe, args):
    for t in args.targets:
        addr, label = parse_target(exe, t)
        if not exe.in_text(addr):
            print('%s is not in the code section (%s); use "name" or "refs" for data' % (t, exe.describe_data(addr)))
            continue
        guessed = False
        if args.size:
            if args.size > MAX_SIZE_OPTION:
                raise SystemExit('--size is capped at %d bytes: single functions only, never sections' % MAX_SIZE_OPTION)
            start, end, primary = addr, addr + args.size, addr
            func = None
        else:
            f = exe.function_at(addr)
            if f:
                start, end, primary = f
                ext = exe.function_extent(primary)
                if ext:
                    start, end = ext
                func = (start, end, primary)
            else:
                start, end, primary = exe.guess_function(addr)
                func = (start, end, primary)
                guessed = True
            if end - start > MAX_FUNC_BYTES:
                print('function %s..%s is %d bytes; reading the first %d (--size for more, up to %d)'
                      % (exe.fmt(start), exe.fmt(end), end - start, MAX_FUNC_BYTES, MAX_SIZE_OPTION))
                end = start + MAX_FUNC_BYTES
        code = exe.read(start, end - start)
        name = exe.name_exact(primary)
        fname = safe_name(LiveExe.short_name(label)) if label else (safe_name(name.split(' ')[0]) if name else 'exe+0x%x' % (start - exe.base))
        head = ['function %s .. %s (%d bytes)%s' % (exe.fmt(start), exe.fmt(end), end - start,
                                                     ', boundaries GUESSED (no exception-table entry)' if guessed else '')]
        if primary != start:
            head.append('   this is a chunk of the function starting at %s' % exe.fmt(primary))
        if name:
            head.append('   name: %s' % name)
        n, dist = exe.nearest_name(primary)
        if n and not name:
            head.append('   nearest known name: %s, 0x%x bytes before' % (n, dist))
        if addr != start:
            head.append('   requested address %s is +0x%x into it (marked >>)' % (exe.fmt(addr), addr - start))
        head.append('   live base 0x%x; offsets are from the exe base' % exe.base)
        body = listing(exe, start, code, func, mark=addr if addr != start else None)
        text = '\n'.join(head + body)
        print(text)
        if not args.no_save:
            os.makedirs(CODE_DIR, exist_ok=True)
            binp = os.path.join(CODE_DIR, fname + '.bin')
            with open(binp, 'wb') as f:
                f.write(code)
            with open(os.path.join(CODE_DIR, fname + '.txt'), 'w', encoding='utf-8') as f:
                f.write('# read-game-code.py, %s, process %d, %s\n' % (time.strftime('%Y-%m-%d %H:%M:%S'), exe.proc.pid, exe.path))
                f.write(text + '\n')
            print('saved %d bytes to %s and the listing to %s' % (len(code), os.path.relpath(binp, PROJECT),
                                                                  os.path.relpath(binp[:-4] + '.txt', PROJECT)))
        print()


def cmd_class(exe, args):
    """List a class's vtable: every virtual function with its address and names."""
    for t in args.targets:
        hits = [k for k in getattr(exe, 'vtables', {}) if t.lower() in k.lower()]
        if not hits:
            print('no class vtable matches "%s" (class names come from the RTTI data; try "strings .?AV%s")' % (t, t))
            continue
        for label in sorted(hits):
            vt, funcs = exe.vtables[label]
            print('%s: vtable at %s, %d virtual functions' % (label, exe.fmt(vt), len(funcs)))
            for slot, f in enumerate(funcs):
                ext = exe.function_extent(f)
                size = ' (%d bytes)' % (ext[1] - f) if ext else ''
                other = exe.name_exact(f)
                mine = '%s::vtbl[%d]' % (label, slot)
                alias = '' if not other or other == mine else '  = ' + other
                print('   [%2d] %-18s%s%s' % (slot, exe.fmt(f), size, alias))
            print()


def cmd_strings(exe, args):
    for t in args.targets:
        hits = exe.find_strings(t)
        print('%d strings containing "%s":' % (len(hits), t))
        for addr, kind, s in hits:
            print('   %-18s %-6s %s' % (exe.fmt(addr), kind, s if len(s) < 100 else s[:97] + '...'))


def cmd_refs(exe, args):
    for t in args.targets:
        targets = []
        try:
            addr, label = parse_target(exe, t)
            targets.append((addr, 'address %s' % exe.fmt(addr)))
        except SystemExit:
            hits = exe.find_strings(t, exact=True)
            if not hits:
                hits = exe.find_strings(t)
                if hits:
                    print('"%s" is not a whole string in the game\'s data; using the %d strings containing it' % (t, len(hits)))
            if not hits:
                print('"%s": not an address and not found in the game\'s data' % t)
                continue
            for addr, kind, s in hits:
                targets.append((addr, '%s %s at %s' % (kind, ('L"%s"' if kind == 'utf16' else '"%s"') % s, exe.fmt(addr))))
        for addr, what in targets:
            t0 = time.time()
            refs = exe.find_refs(addr)
            print('%s: %d reference%s in the code (%.1f s)' % (what, len(refs), '' if len(refs) == 1 else 's', time.time() - t0))
            print_refs(exe, refs, '   ')
            ptrs = exe.find_data_pointers(addr)
            if ptrs:
                print('   also held as a pointer in the data at %d place%s:' % (len(ptrs), '' if len(ptrs) == 1 else 's'))
                for p in ptrs[:12]:
                    prefs = exe.find_refs(p)
                    print('   %s (%s): %d code reference%s' % (exe.fmt(p), exe.section_of(p)[0], len(prefs), '' if len(prefs) == 1 else 's'))
                    print_refs(exe, prefs, '      ')
            print()


def print_refs(exe, refs, indent):
    byfunc = {}
    for at, insn, ok in refs:
        f = exe.function_at(at)
        key = f[2] if f else None
        byfunc.setdefault(key, []).append((at, insn, ok, f))
    for key in sorted(byfunc, key=lambda k: (k is None, k or 0)):
        items = byfunc[key]
        if key is None:
            print(indent + '(no exception-table entry for these, leaf code or data?)')
        else:
            f = items[0][3]
            name = exe.name_exact(key)
            n, dist = exe.nearest_name(key)
            tag = ('= ' + name) if name else ('nearest name %s +0x%x' % (n, dist) if n else '')
            ext = exe.function_extent(key)
            print(indent + 'function %s .. %s  %s' % (exe.fmt(key), exe.fmt(ext[1] if ext else f[1]), tag))
        for at, insn, ok, f in items:
            if insn is not None:
                print(indent + '   %-16s %-7s %s' % (exe.fmt(at), insn.mnemonic, insn.op_str))
            else:
                print(indent + '   %-16s (displacement matches; instruction not verified)' % exe.fmt(at))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('command', choices=['info', 'read', 'refs', 'strings', 'name', 'class', 'peek', 'vtslot'])
    ap.add_argument('targets', nargs='*')
    ap.add_argument('--dump', help='UE4SS object dump (default: newest under dumps\\)')
    ap.add_argument('--dump-base', help='exe base when the dump was written (hex)')
    ap.add_argument('--no-dump', action='store_true', help='do not load an object dump')
    ap.add_argument('--pid', type=int)
    ap.add_argument('--size', type=int, help='read exactly this many bytes (read only)')
    ap.add_argument('--no-save', action='store_true')
    ap.add_argument('--no-rtti', action='store_true')
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args()
    if args.command in ('read', 'refs', 'strings', 'name', 'class', 'peek', 'vtslot') and not args.targets:
        ap.error('give at least one target')

    ok, refused = find_copy_processes()
    for pid, path in refused:
        print('REFUSED process %d: %s is not the copy (only %s is read)' % (pid, path, COPY_EXE))
    if not ok:
        raise SystemExit('the copy is not running (start it with tools\\start-copy.ps1 and wait for the title screen)')
    if args.pid:
        if args.pid not in ok:
            raise SystemExit('process %d is not a running copy; running: %s' % (args.pid, ok))
        pid = args.pid
    elif len(ok) > 1:
        raise SystemExit('%d copies are running (%s); pick one with --pid' % (len(ok), ', '.join(map(str, ok))))
    else:
        pid = ok[0]

    dump = None
    if not args.no_dump:
        if args.dump:
            dump = args.dump
        else:
            cands = []
            for root, dirs, files in os.walk(DUMPS_DIR):
                for fn in files:
                    if fn.lower().startswith('ue4ss_objectdump') and fn.lower().endswith('.txt'):
                        cands.append(os.path.join(root, fn))
            if cands:
                dump = max(cands, key=os.path.getmtime)
    dump_base = int(args.dump_base, 16) if args.dump_base else None

    proc = Process(pid)
    try:
        exe = LiveExe(proc, dump=dump, dump_base=dump_base, rtti=not args.no_rtti, quiet=args.quiet)
        {'info': cmd_info, 'read': cmd_read, 'refs': cmd_refs, 'strings': cmd_strings, 'name': cmd_name,
         'class': cmd_class, 'peek': cmd_peek, 'vtslot': cmd_vtslot}[args.command](exe, args)
    finally:
        proc.close()


if __name__ == '__main__':
    main()

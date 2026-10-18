import struct, sys, re, bisect
STREAM = {3:'ThreadList',4:'ModuleList',5:'MemoryList',6:'Exception',7:'SystemInfo',8:'ThreadExList',9:'Memory64List',10:'CommentA',11:'CommentW',12:'HandleData',13:'FunctionTable',14:'UnloadedModuleList',15:'MiscInfo',16:'MemoryInfoList',17:'ThreadInfoList',18:'HandleOperationList',19:'Token',21:'SystemMemoryInfo',22:'ProcessVmCounters'}
def rd(f,off,n): f.seek(off); return f.read(n)
def mstr(f,rva):
    n,=struct.unpack('<I',rd(f,rva,4)); return rd(f,rva+4,n).decode('utf-16-le','replace')
def short(nm): return nm.replace('\\','/').split('/')[-1]

def load_natives(dump_path, base):
    """Return sorted list of (offset, name) for native UFunctions in the UE4SS object dump."""
    pat = re.compile(r'\] Function (\S+) \[n: [0-9A-F]+\] \[c: [0-9A-F]+\] \[or: [0-9A-F]+\] \[f: ([0-9A-F]+)\]')
    out = {}
    with open(dump_path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            m = pat.search(line)
            if m:
                addr = int(m.group(2), 16)
                off = addr - base
                if 0 <= off < 0x441a000:
                    out.setdefault(off, []).append(m.group(1))
    offs = sorted(out)
    return offs, out

def nearest(offs, table, off):
    i = bisect.bisect_right(offs, off) - 1
    if i < 0: return None
    o = offs[i]
    names = table[o]
    return '%s (+0x%x past its start)' % (names[0] if len(names)==1 else names[0]+' [and %d others sharing this address]'%(len(names)-1), off - o)

def main(path, objdump=None, dumpbase=None):
    f=open(path,'rb'); hdr=rd(f,0,32)
    sig,ver,nstreams,diroff,cs,ts,flags=struct.unpack('<4sIIIIIQ',hdr)
    print('sig',sig,'streams',nstreams,'flags 0x%x'%flags)
    streams={}
    for i in range(nstreams):
        t,sz,rva=struct.unpack('<III',rd(f,diroff+12*i,12)); streams.setdefault(t,[]).append((sz,rva)); print('  stream',t,STREAM.get(t,'?'),'size',sz)
    mods=[]
    sz,rva=streams[4][0]; n,=struct.unpack('<I',rd(f,rva,4))
    for i in range(n):
        e=rd(f,rva+4+108*i,108); base,size,cs_,ts_,namerva=struct.unpack('<QIIII',e[:24]); mods.append((base,size,mstr(f,namerva)))
    exe=[m for m in mods if m[2].lower().endswith('ace7game.exe')][0]; print('exe base 0x%x size 0x%x'%(exe[0],exe[1]))
    mem=[]
    if 5 in streams:
        sz,rva=streams[5][0]; n,=struct.unpack('<I',rd(f,rva,4))
        for i in range(n):
            start,dsz,drva=struct.unpack('<QIi',rd(f,rva+4+16*i,16)); mem.append((start,dsz,drva))
    if 9 in streams:
        sz,rva=streams[9][0]; n,baserva=struct.unpack('<QQ',rd(f,rva,16)); off=baserva
        for i in range(n):
            start,dsz=struct.unpack('<QQ',rd(f,rva+16+16*i,16)); mem.append((start,dsz,off)); off+=dsz
    print('memory ranges',len(mem),'total bytes',sum(m[1] for m in mem))
    def read(addr,n):
        for s,l,r in mem:
            if s<=addr and addr+n<=s+l: return rd(f,r+(addr-s),n)
        return None
    offs, table = (None, None)
    if objdump:
        offs, table = load_natives(objdump, dumpbase)
        print('native UFunctions known from object dump:', len(offs))
    def tag(v):
        if exe[0]<=v<exe[0]+exe[1]:
            off = v-exe[0]
            s = ' (exe+0x%x)'%off
            if offs: s += ' near ' + str(nearest(offs, table, off))
            return s
        for b,s_,nm in mods:
            if b<=v<b+s_: return ' (%s+0x%x)'%(short(nm),v-b)
        return ''
    sz,rva=streams[6][0]; e=rd(f,rva,sz)
    tid,_,code,eflags,rec,addr,nparams=struct.unpack('<IIIIQQI',e[:36]); params=struct.unpack('<15Q',e[40:160]); ctxsz,ctxrva=struct.unpack('<II',e[160:168])
    print('exception thread',tid,'code 0x%x at 0x%x%s params'%(code,addr,tag(addr)),[hex(p) for p in params[:nparams]])
    ctx=rd(f,ctxrva,ctxsz)
    regs=['Rax','Rcx','Rdx','Rbx','Rsp','Rbp','Rsi','Rdi','R8','R9','R10','R11','R12','R13','R14','R15','Rip']
    vals=struct.unpack('<17Q',ctx[0x78:0x78+17*8])
    for r,v in zip(regs,vals): print('  %s=0x%016x%s'%(r,v,tag(v)))
    rsp=vals[4]
    sz,rva=streams[3][0]; n,=struct.unpack('<I',rd(f,rva,4)); stack=None
    for i in range(n):
        t=rd(f,rva+4+48*i,48); ttid,sc,pc,prio,teb,sstart,ssz,srva,csz,crva=struct.unpack('<IIIIQQIIII',t)
        if ttid==tid: print('crash thread stack 0x%x size 0x%x'%(sstart,ssz)); stack=(sstart,ssz)
    print('--- return-address candidates on the crashing thread stack ---')
    data=read(rsp,min(stack[0]+stack[1]-rsp,0x6000))
    out=[]
    for i in range(0,len(data)-7,8):
        v,=struct.unpack_from('<Q',data,i)
        for b,s_,nm in mods:
            if b<=v<b+s_:
                sn=short(nm).lower()
                if sn in ('ace7game.exe','steam_api64.dll','steamclient64.dll','gameoverlayrenderer64.dll','ue4ss.dll','dwmapi.dll'):
                    out.append('rsp+0x%04x: 0x%016x%s'%(i,v,tag(v)))
    print('\n'.join(out[:150]))
    cb=read(vals[16]-16,48)
    print('code bytes around rip:',cb.hex() if cb else None)
    print('--- modules of interest ---')
    for b,s_,nm in mods:
        if any(k in nm.lower() for k in ('steam','ue4ss','dwmapi','ace7','overlay')): print('  0x%x 0x%x %s'%(b,s_,nm))
if __name__=='__main__':
    main(sys.argv[1], sys.argv[2] if len(sys.argv)>2 else None, int(sys.argv[3],16) if len(sys.argv)>3 else None)

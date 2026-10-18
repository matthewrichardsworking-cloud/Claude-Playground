import struct, sys, os
BS = chr(92)
def rd(f,off,n): f.seek(off); return f.read(n)
def mstr(f,rva):
    n,=struct.unpack('<I',rd(f,rva,4)); return rd(f,rva+4,n).decode('utf-16-le','replace')
def short(nm): return nm.replace(BS,'/').split('/')[-1]

def pe_exports(path):
    """Return {rva: name} for a PE file's export table (read-only, from disk)."""
    d = open(path,'rb').read()
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    nsec = struct.unpack_from('<H', d, pe+6)[0]
    optsz = struct.unpack_from('<H', d, pe+20)[0]
    opt = pe+24
    exp_rva, exp_sz = struct.unpack_from('<II', d, opt+112)
    secs = []
    for i in range(nsec):
        s = pe+24+optsz+40*i
        vsz, va, rsz, rp = struct.unpack_from('<IIII', d, s+8)
        secs.append((va, vsz, rp, rsz))
    def r2o(rva):
        for va, vsz, rp, rsz in secs:
            if va <= rva < va+max(vsz,rsz): return rva-va+rp
        return None
    e = r2o(exp_rva)
    nfunc, nnames, addr_t, name_t, ord_t = struct.unpack_from('<IIIII', d, e+20)
    out = {}
    for i in range(nnames):
        nrva = struct.unpack_from('<I', d, r2o(name_t)+4*i)[0]
        o = struct.unpack_from('<H', d, r2o(ord_t)+2*i)[0]
        frva = struct.unpack_from('<I', d, r2o(addr_t)+4*o)[0]
        no = r2o(nrva); name = d[no:d.index(b'\0', no)].decode()
        out[frva] = name
    return out

path=sys.argv[1]; f=open(path,'rb')
sig,ver,nstreams,diroff,cs,ts,flags=struct.unpack('<4sIIIIIQ',rd(f,0,32))
streams={}
for i in range(nstreams):
    t,sz,rva=struct.unpack('<III',rd(f,diroff+12*i,12)); streams.setdefault(t,[]).append((sz,rva))
mods=[]
sz,rva=streams[4][0]; n,=struct.unpack('<I',rd(f,rva,4))
for i in range(n):
    e=rd(f,rva+4+108*i,108); base,size,_,_,namerva=struct.unpack('<QIIII',e[:24]); mods.append((base,size,mstr(f,namerva)))
exe=[m for m in mods if m[2].lower().endswith('ace7game.exe')][0]
steamapi=[m for m in mods if short(m[2]).lower()=='steam_api64.dll'][0]
exports = pe_exports(steamapi[2])
mem=[]
sz,rva=streams[5][0]; n,=struct.unpack('<I',rd(f,rva,4))
for i in range(n):
    start,dsz,drva=struct.unpack('<QIi',rd(f,rva+4+16*i,16)); mem.append((start,dsz,drva))
def read(addr,n):
    for s,l,r in mem:
        if s<=addr and addr+n<=s+l: return rd(f,r+(addr-s),n)
    return None
def tag(v):
    for b,s_,nm in mods:
        if b<=v<b+s_:
            t='%s+0x%x'%(short(nm),v-b)
            if b==steamapi[0] and (v-b) in exports: t+=' = '+exports[v-b]
            return t
    return ''
sz,rva=streams[6][0]; e=rd(f,rva,sz)
tid,_,code,eflags,rec,addr,nparams=struct.unpack('<IIIIQQI',e[:36]); ctxsz,ctxrva=struct.unpack('<II',e[160:168])
ctx=rd(f,ctxrva,ctxsz); vals=struct.unpack('<17Q',ctx[0x78:0x78+17*8]); rsp=vals[4]; rip=vals[16]; rax=vals[0]; rbx=vals[3]
sz,rva=streams[3][0]; n,=struct.unpack('<I',rd(f,rva,4))
print('threads:',n)
rows=[]
for i in range(n):
    t=rd(f,rva+4+48*i,48); ttid,sc,pc,prio,teb,sstart,ssz,srva,csz,crva=struct.unpack('<IIIIQQIIII',t)
    rows.append((ssz,ttid,sstart))
    if ttid==tid: stack=(sstart,ssz)
rows.sort(reverse=True)
for ssz,ttid,sstart in rows[:6]: print('  tid %d stack used 0x%x%s'%(ttid,ssz,'  <-- crashing' if ttid==tid else ''))
print('  crashing thread rank by stack use:', [r[1] for r in rows].index(tid)+1, 'of', n)
call_at = rip-16
slot = call_at+6+0x1ca6b69
print('import slot at 0x%x (%s)'%(slot, tag(slot)))
v=read(slot,8)
print('  slot contents in dump:', ('0x%x %s'%(struct.unpack('<Q',v)[0], tag(struct.unpack('<Q',v)[0]))) if v else 'not captured')
print('structure at rax=0x%x (%s):'%(rax, tag(rax)))
blk=read(rax,0x60)
if blk:
    for i in range(0,0x60,8): print('   +0x%02x: 0x%016x'%(i,struct.unpack_from('<Q',blk,i)[0]))
else: print('   not captured')
blk=read(rbx,0x80)
print('object at rbx=0x%x:'%rbx, 'captured' if blk else 'not captured')
if blk:
    for i in range(0,0x80,8):
        v=struct.unpack_from('<Q',blk,i)[0]; print('   +0x%02x: 0x%016x %s'%(i,v,tag(v)))
print('--- all module pointers on the crashing stack ---')
data=read(rsp, stack[0]+stack[1]-rsp)
for i in range(0,len(data)-7,8):
    v,=struct.unpack_from('<Q',data,i); t_=tag(v)
    if t_: print('  rsp+0x%04x: %s'%(i,t_))
print('--- steam_api64 exports whose addresses appear anywhere in captured memory near the stack: skipped ---')

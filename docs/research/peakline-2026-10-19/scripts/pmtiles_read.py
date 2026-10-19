"""Minimal PMTiles v3 reader (directories gzip/none). get(z,x,y) -> bytes or None."""
import gzip, struct
def _varint(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1; r |= (c & 0x7f) << s; s += 7
        if c < 0x80: return r, i
def _dec(b, comp): return gzip.decompress(b) if comp == 2 else b
def _zxy_to_id(z, x, y):
    acc = sum(4 ** t for t in range(z)); n = 1 << z; d = 0; s = n // 2; rx = ry = 0; xx, yy = x, y
    while s > 0:
        rx = 1 if (xx & s) else 0; ry = 1 if (yy & s) else 0
        d += s * s * ((3 * rx) ^ ry)
        if ry == 0:
            if rx == 1: xx = s - 1 - xx; yy = s - 1 - yy
            xx, yy = yy, xx
        s //= 2
    return acc + d
class PMTiles:
    def __init__(self, path):
        self.f = open(path, 'rb'); h = self.f.read(127); assert h[:7] == b'PMTiles' and h[7] == 3
        (self.root_off, self.root_len, self.meta_off, self.meta_len, self.leaf_off, self.leaf_len,
         self.data_off, self.data_len) = struct.unpack('<8Q', h[8:72])
        self.icomp, self.tcomp = h[97], h[98]
    def _read(self, off, n): self.f.seek(off); return self.f.read(n)
    def _dir(self, off, n):
        b = _dec(self._read(off, n), self.icomp); i = 0; cnt, i = _varint(b, i); ids = []; last = 0
        for _ in range(cnt): v, i = _varint(b, i); last += v; ids.append(last)
        runs = []; lens = []; offs = []
        for _ in range(cnt): v, i = _varint(b, i); runs.append(v)
        for _ in range(cnt): v, i = _varint(b, i); lens.append(v)
        for k in range(cnt):
            v, i = _varint(b, i); offs.append(offs[-1] + lens[k - 1] if (v == 0 and k > 0) else v - 1)
        return list(zip(ids, runs, lens, offs))
    def get(self, z, x, y):
        tid = _zxy_to_id(z, x, y); off, n = self.root_off, self.root_len
        for _ in range(4):
            ents = self._dir(off, n); lo, hi = 0, len(ents) - 1; hit = None
            while lo <= hi:
                m = (lo + hi) // 2
                if ents[m][0] <= tid: hit = ents[m]; lo = m + 1
                else: hi = m - 1
            if hit is None: return None
            eid, run, ln, o = hit
            if run == 0: off, n = self.leaf_off + o, ln; continue
            if tid < eid + run: return _dec(self._read(self.data_off + o, ln), self.tcomp)
            return None
        return None

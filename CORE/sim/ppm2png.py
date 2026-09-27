import sys, zlib, struct
def conv(src, dst, crop=(0,0,850,300), scale_y=2):
    d = open(src,'rb').read()
    parts = d.split(b'\n',1); hdr = parts[0].split(); w,h = int(hdr[1]), int(hdr[2]); px = parts[1]
    x0,y0,x1,y1 = crop
    rows=[]
    for y in range(y0, min(y1,h)):
        row = px[(y*w+x0)*3:(y*w+x1)*3]
        for _ in range(scale_y): rows.append(b'\x00'+row)
    W=x1-x0; H=len(rows)
    def chunk(t,b): return struct.pack('>I',len(b))+t+b+struct.pack('>I',zlib.crc32(t+b)&0xffffffff)
    png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',W,H,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows),9))+chunk(b'IEND',b'')
    open(dst,'wb').write(png)
if __name__=='__main__':
    sy = int(sys.argv[3]) if len(sys.argv)>3 else 2
    conv(sys.argv[1], sys.argv[2], scale_y=sy)

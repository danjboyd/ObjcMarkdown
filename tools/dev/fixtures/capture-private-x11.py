#!/usr/bin/env python3
"""Future guest-only capture: verify fixture identity, read pixels, encode PNG.

Review draft, never executed. No mouse/key/clipboard APIs. Captures the root of
the approved private X server after checking a fixture client on that server.
"""
import ctypes as C
import ctypes.util
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys
import zlib

def capture(work, client, pid, output, probe=False):
    work = work.resolve(strict=True)
    assert stat.S_IMODE(work.stat().st_mode) == 0o700
    assert Path('/var/lib/oracletestvms/debian13-lease-configured').is_file()
    assert re.fullmatch(r':[0-9]+(?:\.0)?', os.environ['DISPLAY'])
    auth = Path(os.environ['XAUTHORITY']).resolve(strict=True)
    assert auth.is_relative_to(work) and stat.S_IMODE(auth.stat().st_mode) == 0o600
    assert output.parent.resolve(strict=True).is_relative_to(work)
    exe = Path('/proc', str(pid), 'exe').resolve(strict=True)
    if probe:
        assert exe == Path('/usr/bin/zenity').resolve()
        assert b'OMD389-private-display-probe' in Path('/proc',str(pid),'cmdline').read_bytes()
    else:
        assert exe.name == 'OMDShareNoticeFixture' and exe.is_relative_to(work)
    props = subprocess.check_output(['xprop','-id',client,'_NET_WM_PID','WM_NAME','WM_CLASS'],text=True,timeout=3)
    assert re.search(r'_NET_WM_PID\([^)]*\)\s*=\s*'+str(pid)+r'\s*(?:\n|$)',props)
    if probe:
        assert 'OMD389-private-display-probe' in props and 'zenity' in props.lower()
    else:
        assert 'Share notice fixture - private synthetic file' in props
        assert 'OMDShareNoticeFixture' in props, 'require actual fixture WM_CLASS'
    x = C.CDLL(ctypes.util.find_library('X11'))
    class Image(C.Structure):
        _fields_ = [('width',C.c_int),('height',C.c_int),('xoffset',C.c_int),('format',C.c_int),('data',C.c_void_p),('byte_order',C.c_int),('bitmap_unit',C.c_int),('bitmap_bit_order',C.c_int),('bitmap_pad',C.c_int),('depth',C.c_int),('bytes_per_line',C.c_int),('bits_per_pixel',C.c_int),('red_mask',C.c_ulong),('green_mask',C.c_ulong),('blue_mask',C.c_ulong)]
    x.XOpenDisplay.argtypes=[C.c_char_p]; x.XOpenDisplay.restype=C.c_void_p
    x.XDefaultRootWindow.argtypes=[C.c_void_p]; x.XDefaultRootWindow.restype=C.c_ulong
    x.XGetImage.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_int,C.c_uint,C.c_uint,C.c_ulong,C.c_int]; x.XGetImage.restype=C.POINTER(Image)
    x.XGetPixel.argtypes=[C.POINTER(Image),C.c_int,C.c_int]; x.XGetPixel.restype=C.c_ulong
    x.XDestroyImage.argtypes=[C.POINTER(Image)]; x.XDestroyImage.restype=C.c_int
    x.XCloseDisplay.argtypes=[C.c_void_p]; x.XCloseDisplay.restype=C.c_int
    display=x.XOpenDisplay(None); assert display, 'cannot open authorized private display'
    image=None
    try:
        root=x.XDefaultRootWindow(display)
        info=subprocess.check_output(['xwininfo','-id',hex(root),'-stats'],text=True,timeout=3,env={**os.environ,'LC_ALL':'C'})
        width=int(re.search(r'Width:\s+(\d+)',info)[1]); height=int(re.search(r'Height:\s+(\d+)',info)[1])
        assert 1<=width<=1920 and 1<=height<=1200
        image=x.XGetImage(display,root,0,0,width,height,C.c_ulong(-1).value,2); assert image
        masks=[image.contents.red_mask,image.contents.green_mask,image.contents.blue_mask]; assert all(masks)
        shifts=[(m & -m).bit_length()-1 for m in masks]
        raw=bytearray()
        for y in range(height):
            raw.append(0)
            for col in range(width):
                pixel=x.XGetPixel(image,col,y)
                raw.extend(((pixel&m)>>s)*255//(m>>s) for m,s in zip(masks,shifts))
        def chunk(kind,data):
            return struct.pack('!I',len(data))+kind+data+struct.pack('!I',zlib.crc32(kind+data)&0xffffffff)
        png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!IIBBBBB',width,height,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
        with output.open('xb') as f:
            f.write(png)
        print(props,end='')
        print('CAPTURE',width,height,output)
    finally:
        if image:
            x.XDestroyImage(image)
        x.XCloseDisplay(display)

if __name__=='__main__':
    capture(Path(sys.argv[1]),sys.argv[2],int(sys.argv[3]),Path(sys.argv[4]),len(sys.argv)==6 and sys.argv[5]=='--probe')

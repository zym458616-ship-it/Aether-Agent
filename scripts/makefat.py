#!/usr/bin/env python3
"""Combine thin Mach-O slices into a fat binary (a minimal lipo replacement).

Usage: makefat.py out.bin arm64:path/to/arm64.dylib arm64e:path/to/arm64e.dylib

Notes
-----
ld64.lld (LLVM 16) emits arm64e code but records CPU_SUBTYPE 0 in the Mach-O
header, which dyld would treat as a plain arm64 slice. We rewrite the header
subtype so the resulting binary is loadable inside arm64e host processes
(SpringBoard and other system apps on A12+ devices).
"""
import struct
import sys

FAT_MAGIC = 0xcafebabe
ALIGN = 0x4000  # 16 KB page size, required by arm64 iOS

CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64_ALL = 0
CPU_SUBTYPE_ARM64E = 0x80000002  # ABI v2 with pointer authentication

ARCHS = {
    'arm64': (CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL),
    'arm64e': (CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64E),
}


def load(path, arch):
    with open(path, 'rb') as f:
        data = bytearray(f.read())
    if len(data) < 32:
        raise SystemExit('short Mach-O: %s' % path)
    magic = struct.unpack('<I', bytes(data[:4]))[0]
    if magic != 0xFEEDFACF:
        raise SystemExit('not a thin 64-bit Mach-O: %s' % path)
    cpu, sub = ARCHS[arch]
    if struct.unpack('<I', bytes(data[4:8]))[0] != cpu:
        raise SystemExit('%s: unexpected cputype %08x' % (path, struct.unpack('<I', bytes(data[4:8]))[0]))
    struct.pack_into('<I', data, 8, sub)
    return cpu, sub, bytes(data)


def main(out, specs):
    blobs = []
    for spec in specs:
        arch, _, path = spec.partition(':')
        if arch not in ARCHS:
            raise SystemExit('unknown arch spec: %s' % spec)
        blobs.append((path,) + load(path, arch))

    n = len(blobs)
    header_len = 8 + n * 20
    entries = b''
    body = b''

    for _, cpu, sub, data in blobs:
        start = header_len + len(body)
        pad = (ALIGN - (start % ALIGN)) % ALIGN
        body += b'\0' * pad
        start = header_len + len(body)
        entries += struct.pack('>IIIII', cpu & 0xffffffff, sub & 0xffffffff, start, len(data), 14)  # 2^14 = 16384
        body += data

    with open(out, 'wb') as f:
        f.write(struct.pack('>II', FAT_MAGIC, n))
        f.write(entries)
        f.write(body)

    print('wrote %s: %d slices, %d bytes' % (out, n, header_len + len(body)))
    for path, cpu, sub, data in blobs:
        print('  %-28s cpu=%08x sub=%08x size=%d' % (path.split('/')[-1], cpu, sub, len(data)))


if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2:])

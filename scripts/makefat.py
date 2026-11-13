#!/usr/bin/env python3
"""Combine thin Mach-O slices into a fat binary (a minimal lipo replacement)."""
import struct
import sys

FAT_MAGIC = 0xcafebabe
ALIGN = 0x4000  # 16 KB, required by arm64 iOS


def read_cpu(path):
    with open(path, 'rb') as f:
        head = f.read(12)
    if len(head) < 12:
        raise SystemExit('short Mach-O header: %s' % path)
    magic = struct.unpack('<I', head[:4])[0]
    if magic != 0xfeedfacf:
        raise SystemExit('not a thin 64-bit Mach-O: %s (magic %08x)' % (path, magic))
    cpu, sub = struct.unpack('<ii', head[4:12])
    return cpu, sub


def main(out, slices):
    blobs = []
    for p in slices:
        with open(p, 'rb') as f:
            blobs.append((p, f.read()))

    n = len(blobs)
    header_len = 8 + n * 20
    entries = b''
    body = b''

    for path, data in blobs:
        cpu, sub = read_cpu(path)
        start = header_len + len(body)
        pad = (ALIGN - (start % ALIGN)) % ALIGN
        body += b'\0' * pad
        start = header_len + len(body)
        entries += struct.pack('>iiIII', cpu, sub, start, len(data), 14)  # 2^14
        body += data

    with open(out, 'wb') as f:
        f.write(struct.pack('>II', FAT_MAGIC, n))
        f.write(entries)
        f.write(body)

    print('wrote %s: %d slices, %d bytes' % (out, n, header_len + len(body)))


if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit('usage: makefat.py out input1 [input2 ...]')
    main(sys.argv[1], sys.argv[2:])

#!/usr/bin/env python3
"""Combine thin Mach-O slices into a fat binary (lipo replacement)."""
import struct
import sys

FAT_MAGIC = 0xcafebabe
ALIGN = 0x4000  # 16 KB page size, required by arm64 iOS


def read_cpu(path):
    with open(path, 'rb') as f:
        head = f.read(8)
    magic = struct.unpack('<I', head[:4])[0]
    if magic == 0xfeedfacf:  # MH_MAGIC_64
        cpu, sub = struct.unpack('<ii', head[4:12])
        return cpu, sub
    raise SystemExit('not a thin 64-bit Mach-O: %s' % path)


def pad_to(data, alignment):
    rem = len(data) % alignment
    return data if rem == 0 else data + b'\0' * (alignment - rem)


def main(out, *slices):
    blobs = []
    for p in slices:
        with open(p, 'rb') as f:
            blobs.append((p, f.read()))

    n = len(blobs)
    header = struct.pack('>II', FAT_MAGIC, n)
    offset = 8 + n * 20
    entries = b''
    body = b''

    cursor = 0
    for path, data in blobs:
        cpu, sub = read_cpu(path)
        body = pad_to(body, ALIGN)
        start = offset + cursor
        entries += struct.pack('>iiIII', cpu, sub, start, len(data), 14)  # 2^14 = 16384
        body += data
        cursor = len(body)

    with open(out, 'wb') as f:
        f.write(header)
        f.write(entries)
        # entries length is part of the offset already counted via 'offset'
        f.write(body[:0])
        f.seek(0)
        f.write(header + entries)
        f.seek(offset)
        f.write(body)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit('usage: makefat.py out input1 [input2 ...]')
    main(sys.argv[1], *sys.argv[2:])

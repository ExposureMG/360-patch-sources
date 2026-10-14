#!/usr/bin/env python3
"""
smcpatch.py - build, inspect and apply Xbox 360 SMC patch blobs.

Format (all big-endian; see patches/smc_macros.S):
  0x00  'SMCP'
  0x04  u16 version (1), u16 flags (0)
  0x08  u8 revision, u8 major, u8 minor (base image 0x100-0x102), u8 0
  0x0C  u32 CRC32 of the clean raw base dump
  0x10  records until EOF: u32 address, u32 length, data

Commands:
  pack  BASE.bin PATCH.ihx -o OUT.smcpatch   Intel HEX from sdld -> patch blob
  apply BASE.bin PATCH.smcpatch -o OUT.bin   check base, apply records
  info  PATCH.smcpatch                        print header and records
  diff  BASE.bin PATCHED.bin                  list differing byte ranges
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

MAGIC = b"SMCP"
VERSION = 1
HEADER = struct.Struct(">4sHHBBBBI")


def read_ihx(path: Path) -> dict[int, int]:
    data: dict[int, int] = {}
    upper = 0
    for n, line in enumerate(path.read_text().split(), 1):
        if not line.startswith(":"):
            continue
        raw = bytes.fromhex(line[1:])
        if sum(raw) & 0xFF:
            raise SystemExit(f"{path}:{n}: bad checksum")
        count, addr, typ = raw[0], raw[1] << 8 | raw[2], raw[3]
        if typ == 0:
            for i, b in enumerate(raw[4:4 + count]):
                a = upper + addr + i
                if a in data and data[a] != b:
                    raise SystemExit(f"{path}: address 0x{a:04X} written twice with different values")
                data[a] = b
        elif typ == 4:
            upper = (raw[4] << 8 | raw[5]) << 16
        elif typ == 1:
            break
    return data


def records(data: dict[int, int]) -> list[tuple[int, bytes]]:
    out: list[tuple[int, bytes]] = []
    for a in sorted(data):
        if out and out[-1][0] + len(out[-1][1]) == a:
            out[-1] = (out[-1][0], out[-1][1] + bytes([data[a]]))
        else:
            out.append((a, bytes([data[a]])))
    return out


def header_for(base: bytes) -> bytes:
    return HEADER.pack(MAGIC, VERSION, 0, base[0x100], base[0x101], base[0x102], 0, zlib.crc32(base))


def parse(blob: bytes):
    if len(blob) < HEADER.size:
        raise SystemExit("not an SMC patch: too short")
    magic, ver, flags, rev, major, minor, _, crc = HEADER.unpack_from(blob)
    if magic != MAGIC:
        raise SystemExit("not an SMC patch: bad magic (xeBuild kernel patch?)")
    if ver != VERSION:
        raise SystemExit(f"unsupported SMC patch version {ver}")
    recs, pos = [], HEADER.size
    while pos < len(blob):
        if pos + 8 > len(blob):
            raise SystemExit("truncated record header")
        addr, length = struct.unpack_from(">II", blob, pos)
        pos += 8
        if pos + length > len(blob):
            raise SystemExit(f"truncated record at 0x{addr:04X}")
        recs.append((addr, blob[pos:pos + length]))
        pos += length
    return (rev, major, minor, crc, flags), recs


def cmd_pack(a) -> int:
    base = a.base.read_bytes()
    data = read_ihx(a.ihx)
    bad = [x for x in data if x >= len(base)]
    if bad:
        raise SystemExit(f"patch writes past the end of the image: 0x{min(bad):04X}")
    blob = bytearray(header_for(base))
    for addr, chunk in records(data):
        blob += struct.pack(">II", addr, len(chunk)) + chunk
    a.output.write_bytes(blob)
    recs = records(data)
    print(f"{a.output}: {len(recs)} records, {sum(len(c) for _, c in recs)} bytes, "
          f"base rev 0x{base[0x100]:02X} v{base[0x101]}.{base[0x102]:02d}")
    return 0


def cmd_apply(a) -> int:
    base = bytearray(a.base.read_bytes())
    (rev, major, minor, crc, _), recs = parse(a.patch.read_bytes())
    problems = []
    if (base[0x100], base[0x101], base[0x102]) != (rev, major, minor):
        problems.append(f"base is rev 0x{base[0x100]:02X} v{base[0x101]}.{base[0x102]:02d}, "
                        f"patch wants rev 0x{rev:02X} v{major}.{minor:02d}")
    if zlib.crc32(base) != crc:
        problems.append(f"base CRC32 {zlib.crc32(base):08X} != expected {crc:08X} (not the clean dump?)")
    if problems and not a.force:
        raise SystemExit("refusing to patch:\n  " + "\n  ".join(problems) + "\n(use --force to override)")
    for addr, chunk in recs:
        if addr + len(chunk) > len(base):
            raise SystemExit(f"record at 0x{addr:04X} runs past the image")
        base[addr:addr + len(chunk)] = chunk
    a.output.write_bytes(base)
    print(f"{a.output}: applied {len(recs)} records")
    return 0


def cmd_info(a) -> int:
    (rev, major, minor, crc, flags), recs = parse(a.patch.read_bytes())
    print(f"SMC patch v{VERSION}: base rev 0x{rev:02X} v{major}.{minor:02d}, base CRC32 {crc:08X}, flags {flags}")
    for addr, chunk in recs:
        preview = chunk[:16].hex(" ") + (" ..." if len(chunk) > 16 else "")
        print(f"  0x{addr:04X} +{len(chunk):<4} {preview}")
    print(f"{len(recs)} records, {sum(len(c) for _, c in recs)} bytes")
    return 0


def cmd_diff(a) -> int:
    x, y = a.base.read_bytes(), a.patched.read_bytes()
    if len(x) != len(y):
        raise SystemExit("images differ in size")
    for addr, chunk in records({i: y[i] for i in range(len(x)) if x[i] != y[i]}):
        print(f"0x{addr:04X} +{len(chunk):<4} {x[addr:addr + len(chunk)].hex(' ')} -> {chunk.hex(' ')}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Xbox 360 SMC patch blobs")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("pack")
    p.add_argument("base", type=Path)
    p.add_argument("ihx", type=Path)
    p.add_argument("-o", "--output", type=Path, required=True)
    p = sub.add_parser("apply")
    p.add_argument("base", type=Path)
    p.add_argument("patch", type=Path)
    p.add_argument("-o", "--output", type=Path, required=True)
    p.add_argument("--force", action="store_true", help="apply even if the base doesn't match")
    p = sub.add_parser("info")
    p.add_argument("patch", type=Path)
    p = sub.add_parser("diff")
    p.add_argument("base", type=Path)
    p.add_argument("patched", type=Path)
    a = ap.parse_args()
    return {"pack": cmd_pack, "apply": cmd_apply, "info": cmd_info, "diff": cmd_diff}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())

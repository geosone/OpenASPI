#!/usr/bin/env python3
"""Build a SyQuest cartridge image: an MBR and one FAT16 partition at LBA 32.

The MBR boots nothing itself: it chains to the floppy, so the BIOS may keep
the cartridge first in its boot order while DOS still starts from A:.
"""
import struct
import subprocess
import sys
from pathlib import Path

HPC, SPT = 16, 32
START = SPT                                     # cylinder 0, head 1

# Relocate to 0:0600, then read A: sector 0 to 0:7C00 (three tries, with a
# disk reset before each, while the motor spins up) and jump to it.
CHAIN = bytes.fromhex(
    "fa31c08ed0bc007c8ed88ec0fbbe007cbf0006b90001f3a5ea1d060000"
    "bf0300" "31c031d2cd13" "bb007cb80102b9010031d2cd13" "7305" "4f" "75e8" "ebfe"
    "ea007c0000")


def chs(lba):
    cyl = min(lba // (HPC * SPT), 1023)
    return bytes([(lba // SPT) % HPC, ((cyl >> 2) & 0xC0) | (lba % SPT + 1), cyl & 0xFF])


def main():
    out, total = Path(sys.argv[1]), int(sys.argv[2])
    size = total - START
    part = out.with_suffix(".part")
    subprocess.run(["truncate", "-s", str(size * 512), part], check=True)
    subprocess.run(["mkfs.fat", "-F16", "-n", "SYQUEST", "-h", str(START), "-S", "512",
                    "-g", f"{HPC}/{SPT}", "-i", "51151151", part],
                   check=True, stdout=subprocess.DEVNULL)
    mbr = bytearray(512)
    mbr[0:len(CHAIN)] = CHAIN
    mbr[446:462] = (bytes([0x00]) + chs(START) + bytes([0x06]) + chs(total - 1)
                    + struct.pack("<II", START, size))
    mbr[510:512] = b"\x55\xAA"
    with out.open("wb") as image, part.open("rb") as body:
        image.write(mbr)
        image.write(bytes(512 * (START - 1)))
        while chunk := body.read(1 << 20):
            image.write(chunk)
    part.unlink()


if __name__ == "__main__":
    main()

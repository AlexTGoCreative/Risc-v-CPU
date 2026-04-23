#!/usr/bin/env python3
"""
Cross-platform build helpers for darkriscv.
Replaces Unix-specific utilities (awk, hexdump, xxd, dd, wc, rm) for Windows compatibility.
"""

import sys
import struct
import re
import os
import shutil
import glob


def extract_mlen(config_file):
    """Extract 2**MLEN from config.vh (replaces: awk '/define MLEN/ { print 2**$3 }')"""
    with open(config_file, 'r') as f:
        for line in f:
            m = re.search(r'`define\s+MLEN\s+(\d+)', line)
            if m:
                print(2 ** int(m.group(1)))
                return
    print("ERROR: MLEN not found in " + config_file, file=sys.stderr)
    sys.exit(1)


def check_trace(config_file):
    """Check if __TRACE__ is defined. Exit 0 if defined, 1 if not."""
    with open(config_file, 'r') as f:
        for line in f:
            if re.match(r'^`define\s+__TRACE__', line):
                sys.exit(0)
    sys.exit(1)


def bin2hex(bin_file, hex_file, endian='little'):
    """Convert binary file to hex words (replaces hexdump/xxd)."""
    with open(bin_file, 'rb') as bf:
        data = bf.read()
    # Pad to 4-byte alignment
    while len(data) % 4 != 0:
        data += b'\x00'
    with open(hex_file, 'w') as hf:
        if endian == 'little':
            # Replaces: hexdump -ve '1/4 "%08x\n"'
            for i in range(0, len(data), 4):
                word = struct.unpack('<I', data[i:i+4])[0]
                hf.write(f'{word:08x}\n')
        else:
            # Replaces: xxd -p -c 4 -g 4
            for i in range(0, len(data), 4):
                hf.write(data[i:i+4].hex() + '\n')


def count_lines(filename):
    """Count lines in file (replaces wc -l)."""
    with open(filename, 'r') as f:
        count = sum(1 for _ in f)
    print(f'  {count} {filename}')


def skip_copy(in_file, out_file, skip_bytes):
    """Copy file skipping N bytes from the start (replaces dd with skip)."""
    with open(in_file, 'rb') as inf:
        inf.seek(int(skip_bytes))
        data = inf.read()
    with open(out_file, 'wb') as outf:
        outf.write(data)


def remove_files(*patterns):
    """Remove files (cross-platform rm -f). Supports glob patterns."""
    for pattern in patterns:
        matched = glob.glob(pattern)
        if matched:
            for f in matched:
                try:
                    if os.path.isfile(f):
                        os.remove(f)
                except OSError:
                    pass
        # Also try as literal filename
        elif os.path.isfile(pattern):
            try:
                os.remove(pattern)
            except OSError:
                pass


def remove_dir(path):
    """Remove directory recursively (cross-platform rm -rf)."""
    try:
        if os.path.isdir(path):
            shutil.rmtree(path)
    except OSError:
        pass


def get_build_date():
    """Get build date string (replaces date -R)."""
    import datetime
    print(datetime.datetime.now().strftime('%a, %d %b %Y %H:%M:%S'))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: helpers.py <command> [args...]", file=sys.stderr)
        print("Commands: extract_mlen, check_trace, bin2hex, count_lines,", file=sys.stderr)
        print("          skip_copy, rm, rmdir, build_date", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]
    args = sys.argv[2:]

    if cmd == 'extract_mlen':
        extract_mlen(args[0])
    elif cmd == 'check_trace':
        check_trace(args[0])
    elif cmd == 'bin2hex':
        # bin2hex <input> <output> [little|big]
        endian = args[2] if len(args) > 2 else 'little'
        bin2hex(args[0], args[1], endian)
    elif cmd == 'count_lines':
        count_lines(args[0])
    elif cmd == 'skip_copy':
        # skip_copy <input> <output> <skip_bytes>
        skip_copy(args[0], args[1], args[2])
    elif cmd == 'rm':
        remove_files(*args)
    elif cmd == 'rmdir':
        remove_dir(args[0])
    elif cmd == 'build_date':
        get_build_date()
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)

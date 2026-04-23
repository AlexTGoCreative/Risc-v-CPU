#!/usr/bin/env python3
"""
mem2mif.py - Convert darksocv.mem hex file to Altera MIF format
Usage: python mem2mif.py <input.mem> <output.mif> [depth]

The .mem file has one 32-bit hex word per line (little-endian).
The MIF format is required by Altera altsyncram for BRAM initialization.
"""

import sys

def mem2mif(input_file, output_file, depth=8192):
    words = []
    with open(input_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                words.append(line.lower().zfill(8))

    # Pad to full depth with zeros
    while len(words) < depth:
        words.append('00000000')

    with open(output_file, 'w') as f:
        f.write(f'DEPTH = {depth};\n')
        f.write('WIDTH = 32;\n')
        f.write('ADDRESS_RADIX = HEX;\n')
        f.write('DATA_RADIX = HEX;\n')
        f.write('CONTENT\n')
        f.write('BEGIN\n')
        for i, word in enumerate(words[:depth]):
            f.write(f'{i:08x} : {word};\n')
        f.write('END;\n')

    print(f'Wrote {min(len(words), depth)} words to {output_file}')

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f'Usage: {sys.argv[0]} <input.mem> <output.mif> [depth]')
        sys.exit(1)
    depth = int(sys.argv[3]) if len(sys.argv) > 3 else 2048
    mem2mif(sys.argv[1], sys.argv[2], depth)

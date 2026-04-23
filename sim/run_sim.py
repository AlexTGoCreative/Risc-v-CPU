#!/usr/bin/env python3
"""
Simulation runner with trace filtering for darkriscv.
Replaces the awk-based pipeline in sim/Makefile for Windows compatibility.
"""

import sys
import subprocess
import re


def check_trace_defined(config_file):
    """Check if __TRACE__ is defined in config.vh."""
    with open(config_file, 'r') as f:
        for line in f:
            if re.match(r'^`define\s+__TRACE__', line):
                return True
    return False


def run_simulation(xsim, trace_file, config_file):
    """Run the Icarus Verilog simulation, optionally filtering trace output."""
    trace_defined = check_trace_defined(config_file)

    if not trace_defined:
        # No trace mode - run simulator directly
        result = subprocess.run(['vvp', xsim])
        return result.returncode
    else:
        # Trace mode - pipe output through trace filter
        proc = subprocess.Popen(
            ['vvp', xsim],
            stdout=subprocess.PIPE,
            text=True
        )

        with open(trace_file, 'w') as tf:
            for line in proc.stdout:
                line = line.rstrip('\n')
                if 'trace:' in line:
                    tf.write(line + '\n')
                    if '40000005:' in line:
                        parts = line.split()
                        if parts:
                            a = parts[-1].split(':')
                            if len(a) >= 2:
                                try:
                                    val = int(a[1], 16)
                                    if val > 65536:
                                        val = val // 256
                                    sys.stdout.write(chr(val // 256))
                                    sys.stdout.flush()
                                except (ValueError, OverflowError):
                                    pass
                else:
                    print(line)

        proc.wait()
        return proc.returncode


if __name__ == '__main__':
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <xsim> <trace_file> <config_file>",
              file=sys.stderr)
        sys.exit(1)

    sys.exit(run_simulation(sys.argv[1], sys.argv[2], sys.argv[3]))

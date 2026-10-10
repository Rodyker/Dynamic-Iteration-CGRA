#!/usr/bin/env python3
# Written by Claude.
"""
Simulate a config in xsim, or build it and put it on the Basys 3.

    cgra sim     configs/rsqrt.csv [--inputs 2CF3 1000 0 110A | --dec 1.405 0.5 0 0.532] [--trace]
    cgra fpga    configs/rsqrt.csv [--sw 1] [--led 0] [--inputs ... | --dec ...] [--no-program]
    cgra program configs/rsqrt.csv           reprogram the bitstream built earlier

Defaults come from '#@' lines in the config; flags override them:

    #@ inputs 2CF3 1000 0000 110A     input[0] .. input[3], hex Q3.13
    #@ board  sw=1 led=0              switches drive input[sw], LEDs show output[led]

Vivado is found from CGRA_VIVADO (e.g. C:\\Xilinx\\2025.1\\Vivado), the usual
install folders, or PATH. Work files go to sim/build and fpga/build.
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM_DIR = os.path.join(ROOT, "sim", "build")
FPGA_DIR = os.path.join(ROOT, "fpga", "build")
RTL = ["cgra_pkg.sv", "pe.sv", "lcu.sv", "top.sv"]
WIN = os.name == "nt"


def fail(msg):
    sys.exit(f"error: {msg}")


def find_vivado():
    """Return the Vivado install dir (the one holding bin/vivado)."""
    env = os.environ.get("CGRA_VIVADO")
    if env:
        return env
    patterns = ["C:/Xilinx/*/Vivado", "C:/AMDDesignTools/*/Vivado",
                "/tools/Xilinx/*/Vivado", "/opt/Xilinx/*/Vivado",
                "/tools/Xilinx/Vivado/*", "/opt/Xilinx/Vivado/*"]
    found = [d for p in patterns for d in glob.glob(p)
             if os.path.exists(os.path.join(d, "bin", "vivado.bat" if WIN else "vivado"))]
    if found:
        return sorted(found)[-1]
    on_path = shutil.which("vivado")
    if on_path:
        return os.path.dirname(os.path.dirname(on_path))
    fail("Vivado not found; set CGRA_VIVADO to its install dir, e.g. C:\\Xilinx\\2025.1\\Vivado")


def tool(name):
    return os.path.join(find_vivado(), "bin", name + (".bat" if WIN else ""))


def run(cmd, cwd, log=None, show=None):
    """Run a command, saving its output to log. Lines matching `show` are echoed."""
    proc = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, errors="replace")
    lines = []
    for line in proc.stdout:
        lines.append(line)
        if show and re.search(show, line):
            print("  " + line.rstrip())
    proc.wait()
    text = "".join(lines)
    if log:
        with open(log, "w") as f:
            f.write(text)
    return proc.returncode, text


def config_path(args):
    path = os.path.abspath(args.config)
    if not os.path.isfile(path):
        fail(f"config not found: {args.config}")
    return path


def read_defaults(csv_path):
    """Parse '#@ inputs ...' and '#@ board sw=N led=N' lines."""
    inputs, board = [0, 0, 0, 0], {"sw": 0, "led": 0}
    with open(csv_path) as f:
        for line in f:
            if not line.startswith("#@"):
                continue
            key, *vals = line[2:].split()
            if key == "inputs":
                inputs = [int(v, 16) & 0xFFFF for v in vals]
                if len(inputs) != 4:
                    fail(f"{csv_path}: '#@ inputs' needs four values")
            elif key == "board":
                board.update({k: int(v) for k, v in (kv.split("=") for kv in vals)})
    return inputs, board


def assemble(csv_path, out_path):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    code, text = run([sys.executable, os.path.join(ROOT, "assembler.py"), csv_path, out_path], ROOT)
    if code:
        fail(f"assembler failed:\n{text}")


def pick(args, csv_path):
    inputs, board = read_defaults(csv_path)
    if args.inputs:
        try:
            inputs = [int(v, 16) for v in args.inputs]
        except ValueError:
            fail("--inputs takes hex values, e.g. 2000; use --dec for decimals like 1.0")
        if any(not 0 <= v <= 0xFFFF for v in inputs):
            fail("--inputs values must fit in 16 bits (0000-FFFF)")
    elif args.dec:
        if any(not -4 <= v < 4 for v in args.dec):
            fail("--dec values must be in [-4, 4), the Q3.13 range")
        # Round to the nearest LSB; the top code would round up out of range.
        inputs = [min(round(v * 8192), 32767) & 0xFFFF for v in args.dec]
    sw = board["sw"] if getattr(args, "sw", None) is None else args.sw
    led = board["led"] if getattr(args, "led", None) is None else args.led
    return inputs, sw, led


def cmd_sim(args):
    csv_path = config_path(args)
    inputs, _, _ = pick(args, csv_path)
    assemble(csv_path, os.path.join(SIM_DIR, "config.bin"))

    # Recompile only when the RTL or testbench changed.
    sources = [os.path.join(ROOT, f) for f in RTL + ["tb.sv"]]
    stamp = os.path.join(SIM_DIR, ".compiled")
    if not os.path.exists(stamp) or max(map(os.path.getmtime, sources)) > os.path.getmtime(stamp):
        print("Compiling RTL ...")
        for cmd, log in ([tool("xvlog"), "-sv", *sources], "xvlog.txt"), \
                        ([tool("xelab"), "tb", "-s", "tb"], "xelab.txt"):
            code, text = run(cmd, SIM_DIR, os.path.join(SIM_DIR, log))
            if code:
                fail(f"{os.path.basename(cmd[0])} failed:\n{text}")
        open(stamp, "w").close()

    # Plusargs go through an options file: xsim.bat splits arguments at '='.
    with open(os.path.join(SIM_DIR, "args.f"), "w") as f:
        for i, v in enumerate(inputs):
            f.write(f"-testplusarg input{i}={v:04x}\n")

    print(f"Simulating {os.path.relpath(csv_path, ROOT)} with inputs "
          + " ".join(f"{v:04X}" for v in inputs)
          + "  (" + ", ".join(f"{(v - 65536 if v > 32767 else v) / 8192:g}" for v in inputs) + ")")
    code, text = run([tool("xsim"), "tb", "-R", "-f", "args.f"], SIM_DIR,
                     os.path.join(SIM_DIR, "xsim.txt"))
    lines = text.splitlines()
    first = next((i for i, l in enumerate(lines) if l.startswith("Cycle" if args.trace else "Output:")), None)
    last = next((i for i, l in enumerate(lines) if l.startswith("LCU:")), None)
    if code or first is None or last is None:
        fail(f"simulation failed (log in sim/build/xsim.txt):\n{text}")
    print("\n".join(lines[first:last + 1]))
    print("Waveform: sim/build/wave.vcd")


def program(bit):
    print(f"Programming {os.path.relpath(bit, ROOT)} ...")
    code, text = run([tool("vivado"), "-mode", "batch", "-nojournal", "-log", "program.log",
                      "-source", os.path.join(ROOT, "fpga", "program.tcl"), "-tclargs", bit],
                     FPGA_DIR, show=r"^ERROR")
    if code or "End of startup status: HIGH" not in text:
        fail("programming failed (log in fpga/build/program.log); is the board connected and on?")
    print("Board programmed.")


def cmd_fpga(args):
    csv_path = config_path(args)
    name = os.path.splitext(os.path.basename(csv_path))[0]
    inputs, sw, led = pick(args, csv_path)
    if not (0 <= sw < 4 and 0 <= led < 4):
        fail("--sw and --led must be 0-3")
    bin_path = os.path.join(FPGA_DIR, name + ".bin")
    assemble(csv_path, bin_path)

    inputs_hex = "".join(f"{v:04X}" for v in reversed(inputs))  # input[3] first
    print(f"Building {name}: switches -> input[{sw}], LEDs -> output[{led}], other inputs "
          + " ".join(f"[{i}]={v:04X}" for i, v in enumerate(inputs) if i != sw))
    print("This takes a few minutes ...")
    code, text = run([tool("vivado"), "-mode", "batch", "-nojournal", "-log", name + ".log",
                      "-source", os.path.join(ROOT, "fpga", "build.tcl"),
                      "-tclargs", bin_path, str(sw), str(led), inputs_hex, name],
                     FPGA_DIR, show=r"_design completed|write_bitstream completed|^ERROR|CRITICAL WARNING")
    if code:
        fail(f"build failed (log in fpga/build/{name}.log)")

    m = re.search(r"^CGRA_WNS (\S+)", text, re.M)
    wns = float(m.group(1)) if m else None
    print(f"Timing slack: {wns} ns" if wns is not None else "Timing slack: unknown")
    if wns is None or wns < 0:
        if not args.ignore_timing:
            fail(f"timing not met; see fpga/build/{name}_timing.rpt (or pass --ignore-timing)")
        print("warning: timing not met, programming anyway")

    if not args.no_program:
        program(os.path.join(FPGA_DIR, name + ".bit"))


def cmd_program(args):
    csv_path = config_path(args)
    name = os.path.splitext(os.path.basename(csv_path))[0]
    bit = os.path.join(FPGA_DIR, name + ".bit")
    if not os.path.exists(bit):
        fail(f"no bitstream for {name}; run 'cgra fpga {args.config}' first")
    if os.path.getmtime(csv_path) > os.path.getmtime(bit):
        print(f"warning: {args.config} changed since {name}.bit was built")
    program(bit)


def add_input_args(parser, note):
    g = parser.add_mutually_exclusive_group()
    g.add_argument("--inputs", nargs=4, metavar="HEX",
                   help="input[0] .. input[3] as raw Q3.13 hex" + note)
    g.add_argument("--dec", nargs=4, type=float, metavar="NUM",
                   help="input[0] .. input[3] as decimals in [-4, 4)" + note)


def main():
    p = argparse.ArgumentParser(prog="cgra", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("sim", help="assemble and simulate a config in xsim")
    s.add_argument("config")
    add_input_args(s, "")
    s.add_argument("--trace", action="store_true", help="print the PE grid every cycle")
    s.set_defaults(func=cmd_sim)

    f = sub.add_parser("fpga", help="build a config for the Basys 3 and program it")
    f.add_argument("config")
    add_input_args(f, "; input[sw] comes from the switches")
    f.add_argument("--sw", type=int, help="input slot driven by the switches")
    f.add_argument("--led", type=int, help="output shown on the LEDs")
    f.add_argument("--no-program", action="store_true", help="build only")
    f.add_argument("--ignore-timing", action="store_true", help="program even if timing fails")
    f.set_defaults(func=cmd_fpga)

    g = sub.add_parser("program", help="program a bitstream built earlier")
    g.add_argument("config")
    g.set_defaults(func=cmd_program)

    os.makedirs(SIM_DIR, exist_ok=True)
    os.makedirs(FPGA_DIR, exist_ok=True)
    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

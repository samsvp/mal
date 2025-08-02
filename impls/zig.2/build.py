#!/bin/python3

import os
import subprocess
import argparse

commands = {
    0: "step0_repl",
    1: "step1_read_print",
    2: "step2_eval",
    3: "step3_env",
    4: "step4_if_fn_do",
    5: "step5_tco",
    6: "step6_file",
}

def build(step: int):
    command = commands[step]
    subprocess.run([
        "zig",
        "build",
        #"-Doptimize=ReleaseFast",
        f"-Dname={command}",
        f"-Droot_source_file={command}.zig"
    ])

def run(step: int):
    current_env = os.environ.copy()
    current_env["STEP"] = commands[step]
    subprocess.run(["./run"], env=current_env)

parser = argparse.ArgumentParser()
parser.add_argument('-b', '--build', action='store_true')
parser.add_argument('-r', '--run', action='store_true')
parser.add_argument('-s', '--step', type=int)

args = parser.parse_args()

if args.build:
    build(args.step)
if args.run:
    run(args.step)

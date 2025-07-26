#!/bin/python3

import subprocess
import sys
import argparse

commands = {
    0: "step0_repl",
    1: "step1_read_print",
    2: "step2_eval",
}

def build(step: int):
    command = commands[step]
    subprocess.run(["zig", "build", f"-Dname={command}", f"-Droot_source_file={command}.zig"])

def run(step: int):
    subprocess.run(["./run"])

parser = argparse.ArgumentParser()
parser.add_argument('-b', '--build', action='store_true')
parser.add_argument('-r', '--run', action='store_true')
parser.add_argument('-s', '--step', type=int)

args = parser.parse_args()

if args.build:
    build(args.step)
if args.run:
    run(args.step)

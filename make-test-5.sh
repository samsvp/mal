#!/bin/bash
cd impls/zig.2 && python3 build.py -b -s 5 && cd - && env STEP=step5_tco MAL_IMPL=js ./runtest.py  --deferrable --optional   impls/tests/step4_if_fn_do.mal -- impls/zig.2/run

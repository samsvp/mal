#!/bin/bash
cd impls/rust-2 && cargo build --release --bin step6_file && cd - && env STEP=step6_file MAL_IMPL=js ./runtest.py  --deferrable --optional   impls/tests/step4_if_fn_do.mal -- impls/rust-2/run

#!/bin/bash
cd impls/rust-2 && cargo build --release --bin step5_tco && cd - && env STEP=step5_tco MAL_IMPL=js ./runtest.py  --deferrable --optional   impls/tests/step4_if_fn_do.mal -- impls/rust-2/run

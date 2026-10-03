# Notes for anyone (or any assistant) working in this repo

- All of our work lives in `choir/` (the repo owner asked that nothing outside this folder be changed).
- Reproduce everything: `matlab -batch run_all` from `choir/` (~2 min with Parallel Computing Toolbox). It runs `tests/run_tests.m` first, then writes `results/` and `docs/slides.pdf`.
- Tests only: `run('tests/run_tests.m')`.
- One scenario: `run_scenario(choir_params(), make_scenario(seed, frames, EsN0dB, faults), specs)` with `fault(...)` and `rx_spec(...)`.
- Seeds: development used 1-30 and 101-120; reported numbers use fresh seeds 301-320. Do not tune on 301+.
- Real MSL telemetry: put telemanom `labeled_anomalies.csv` and `test/*.npy` anywhere under `res/` (gitignored); otherwise a labeled synthetic stand-in is used. After adding data, rerun `run_all` and update the README numbers and its data note.
- `run_tests.m` runs in the caller's workspace and reuses names like `out` and `P`; scripts that call it should not depend on those names afterwards.

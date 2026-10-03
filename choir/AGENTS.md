# Notes for anyone (or any assistant) working in this repo

- All of our work lives in `choir/` (the repo owner asked that nothing outside this folder be changed).
- Reproduce everything: `matlab -batch run_all` from `choir/` (~2 min with Parallel Computing Toolbox). It runs `tests/run_tests.m` first, then writes `results/` and `docs/slides.pdf`.
- Tests only: `run('tests/run_tests.m')`.
- One scenario: `run_scenario(choir_params(), make_scenario(seed, frames, EsN0dB, faults), specs)` with `fault(...)` and `rx_spec(...)`.
- Seeds: development used 1-30 and 101-120; reported numbers use fresh seeds 301-320. Do not tune on 301+.
- Real MSL telemetry: put telemanom `labeled_anomalies.csv` and `test/*.npy` anywhere under `res/` (gitignored); otherwise a labeled synthetic stand-in is used. After adding data, rerun `run_all` and update the README numbers and its data note.
- README must cover what Devpost asks for: problem and approach, datasets used, how to run, results with plots, limitations and next steps. Track 1 also asks for a telemetry log plus before/after spectral plots. The rubric is autonomy 30%, technical 25%, results and evidence on real mission data 25%, communication 20%. Keep every README number in sync with `results/*.csv`.
- From the teammate's original root README, keep only the useful format: Requirements, numbered Setup, a dataset property table, Credits & License, and a project tree. RadioML is not used; do not mention it.
- `run_tests.m` runs in the caller's workspace and reuses names like `out` and `P`; scripts that call it should not depend on those names afterwards.

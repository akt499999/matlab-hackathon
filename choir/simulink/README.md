# choir_sim: Simulink wrapper around the Choir receiver

- Runs the same Choir MATLAB code as `run_all.m` (`src/channel_slot` + `src/rx_step`), one frame period (28.4 ms) per simulation step. A wrapper, not a separate implementation.
- Run in MATLAB from this folder: `build_choir_sim` (writes `choir_sim.slx`), then `run_choir_sim` (simulates, saves both PNGs, re-runs the plain MATLAB loop and prints both results).
- `ChoirStep.m` is the receiver as a System object; `choir_step_sfun.m` steps it once per frame from a Level-2 MATLAB S-Function block (the MATLAB System block needs a Java runtime, which this MATLAB lacks). Interpreted, no code generation.
- Scope **Receiver** (receiver outputs only): verified frame this step (0/1), state (1 SEARCH, 2 ALIGN, 3 DECODE, 4 FALLBACK), dishes in use.
- Scope **Scorer (truth)**: cumulative frames whose telemetry equals what was sent (`score_run`'s test). The receiver never sees it.
- Scenario: seed 301, 300 frames, 2 dB, `random_faults(301, 300, 8)`; defaults in `ChoirStep.m`.
- Checked: 275/300 frames correct (91.7%) in Simulink, same as the plain MATLAB loop and `results/faults_raw.mat` for seed 301; receiver state identical at all 301 steps.
- `choir_sim_outputs.png`: the four logged signals over time. `choir_sim_diagram.png`: the block diagram.

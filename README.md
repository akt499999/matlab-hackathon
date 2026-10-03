# Choir: Deep-Space Signal Intelligence that trusts what decodes

**MATLAB in Space Hackathon (Northeastern University, 3 October 2026) · Track 1 (Advanced): Deep-Space Communication & Signal Intelligence**

**Goal (the track's words):** find, clean and decode weak radio signals with no human tuning.

## The 60-second version

- **Problem.** A deep-space signal is too weak for one dish, so the Deep Space Network combines several (arraying). The classic way to line dishes up, JPL's SUMPLE, follows whatever the dishes agree on. When something louder reaches every dish, such as another spacecraft or a radio source in the beam, that is what they agree on.
- **What Choir does.** Choir is an autonomous 8-dish receiver written in MATLAB. It finds the carrier, lines the dishes up, decodes CCSDS telemetry frames and logs the telemetry. It recovers from dead dishes, clock glitches, carrier hops, deep fades and interference, and it logs why it made every decision.
- **The key idea.** Each dish's weight is learned only from frames that pass the checksum, carry our spacecraft ID and continue the frame count. Interference is cancelled using the current frame's samples.
- **The result.** With a look-alike spacecraft 10 dB louder than ours at every dish, Choir delivers 88.5% of frames bit-exact and SUMPLE delivers 0%. With six hidden faults per run, Choir delivers 90.6% and SUMPLE, given the same supervisor, 77.7%. Across all experiments, 0 frames were logged with wrong data.
- **The data.** The telemetry values are real NASA Curiosity (MSL) telemetry from the telemanom dataset. The 8-dish radio link that carries them is simulated in MATLAB.

![Interference results](choir/results/figures/interference.png)

## What the judges asked for, and where it is

| Requirement | Where |
|---|---|
| Problem and approach | [Problem](#1-problem), [Approach](#2-approach) |
| Datasets used | [Data](#7-data) |
| How to run | [Run it](#6-run-it): one command, `run_all` |
| Results with plots or images | [Results](#3-results), `choir/results/figures/` |
| Limitations and next steps | [Limitations](#8-limitations-and-next-steps) |
| Track 1: telemetry log | `choir/results/telemetry_log_seed301.csv`; plot `choir/results/figures/telemetry.png` |
| Track 1: before/after spectral plots | `choir/results/figures/spectra.png` |
| Autonomy: drift, dropouts, component failures, no human input | [Autonomy](#4-autonomy), `choir/results/decision_log_seed301.csv` |
| Real mission data | NASA MSL telemetry (telemanom), [Data](#7-data) |
| Slide deck | [`choir/docs/slides.pdf`](choir/docs/slides.pdf) |

## 1. Problem

- **Weak signals.** At the per-dish signal level used here (mean Es/N0 of 2 dB), no single dish can decode an uncoded frame. Eight dishes together can.
- **Lining the dishes up.** The dishes must be aligned in time and phase without knowing the data.
- **Interference.** Blind alignment can be captured by anything louder that reaches every dish.
- **Scarce antenna time.** NASA's Deep Space Network is oversubscribed by up to 40% at times (NASA OIG, 2023), and nobody can hand-tune a receiver 20 light-minutes away.

## 2. Approach

```
telemetry (NASA MSL) -> CCSDS-style frames + CRC-16 -> ccsdsTMWaveformGenerator (BPSK)
  -> [hidden] 8 dishes: own SNR, delay, drift + seeded faults + interferers
  -> Choir: SEARCH -> ALIGN -> DECODE -> FALLBACK -> SEARCH ... -> telemetry log
  -> independent scorer compares the log with what was sent
```

| Stage | What MATLAB does |
|---|---|
| SEARCH | Squares the BPSK signal so the carrier shows up as a tone, sums the spectra over the dishes, and interpolates the peak |
| ALIGN | Searches for the sync marker over one frame period on every dish to find the frame timing and each dish's delay; rejects frames with another spacecraft's ID |
| DECODE | Weights `w = Q⁻¹h`. `h` comes only from verified frames (1,816 known symbols each); `Q` is the frame covariance minus the spacecraft's own part, floored at the noise level |
| Dish health | A dish that stops matching verified frames sits out, then is re-timed (±16 samples) or excluded, and is probed until it returns |
| FALLBACK | After 3 bad frames: re-time every dish on the sync marker and use equal weights. After 8: go back to a full carrier search |

### Why these choices

- **The real CCSDS frame structure.** It makes the look-alike test honest: real spacecraft share the sync marker and send valid CRCs, so the spacecraft-ID check matters.
- **Verified frames give 17.5 dB more averaging than the sync marker alone** (1,816 symbols vs 32). The "sync-marker only" baseline uses Choir's math but learns from the 32 known bits. It isolates the difference: 7.3% vs Choir's 87.8% against a +20 dB look-alike.
- **Subtracting the spacecraft's own part from the covariance.** Without it, our first version partly cancelled the spacecraft at high SNR, a known effect when `h` is slightly off.
- **A fair comparison.** Every receiver sees identical samples and shares the same front end and supervisor. Without interference, SUMPLE and equal gain match the bound to within a few frames; this is checked automatically in the tests.
- **No deep learning.** The combining and decoding math is known and close to optimal, and there was no training data for a network.

## 3. Results

All numbers come from `choir/run_all.m`:
- **Development** used seeds 1–30 and 101–120.
- **Reported results** come from fresh seeds 301–320, run after the receiver was frozen. Later edits changed only log messages and figure labels, and the numbers did not change.
- **Intervals** in the figures are 95% Clopper–Pearson.

| 8 dishes, mean 2 dB per dish | Choir | SUMPLE | Equal gain | Sync-marker only | Bound* |
|---|---|---|---|---|---|
| Look-alike spacecraft +10 dB | **88.5%** | 0.0% | 0.0% | 85.0% | 90.3% |
| Look-alike spacecraft +20 dB | **87.8%** | 0.0% | 0.0% | 7.3% | 89.8% |
| Wide-band source +10 dB | **99.8%** | 0.8% | 15.0% | 98.5% | 99.8% |
| Wide-band source +20 dB | **98.3%** | 0.0% | 0.0% | 72.0% | 99.8% |
| Wrong frames logged | **0** | 0 | 0 | 0 | 0 |

\* The bound knows the transmitted bits of every frame. It is a reference, not a receiver. The best single dish gets 0% in every row, because at 2 dB one dish cannot decode.

**Before/after spectra** (the required Track 1 plots):
- **No interference:** eight dishes lift the signal about 10 dB above the noise, versus about 3 dB for one dish.
- **Wide-band source at +10 dB:** it raises one dish's noise floor to 7.7 dB. SUMPLE amplifies it to 16 dB; Choir brings the floor back to 0.1 dB.

![Spectra](choir/results/figures/spectra.png)

**No interference.** One dish needs about 8 dB per dish; eight dishes decode 100% of frames at 2 dB each.

![SNR sweep](choir/results/figures/snr.png)

**Where Choir loses (measured)**
- **A look-alike arriving almost the same way as our spacecraft.** In one geometry (seed 304), the two signals' patterns across the dishes have a similarity of 0.81; in the other nine geometries it is 0.16–0.58. Every receiver fails there, including the bound. That geometry is why the look-alike rows are near 89% rather than 100%.
- **No interference and a very weak signal.** Choir is no better than SUMPLE: 27.8% vs 32.6% at −2 dB. Its advantage is robustness, not sensitivity.

## 4. Autonomy

Twenty runs of 300 frames (8.5 s) each. Every run hides six faults at random times and dishes, and the receiver is never told:
- a dead dish
- a clock glitch
- a look-alike spacecraft at +10 dB
- a carrier hop of ±0.5–3 kHz
- a −30 dB fade of every dish
- a dish with 10× noise

| Receiver | Frames correct | Worst run | Back after carrier hop | Through the look-alike |
|---|---|---|---|---|
| **Choir** | **90.6%** | 80.7% | 284 ms | no interruption |
| SUMPLE + same supervisor | 77.7% | 70.0% | 284 ms | lost the whole 0.85 s window |
| Equal gain + same supervisor | 77.3% | 70.7% | 284 ms | lost the whole 0.85 s window |
| Choir, supervisor off | 40.0% | 7.7% | never | recovered in only 55% of runs |

Dead dishes, clock glitches and the noisy dish cause no interruption for Choir. The full table is in `choir/results/faults_recovery.csv`.

![Timeline](choir/results/figures/timeline.png)

**From the decision log** (`choir/results/decision_log_seed301.csv`; the truth is in `hidden_faults_seed301.csv`). Every hidden fault was logged within 2 frames (57 ms):
```
 0.795 s  interference     a strong extra source reaches 8 dishes (21 dB over noise); weights now cancel it
 2.213 s  dish down        dish 2 stopped matching verified frames (fit 0.80 -> 0.01) and was not found nearby: excluded
 3.632 s  dish back        probe found dish 2 again (fit 0.83, timing +0 samples): re-included
 4.937 s  lost             8 bad frames in a row: full carrier re-search
 5.987 s  dish re-aligned  dish 1 stopped matching verified frames; timing moved -12 samples
 7.406 s  carrier found    +1440.5 Hz (the hidden hop was +1363 Hz on top of about 75 Hz of offset and drift)
```

**Telemetry log.** These are real MSL values, logged only from verified frames. The gaps are frames the receiver refused to log.

![Telemetry](choir/results/figures/telemetry.png)

## 5. More in this repo

- **Simulink** (`choir/simulink/`). The same receiver runs inside Simulink: a Level-2 MATLAB S-Function steps `rx_step` once per frame. It delivered 275 of 300 frames for seed 301, matching the MATLAB run. To try it, run `build_choir_sim` and then `run_choir_sim`.
- **Swarm receivers** (`choir/swarm/`, an add-on). Several receivers search the carrier frequency, phase, timing and gain together (a particle swarm), using a known training message.
  - In its three reported runs it learned each carrier offset to within 0.6 Hz.
  - It decoded two messages with 0 bit errors. The third, at 4 dB, had 3 of 160 bits wrong, near the BPSK noise limit.
  - It runs in plain MATLAB; see `choir/swarm/README.md`.
- **Hardware demo** (shown live, Raspberry Pi Pico).
  - Three LEDs take turns sending the same Morse frame to one photoresistor: a sync pulse, ID C, a counter, MATLAB, and a checksum.
  - Each round, a hidden fault garbles one LED, corrupts its payload, or puts a look-alike frame (ID Q) on 2 of 3 LEDs.
  - A majority vote trusts what the LEDs agree on; Choir's rule trusts only frames that pass the checksum, carry ID C and move the counter forward. A look-alike on 2 of 3 LEDs is built to win the vote and fail Choir's ID check.
  - Light adds as brightness, so this illustrates the trust rule, not radio combining.
- **Slides and explainer.**
  - `choir/docs/slides.pdf` holds the slides; every number in them is read from `choir/deck/numbers.json`, which `choir/deck/make_figs.m` builds from the results files.
  - `choir/docs/choir-explainer.html` is an animated, offline explainer with illustrative visuals.

## 6. Run it

**Requirements**
- MATLAB R2026b with Communications, Satellite Communications, Signal Processing, DSP System, and Statistics and Machine Learning Toolboxes.
- Optional: Parallel Computing Toolbox. With it, the full run takes about 2 minutes on a 12-core laptop; without it, everything runs serially.

**Setup**
1. Download the telemanom dataset zip from Kaggle (`patrickfleith/nasa-anomaly-detection-dataset-smap-msl`, about 86 MB).
2. Extract `labeled_anomalies.csv` and `data/data/test/*.npy` anywhere under `choir/res/`. That folder is not committed.
3. From `choir/`, run:
   ```matlab
   run_all          % or: matlab -batch run_all
   ```
   It runs `tests/run_tests.m` first (7 checks), then writes every CSV and figure to `choir/results/`.

Without the dataset, a clearly labeled synthetic stand-in is used, so the code still runs.

**Tests** (`choir/tests/run_tests.m`):
- The CRC reproduces the CRC-16/CCITT-FALSE check value 0x29B1.
- Frames survive a pack/parse round trip, and one flipped bit is rejected.
- Measured BER is 0.0118 against the BPSK theory value of 0.0125 at 4 dB.
- A clean loopback is exact.
- Pure noise produces 0 logged frames.
- The baselines are fair without interference.
- Only the analysis bound can receive the true bits.

## 7. Data

| Property | Value |
|---|---|
| Dataset | telemanom: NASA SMAP and Curiosity (MSL) telemetry with labeled anomalies |
| Used here | MSL test-set channels, first column (the telemetry value), streamed in label-file order (M-6, M-1, M-2, S-2, P-10, ...) |
| Values | Pre-scaled to (−1, 1) by the dataset authors, with anonymized channel names, so no physical units are claimed. Quantized to int16 for framing |
| Format | One `.npy` file per channel, read with a small MATLAB `.npy` reader (`choir/src/telemetry_source.m`) |
| Source | Hundman et al., KDD 2018; https://github.com/khundman/telemanom; Kaggle mirror `patrickfleith/nasa-anomaly-detection-dataset-smap-msl` |
| License | The telemanom repository is © 2018 Caltech/JPL under a BSD-style license. We do not redistribute the data |
| Not real | The radio link (dishes, noise, faults, interferers) is simulated; no multi-dish recording was available |

## 8. Limitations and next steps

- **The RF link is simulated.** Next: real multi-station recordings, such as several SatNOGS stations on one pass.
- **Uncoded BPSK.** Turbo or LDPC codes would shift every curve several dB to the left without changing the receiver logic.
- **Interferer direction.**
  - Interferers are modeled near the spacecraft's direction, so they share each dish's residual delay.
  - An interferer far off-axis would need several taps per dish.
  - One arriving exactly the same way cannot be separated by any dish weighting.
- **Choir needs verified frames to learn trust.** Interference that is present before any frame verifies is its weak case.
- **Spoofing.** The checksum guards against noise, not a deliberate spoofer; that would need authenticated frames, such as CCSDS SDLS.
- **Not built yet:**
  - Elastic arraying (releasing dishes when the margin allows); the explainer shows it as a planned next step.
  - A Stateflow version of the supervisor.

## 9. Prior work and what is ours

- **Prior work.**
  - Arraying is decades old in the Deep Space Network.
  - SUMPLE is Rogstad, IPN Progress Report 42-162 (2005).
  - JPL modified SUMPLE for wide-band interferers in the beam (NASA Tech Brief NPO-45640) and studied arrays with interfering sources (IPN PR 42-150).
  - Weighting antennas by known or decoded data is standard in wireless engineering.
- **Ours.**
  - A receiver that runs itself and trusts only verified frames: checksum, spacecraft ID and frame count.
  - It cancels interference from the current frame's statistics, recovers without help, and explains each decision.
  - It is measured on identical samples against SUMPLE, equal gain, a sync-marker-only version and a bound, including a look-alike spacecraft that the published bandwidth-based fix does not target.

## 10. Credits and license

- **Data:** NASA/JPL SMAP and MSL telemetry via telemanom (Hundman, Constantinou, Laporte, Colwell and Soderstrom, KDD 2018).
- **References:**
  - Rogstad, *The SUMPLE Algorithm for Aligning Arrays of Receiving Radio Antennas*, IPN PR 42-162 (2005).
  - NASA Tech Brief NPO-45640, *Aligning a Receiving Antenna Array to Reduce Interference*.
  - *Large-Array Signal Processing for Deep-Space Applications*, IPN PR 42-150.
  - NASA OIG, *Audit of NASA's Deep Space Network*, IG-23-016 (2023).
- **Tools:**
  - MATLAB R2026b and `ccsdsTMWaveformGenerator` (Satellite Communications Toolbox).
  - Communications, Signal Processing, DSP System, Statistics and Machine Learning, and Parallel Computing Toolboxes; Simulink.
- **AI assistance:** the code was written with AI assistance (Devin) during the hackathon, and reviewed and run by the team.

## Project structure

```
choir/
├── run_all.m              reproduces every number and figure (runs the tests first)
├── src/                   the receiver and the simulation
│   ├── choir_params.m     all settings, fixed before evaluation
│   ├── frame_pack.m / frame_parse.m     CCSDS-style frames + CRC-16
│   ├── tx_build.m         ccsdsTMWaveformGenerator transmitter
│   ├── channel_make.m / channel_slot.m  hidden truth: dishes, faults, interferers
│   ├── rx_init.m / rx_step.m            the receiver and its supervisor
│   ├── score_run.m        independent scorer
│   ├── exp_*.m            experiments and figures
│   └── telemetry_source.m MSL loader (.npy) with a labeled synthetic fallback
├── tests/run_tests.m      checks that the claims depend on
├── results/               CSVs, decision and telemetry logs, figures
├── simulink/              the same receiver stepped inside Simulink
├── swarm/                 add-on: swarm receivers that learn channel settings together
├── deck/                  slide sources: make_figs.m, numbers.json, deck.html, figures
├── docs/                  slides.pdf, choir-explainer.html
└── res/                   telemanom data (not committed)
```

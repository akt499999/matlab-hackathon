# Choir: Deep-Space Signal Intelligence that trusts what decodes

**MATLAB in Space Hackathon · Track 1 (Advanced): Deep-Space Communication & Signal Intelligence**

**Goal (the track's words):** find, clean and decode weak radio signals with no human tuning.

## The 60-second version

- **Problem.** A deep-space signal is too weak for one dish, so the Deep Space Network combines several (arraying). The classic way to line the dishes up, JPL's SUMPLE, follows whatever the dishes agree on. When something louder reaches every dish, such as another spacecraft or a radio source in the beam, that is what they agree on.
- **What Choir does.** It is an autonomous 8-dish receiver in MATLAB. It finds the carrier, lines the dishes up, decodes CCSDS telemetry frames and logs the telemetry. It recovers from dead dishes, clock glitches, carrier hops, deep fades and interference, and logs why it made every decision.
- **The key idea.** Each dish's weight is learned only from frames that pass the checksum, carry our spacecraft ID and continue the frame count. Interference is cancelled from the current frame's samples.
- **The result.** With a look-alike spacecraft 10 dB louder than ours at every dish, Choir delivers 88.5% of frames bit-exact; SUMPLE delivers 0%. With six hidden faults per run, Choir delivers 90.6% (SUMPLE with the same supervisor: 77.7%). Wrong frames logged across all experiments: 0.
- **The data.** The telemetry values are real NASA Curiosity (MSL) telemetry from the telemanom dataset. The 8-dish radio link that carries them is simulated in MATLAB.

![Interference results](results/figures/interference.png)

## What the judges asked for, and where it is

| Requirement | Where |
|---|---|
| Problem and approach | [Problem](#1-problem), [Approach](#2-approach) |
| Datasets used | [Data](#6-data) |
| How to run | [Run it](#5-run-it): one command, `run_all` |
| Results with plots or images | [Results](#3-results), `results/figures/` |
| Limitations and next steps | [Limitations](#7-limitations-and-next-steps) |
| Track 1: telemetry log | `results/telemetry_log_seed301.csv`; plot `results/figures/telemetry.png` |
| Track 1: before/after spectral plots | `results/figures/spectra.png` |
| Autonomy: drift, dropouts, component failures, no human input | [Autonomy](#4-autonomy), `results/decision_log_seed301.csv` |
| Real mission data | NASA MSL telemetry (telemanom), [Data](#6-data) |
| Slide deck | `docs/slides.pdf` |

## 1. Problem

- **Weak signals.** At the per-dish signal levels used here (mean Es/N0 of 2 dB), no single dish can decode an uncoded frame. Eight dishes together can.
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
| SEARCH | Squares the BPSK signal so the carrier shows up as a tone, sums the spectra over dishes, and interpolates the peak |
| ALIGN | Searches for the sync marker over one frame period on every dish to get frame timing and per-dish delay; rejects frames with another spacecraft's ID |
| DECODE | Weights `w = Q⁻¹h`: `h` comes only from verified frames (1,816 known symbols each); `Q` is the frame covariance minus the spacecraft's own part, floored at the noise level |
| Dish health | A dish that stops matching verified frames sits out, is re-timed (±16 samples) or excluded, and is probed until it returns |
| FALLBACK | After 3 bad frames: re-time every dish on the sync marker, equal weights. After 8: full carrier re-search |

**Why these choices**
- **The real CCSDS frame structure.** It makes the look-alike test honest: real spacecraft share the sync marker and send valid CRCs, so the spacecraft-ID check matters.
- **Verified frames give 17.5 dB more averaging than the sync marker alone** (1,816 symbols vs 32). The "sync-marker only" baseline isolates that: 7.3% vs Choir's 87.8% against a +20 dB look-alike.
- **Subtracting the spacecraft's own part from the covariance.** Without it, our first version partly cancelled the spacecraft at high SNR.
- **No deep learning.** The combining and decoding math is known and near-optimal, and there was no training data for a network.

## 3. Results

All numbers come from `run_all`. Development used seeds 1–30 and 101–120. Results are from fresh seeds 301–320, run after the receiver was frozen. Every receiver sees identical samples and shares the supervisor; only the dish weights differ.

| 8 dishes, mean 2 dB per dish | Choir | SUMPLE | Equal gain | Sync-marker only | Bound* |
|---|---|---|---|---|---|
| Look-alike spacecraft +10 dB | **88.5%** | 0.0% | 0.0% | 85.0% | 90.3% |
| Look-alike spacecraft +20 dB | **87.8%** | 0.0% | 0.0% | 7.3% | 89.8% |
| Wide-band source +10 dB | **99.8%** | 0.8% | 15.0% | 98.5% | 99.8% |
| Wide-band source +20 dB | **98.3%** | 0.0% | 0.0% | 72.0% | 99.8% |
| Wrong frames logged | **0** | 0 | 0 | 0 | 0 |

\* The bound knows the transmitted bits of every frame. It is a reference, not a receiver. The best single dish gets 0% in every row: at 2 dB one dish cannot decode.

**Before/after spectra.** These are the required Track 1 plots.
- Left: eight dishes lift the signal about 10 dB above the noise, versus about 3 dB for one dish.
- Right: a wide-band source raises one dish's noise floor. SUMPLE amplifies it; Choir cancels it.

![Spectra](results/figures/spectra.png)

**No interference.** One dish needs about 8 dB; eight dishes decode 100% at 2 dB each.

![SNR sweep](results/figures/snr.png)

**Where Choir loses (measured)**
- **A look-alike arriving almost the same way as our spacecraft.** In one geometry (seed 304) the two signals' patterns across the dishes have a similarity of 0.81, against 0.16–0.58 in the other nine geometries. Every receiver fails there, including the bound. That geometry is why the look-alike rows are near 89% rather than 100%.
- **No interference and a very weak signal.** Choir is no better than SUMPLE: 27.8% vs 32.6% at −2 dB. Its advantage is robustness, not sensitivity.

## 4. Autonomy

Twenty runs of 300 frames (8.5 s) each. Every run hides six faults at random times and dishes: a dead dish, a clock glitch, a look-alike spacecraft at +10 dB, a carrier hop of ±0.5–3 kHz, a −30 dB fade of every dish, and a dish with 10× noise. The receiver is never told.

| Receiver | Frames correct | Worst run | Back after carrier hop | Through the look-alike |
|---|---|---|---|---|
| **Choir** | **90.6%** | 80.7% | 284 ms | no interruption |
| SUMPLE + same supervisor | 77.7% | 70.0% | 284 ms | lost the whole 0.85 s window |
| Equal gain + same supervisor | 77.3% | 70.7% | 284 ms | lost the whole 0.85 s window |
| Choir, supervisor off | 40.0% | 7.7% | never | recovered in only 55% of runs |

Dead dishes, clock glitches and the noisy dish cause no interruption for Choir. Full table: `results/faults_recovery.csv`.

![Timeline](results/figures/timeline.png)

**From the decision log** (`results/decision_log_seed301.csv`; the truth is in `hidden_faults_seed301.csv`):
```
 0.795 s  interference     a strong extra source reaches 8 dishes (21 dB over noise); weights now cancel it
 2.213 s  dish down        dish 2 stopped matching verified frames (fit 0.80 -> 0.01) and was not found nearby: excluded
 3.632 s  dish back        probe found dish 2 again (fit 0.83, timing +0 samples): re-included
 4.937 s  lost             8 bad frames in a row: full carrier re-search
 5.987 s  dish re-aligned  dish 1 stopped matching verified frames; timing moved -12 samples
 7.406 s  carrier found    +1440.5 Hz (the hidden hop was +1363 Hz on top of about 75 Hz of offset and drift)
```

**Telemetry log.** Real MSL values, logged only from verified frames. The gaps are frames the receiver refused to log.

![Telemetry](results/figures/telemetry.png)

## 5. Run it

**Requirements**
- MATLAB R2026b with Communications, Satellite Communications, Signal Processing, DSP System, and Statistics and Machine Learning Toolboxes.
- Optional: Parallel Computing Toolbox (about 2 minutes on a 12-core laptop; without it, everything runs serially).

**Setup**
1. Download the telemanom dataset zip from Kaggle (`patrickfleith/nasa-anomaly-detection-dataset-smap-msl`, about 86 MB).
2. Extract `labeled_anomalies.csv` and `data/data/test/*.npy` anywhere under `choir/res/`. That folder is not committed.
3. From `choir/`, run:
   ```matlab
   run_all          % or: matlab -batch run_all
   ```
   It runs `tests/run_tests.m` first (7 checks), then writes every CSV and figure to `results/` and the slides to `docs/slides.pdf`.

Without the dataset, a clearly labeled synthetic stand-in is used, so the code still runs.

## 6. Data

| Property | Value |
|---|---|
| Dataset | telemanom: NASA SMAP and Curiosity (MSL) telemetry with labeled anomalies |
| Used here | MSL test-set channels, first column (the telemetry value), streamed in label-file order (M-6, M-1, M-2, S-2, P-10, ...) |
| Values | pre-scaled to (−1, 1) by the dataset authors; channel names anonymized, so no physical units are claimed; quantized to int16 for framing |
| Format | one `.npy` per channel; read with a small MATLAB `.npy` reader (`src/telemetry_source.m`) |
| Source | Hundman et al., KDD 2018; https://github.com/khundman/telemanom; Kaggle mirror `patrickfleith/nasa-anomaly-detection-dataset-smap-msl` |
| License | telemanom repository © 2018 Caltech/JPL, BSD-style license. We do not redistribute the data. |
| Not real | the radio link (dishes, noise, faults, interferers) is simulated; no multi-dish recording was available |

## 7. Limitations and next steps

- **The RF link is simulated.** Next: real multi-station recordings, such as several SatNOGS stations on one pass.
- **Uncoded BPSK.** Turbo or LDPC codes would shift every curve several dB to the left without changing the receiver logic.
- **Interferer direction.**
  - Interferers are modeled near the spacecraft's direction, sharing each dish's residual delay.
  - A far off-axis one would need several taps per dish.
  - One arriving exactly the same way cannot be separated by any dish weighting.
- **Choir needs verified frames to learn trust.** Interference present before any frame verifies is its weak case.
- **The checksum guards against noise, not a deliberate spoofer.** That would need authenticated frames, such as CCSDS SDLS.
- **Not built yet:** elastic arraying (releasing dishes when the margin allows) and a Stateflow version of the supervisor.

## 8. Prior work and what is ours

- **Prior work.**
  - Arraying is decades old in the Deep Space Network.
  - SUMPLE is Rogstad, IPN Progress Report 42-162 (2005).
  - JPL modified SUMPLE for wide-band interferers in the beam (NASA Tech Brief NPO-45640) and studied arrays with interfering sources (IPN PR 42-150).
  - Weighting antennas by known or decoded data is standard in wireless engineering.
- **Ours.**
  - A receiver that runs itself and trusts only verified frames (checksum, spacecraft ID and frame count).
  - It cancels interference from the current frame's statistics, recovers without help and explains each decision.
  - It is measured on identical samples against SUMPLE, equal gain, a sync-marker-only version and a bound, including a look-alike spacecraft that the published bandwidth-based fix does not target.

## 9. Credits and license

- **Data:** NASA/JPL SMAP and MSL telemetry via telemanom (Hundman, Constantinou, Laporte, Colwell, Soderstrom, KDD 2018).
- **References:**
  - Rogstad, IPN PR 42-162 (2005)
  - NASA Tech Brief NPO-45640
  - IPN PR 42-150
  - NASA OIG IG-23-016 (2023)
- **Tools:** MATLAB R2026b; `ccsdsTMWaveformGenerator` (Satellite Communications Toolbox); Communications, Signal Processing, DSP System, Statistics and Machine Learning, and Parallel Computing Toolboxes.
- **AI assistance:** the code was written with AI assistance (Devin) during the hackathon, and reviewed and run by the team.
- **Explainer:** `docs/choir-explainer.html` is an animated explainer. Its visuals are illustrative; the measured numbers are the ones above.

## Project structure

```
choir/
├── run_all.m              reproduces every number, figure and the slides
├── src/
│   ├── choir_params.m     all settings, fixed before evaluation
│   ├── frame_pack.m / frame_parse.m     CCSDS-style frames + CRC-16
│   ├── tx_build.m         ccsdsTMWaveformGenerator transmitter
│   ├── channel_make.m / channel_slot.m  hidden truth: dishes, faults, interferers
│   ├── rx_init.m / rx_step.m            the receiver and its supervisor
│   ├── score_run.m        independent scorer
│   ├── exp_*.m            experiments and figures
│   ├── make_slides.m      builds docs/slides.pdf from results/*.csv
│   └── telemetry_source.m MSL loader (.npy) with a labeled synthetic fallback
├── tests/run_tests.m      checks that the claims depend on
├── results/               CSVs, decision and telemetry logs, figures
├── docs/                  slides.pdf, choir-explainer.html
└── res/                   telemanom data (not committed)
```

# Choir: an antenna array that trusts what decodes

**MATLAB in Space Hackathon (Northeastern, Oct 3 2026) · Track 1: Deep-Space Communication & Signal Intelligence**

Choir is an autonomous receiver for one weak spacecraft signal heard by eight dishes. With no human tuning it finds the carrier, lines the dishes up, decodes CCSDS telemetry frames and writes a telemetry log. It keeps going through dead dishes, clock glitches, carrier frequency hops, deep fades and interference, and it logs the reason for every decision.

**The key idea:** the receiver decides how much to trust each dish only from frames that pass the checksum, carry our spacecraft ID and continue the frame count. The usual blind way to line dishes up (JPL's SUMPLE: each dish is compared with the sum of the others) follows whatever the dishes agree on. When something louder reaches every dish, such as another spacecraft in the beam, that is what they agree on.

> **Data honesty.** The telemetry values are real: NASA Curiosity (MSL) channels from the telemanom test set, pre-scaled to (−1, 1) and with anonymized channel names (see [Data](#data)). The radio link that carries them (8 dishes, noise, faults, interferers) is simulated in MATLAB; no real multi-dish recording was available.

## Results at a glance

All numbers come from `run_all.m`. Development used seeds 1–30 and 101–120. The receiver was then frozen and evaluated on fresh seeds 301–320; later edits changed only log messages and figure labels, and the numbers did not change. The spectra figure uses seeds 201–202. Figures show 95% Clopper–Pearson intervals.

| Test (8 dishes, mean 2 dB Es/N0 per dish) | Choir | SUMPLE (blind) | Equal gain | Sync-marker only | Bound* |
|---|---|---|---|---|---|
| Look-alike spacecraft, +10 dB per dish | **88.5%** | 0.0% | 0.0% | 85.0% | 90.2% |
| Look-alike spacecraft, +20 dB per dish | **87.8%** | 0.0% | 0.0% | 7.2% | 89.8% |
| Wide-band source, +10 dB per dish | **99.8%** | 0.8% | 15.0% | 98.5% | 99.8% |
| Wide-band source, +20 dB per dish | **98.2%** | 0.0% | 0.0% | 72.0% | 99.8% |
| Six hidden faults per run, 20 runs | **90.6%** | 77.7%† | 77.3%† | n/a | n/a |
| Frames logged with wrong telemetry, all experiments | **0** | 0 | 0 | 0 | 0 |

\* The bound learns from the true bits of every frame. It is a reference, not a receiver.
† With the same supervisor as Choir; only the weights differ. With the supervisor switched off, Choir gets 40.0%.

Percentages are telemetry frames delivered bit-exact. The best single dish gets 0% in every interference test: at 2 dB a single uncoded dish cannot decode, which is why arrays exist.

![Interference results](results/figures/interference.png)

**Where Choir loses (measured):**
- **A look-alike from the same direction.** One of the 10 interference geometries (seed 304) puts the look-alike's signature across the dishes at a similarity of 0.81 with ours; the other nine range from 0.16 to 0.58. Every receiver fails there, including the bound. That geometry is the main reason Choir's look-alike rows sit near 89% instead of near 100%; seed 305, at a similarity of 0.58, also loses a few frames. No dish weighting can separate two signals that arrive the same way.
- **No interference and a very weak signal.** Choir is no better than the classic methods. At −2 dB per dish SUMPLE delivers 32.6% and Choir 27.8%; at 0 dB they are 95.2% and 93.6%. Choir's advantage is robustness, not raw sensitivity.

## What happens in MATLAB

1. **Telemetry → frames** (`frame_pack.m`). Each frame is a 223-byte CCSDS-style transfer frame:
   - a 6-byte primary header: version, spacecraft ID 42, frame counters
   - a channel byte
   - 107 big-endian int16 telemetry samples
   - a CRC-16 (x¹⁶+x¹²+x⁵+1, register preset to ones; the 0x29B1 check value is verified in the tests)
2. **Waveform** (`tx_build.m`). `ccsdsTMWaveformGenerator` from Satellite Communications Toolbox adds the attached sync marker 0x1ACFFC1D and the CCSDS randomizer, then produces BPSK with root-raised-cosine shaping (roll-off 0.35) at 4 samples per symbol and 64 ksymbols/s.
3. **Hidden channel** (`channel_make.m`, `channel_slot.m`). This is the truth the receiver never sees.
   - 8 dishes, each with its own SNR (±3 dB around the run's mean), residual delay and slow phase drift, plus a slowly drifting carrier.
   - Faults on a seeded schedule: a dead dish, a clock glitch (timing jump), a carrier hop, a deep fade of all dishes, and a dish whose noise rises 10×.
   - Two interferers in the same band. One is a look-alike CCSDS spacecraft: same format, ID 21, 150 Hz away. The other is a wide-band point source, like a radio source near the line of sight.
4. **Receiver** (`rx_step.m`): a state machine. All receivers share it; only the dish weights differ.
   - **SEARCH**: squaring BPSK leaves a tone at twice the carrier offset. The receiver sums spectra over the dishes and interpolates the peak.
   - **ALIGN**: a sync-marker search over one full frame period on every dish gives the frame timing and each dish's delay. Up to 3 candidates are trial-decoded. A valid frame with another spacecraft ID is rejected, and that carrier is excluded from the next search.
   - **DECODE**: the weights are `w = Q⁻¹h`.
     - `h`, the spacecraft's signature across the dishes, is learned only from verified frames. Each verified frame is re-modulated into 1,816 known symbols.
     - `Q` is the frame's covariance minus the spacecraft's own part `h hᴴ`, floored at the noise level. A new interferer is therefore cancelled from the current frame's samples, without waiting for a verified frame.
     - The carrier is fine-tracked from the phase change between consecutive verified frames.
   - **Dish health**:
     - A dish whose sync-marker match collapses sits out the current frame.
     - It is then re-timed against the full verified frame (±16 samples).
     - If it is not found nearby, it is excluded and probed every 25 frames until it returns.
   - **FALLBACK**: after 3 bad frames, every dish is re-timed on the sync marker and given equal weights. After 8 bad frames, the receiver goes back to a full carrier search.
   - The receiver also logs what its weights are reacting to: an extra source reaching many dishes (interference), or one noisy dish.
5. **Scorer** (`score_run.m`). A logged frame counts as correct only if its telemetry equals the transmitted frame bit for bit. Anything else that gets logged is a false accept.

### Why these design choices

- **A standard waveform instead of a toy.** Testing against the CCSDS frame structure (sync marker, randomizer, spacecraft ID, frame count) is what makes the look-alike test meaningful. Real spacecraft share the sync marker and each sends valid CRCs.
- **Trust verified frames, not agreement.**
  - A verified frame provides 1,816 known symbols. The sync marker provides 32. That is 10·log₁₀(1816/32) ≈ 17.5 dB more averaging.
  - Interference cannot produce a verified frame by accident.
  - The spacecraft-ID check is essential: a look-alike's frames pass their own CRC.
  - "Sync-marker only" uses Choir's exact math but learns `h` from the 32 known bits. The gap between it and Choir (7.2% vs 87.8% at +20 dB) is what verification adds. Part of the reason: a look-alike repeats the same sync marker and nearly the same header in every frame, so it biases a sync-marker estimate in the same way every time.
- **Covariance minus the spacecraft's own part.** Our first version used the plain frame covariance, `w = R⁻¹h`. At high SNR it partly cancelled the spacecraft, a known effect when `h` is slightly off. Subtracting `h hᴴ` and flooring at the noise level fixed it.
- **A fair comparison.**
  - Every receiver sees identical samples and shares the front end and the supervisor.
  - With no interference, SUMPLE and equal gain match the bound within a few frames; this is checked automatically in the tests.
  - Our SUMPLE implementation follows the idea in Rogstad (2005): each dish is correlated with the sum of the others, normalized, with 3 iterations per frame, warm-started.
- **No deep learning.** The combining and decoding math is known and close to optimal. A network would need training data we do not have, and it would be harder to justify to anyone checking the receiver.

## Results in detail

### 1. Interference (the main result)
Figure above; data in `results/interference_summary.csv`, and per run in `interference_runs.csv`. The interferer switches on at frame 20, after lock, and stays on; frames 21–60 are scored. There are 10 seeds × 40 frames per point.

### 2. No interference: eight dishes vs one
![SNR sweep](results/figures/snr.png)

- **Best single dish:** about 8 dB per dish is needed (99.6% at 8 dB, 15.2% at 4 dB).
- **Eight dishes:** every array method delivers 100% at a mean of 2 dB per dish.
- **Data:** `results/snr_summary.csv`.

### 3. Autonomy: six hidden faults per run, no human input
Each of 20 runs (300 frames, 8.5 s) contains a dead dish, a clock glitch, a look-alike spacecraft at +10 dB, a carrier hop of ±0.5–3 kHz, a deep fade of every dish (−30 dB) and a dish with 10× noise. Times and dishes are random per seed (`random_faults.m`).

![Timeline](results/figures/timeline.png)

| Receiver | Frames correct (mean) | Worst run | False accepts | ms per frame* |
|---|---|---|---|---|
| **Choir** | **90.6%** | 80.7% | 0 | 4.5 |
| SUMPLE + same supervisor | 77.7% | 70.0% | 0 | 6.0 |
| Equal gain + same supervisor | 77.3% | 70.7% | 0 | 5.3 |
| Choir, supervisor off | 40.0% | 7.7% | 0 | 3.6 |

\* Median processing time per frame in this run. It varies with machine load.

Median time to five good frames in a row after each fault starts (after a fade, measured from when it ends). Zero means no interruption.

| Receiver | Dead dish | Clock glitch | Look-alike +10 dB | Carrier hop | Deep fade | Noisy dish |
|---|---|---|---|---|---|---|
| **Choir** | 0 ms | 0 ms | 0 ms | 284 ms | 0 ms | 0 ms |
| SUMPLE + same supervisor | 0 ms | 0 ms | 908 ms (lost the whole interference window) | 284 ms | 0 ms | 114 ms |
| Equal gain + same supervisor | 0 ms | 0 ms | 908 ms | 284 ms | 0 ms | 411 ms |
| Choir, supervisor off | | | | never recovers | | |

A frame lasts 28.4 ms. Choir processes one frame in about 4–5 ms in MATLAB on a laptop, several times faster than real time. Data: `results/faults_summary.csv`, `faults_recovery.csv`.

**Decision log excerpt** (`results/decision_log_seed301.csv`; hidden truth in `hidden_faults_seed301.csv`):

```
time_s  state     event            reason
 0.795  DECODE    interference     a strong extra source reaches 8 dishes (21 dB over noise); weights now cancel it
 1.703  DECODE    all clear        no extra source above 3 dB
 2.213  DECODE    dish down        dish 2 stopped matching verified frames (fit 0.80 -> 0.01) and was not found nearby: excluded
 3.632  DECODE    dish back        probe found dish 2 again (fit 0.83, timing +0 samples): re-included
 4.795  FALLBACK  safe mode        3 bad frames in a row: re-aligned every dish on the sync marker, equal weights
 4.937  FALLBACK  lost             8 bad frames in a row: full carrier re-search
 5.051  SEARCH    carrier found    +64.4 Hz (spectral peak/median 197)
 5.987  DECODE    dish re-aligned  dish 1 stopped matching verified frames (fit 0.75 -> 0.21); timing moved -12 samples, fit now 0.55
 7.406  SEARCH    carrier found    +1440.5 Hz (spectral peak/median 1206)
```

The hidden truth for that run was:
- a look-alike spacecraft over frames 29–59
- dish 2 dead over frames 78–118
- a fade over frames 168–178
- a −12-sample clock glitch on dish 1 at frame 212
- a +1363 Hz hop at frame 251, on top of the 40 Hz initial offset and 5 Hz/s drift (about 75 Hz by then)

### 4. Before/after spectra (required Track 1 output)
![Spectra](results/figures/spectra.png)

Units are dB relative to one dish's thermal noise; the combined outputs are scaled to the same noise.
- **Left, no interference:** the eight-dish output rises about 10 dB above the floor, compared with about 3 dB for one dish.
- **Right, wide-band source at +10 dB:** SUMPLE raises the floor to about +16 dB, so it follows the interferer. Choir puts the floor back at 0 dB with the signal on top.

### 5. Telemetry log
![Telemetry](results/figures/telemetry.png)

`results/telemetry_log_seed301.csv` lists every logged value: time, logged frame, sample, value. Only verified frames are logged. Gaps are frames the receiver refused to log.

### Tests (`tests/run_tests.m`, run first by `run_all`)
- The CRC reproduces the CRC-16/CCITT-FALSE check value 0x29B1.
- Frames survive a pack/parse round trip, and one flipped bit is rejected.
- Noise calibration: measured BER is 0.0118 against the BPSK theory value of 0.0125 at 4 dB.
- A clean loopback through the full receiver gives exact frames.
- Pure noise produces 0 logged frames, and 0 of 56 forced decode attempts on noise are accepted.
- With no interference, the baselines are fair: SUMPLE gets 115, equal gain 111 and the bound 117 of 120 frames at 1 dB.
- Only the analysis bound can receive the true bits.

## How to run

```matlab
% from this folder (choir/)
run_all            % or:  cd choir && matlab -batch run_all
```

- **Time:** about 2 minutes on a 12-core Mac with Parallel Computing Toolbox. Without it, everything runs serially.
- **Required:** MATLAB R2026b with Communications Toolbox, Satellite Communications Toolbox, Signal Processing Toolbox, DSP System Toolbox, and Statistics and Machine Learning Toolbox.
- **Outputs:** CSVs and figures in `results/`, slides in `docs/slides.pdf`.
- **One scenario by hand:** `run_scenario(choir_params(), make_scenario(seed, frames, EsN0dB, faults), specs)`. Faults are built with `fault(type, t0, t1, dish, value)`; see `random_faults.m` for examples.

## Data

- **NASA SMAP/MSL telemetry (telemanom).** Real spacecraft telemetry from the Curiosity rover (MSL) and SMAP. Values are pre-scaled to (−1, 1), and channel names are anonymized, so we do not attach physical units.
  - Hundman et al., *Detecting Spacecraft Anomalies Using LSTMs and Nonparametric Dynamic Thresholding*, KDD 2018. Repository: https://github.com/khundman/telemanom. The data is currently distributed through Kaggle (`patrickfleith/nasa-anomaly-detection-dataset-smap-msl`).
  - **What we use:** the first column (the telemetry value) of the MSL test-set channels, streamed in label-file order (M-6, M-1, M-2, S-2, P-10, …). Every run starts at the beginning of that stream. Values are quantized to int16 for the frames.
  - **To reproduce:**
    - Download the Kaggle zip (about 86 MB).
    - Extract `labeled_anomalies.csv` and `data/data/test/*.npy` anywhere under `res/`. That is about 115 MB, and it is not committed.
    - `telemetry_source.m` finds the MSL channels with a small MATLAB `.npy` reader.
  - **Without the files,** a synthetic stand-in is used, and every figure title says so.
- **No real multi-dish radio recordings** were available. The RF link is simulated, so these results show the receiver's logic and robustness, not a field measurement.

## Limitations and next steps

- **Simulated link.** A real multi-antenna recording is the obvious next test, for example SatNOGS recordings with several stations on one pass.
- **Uncoded BPSK.** Real deep-space links use turbo or LDPC codes, which would move every curve several dB to the left. The receiver logic stays the same.
- **Interferer geometry.** Interferers are modeled near the spacecraft's direction, so they share each dish's residual delay.
  - In our first version they did not. Even the bound then lost most frames above +5 dB, because one weight per dish cannot cancel a signal that is misaligned across dishes by whole symbols.
  - We changed the model because residual per-dish delays (cables, clocks) apply to everything a dish receives.
  - A far off-axis interferer, whose geometric delays differ from the spacecraft's, would need a few taps per dish instead of one weight. That case is not covered here.
- **Same-direction interferers.** These cannot be separated by any dish weighting (seed 304).
- **Bootstrapping.** Choir needs verified frames to learn trust. An interferer that is present before any frame ever verifies is its weak case.
- **Spoofing.** The checksum protects against noise, not a deliberate spoofer; that needs authenticated frames, such as CCSDS SDLS.
- **Not built yet:** elastic arraying (releasing dishes when the margin allows) and a Stateflow version of the supervisor.

## Prior work and what is ours

- **Antenna arraying** is decades old in the DSN, for example its role in Galileo's mission.
- **SUMPLE:** D. H. Rogstad, IPN Progress Report 42-162, 2005.
- **JPL's work on interference:**
  - It modified SUMPLE for wide-band interferers in the beam (NASA Tech Brief NPO-45640).
  - It studied array processing with interfering sources, including other spacecraft (IPN Progress Report 42-150).
- **Weighting antennas by known or decoded data** is standard in wireless engineering.

**What we built and measured:** a receiver that runs itself and learns which dishes to trust only from verified frames (checksum + spacecraft ID + frame count). It cancels interference from the current frame's statistics, recovers from failures without help, and logs why. We compared it on identical samples against SUMPLE, equal gain, a sync-marker-only version and a bound. The tests include a look-alike spacecraft with the same bandwidth, a case the published bandwidth-based fix does not target.

## Credits

- **Data:** NASA/JPL SMAP and MSL telemetry via telemanom (Hundman et al., KDD 2018).
- **References:**
  - Rogstad, *The SUMPLE Algorithm for Aligning Arrays of Receiving Radio Antennas*, IPN PR 42-162 (2005).
  - NASA Tech Brief NPO-45640, *Aligning a Receiving Antenna Array to Reduce Interference*.
  - *Large-Array Signal Processing for Deep-Space Applications*, IPN PR 42-150.
  - NASA OIG, *Audit of NASA's Deep Space Network*, IG-23-016 (2023): DSN demand exceeds supply by up to 40% at times.
- **Tools:** MATLAB R2026b; `ccsdsTMWaveformGenerator` (Satellite Communications Toolbox); Communications, Signal Processing, DSP System, Statistics and Machine Learning and Parallel Computing Toolboxes.
- **AI assistance:** the code was written with AI assistance (Devin) during the hackathon, and reviewed and run by the team.
- **Explainer:** `docs/choir-explainer.html` is an animated, offline explainer. Its visuals are illustrative; the measured numbers are the ones in this README.

## Repository layout

```
run_all.m                 reproduces every number and figure
src/choir_params.m        all settings (fixed before evaluation)
src/frame_pack.m, frame_parse.m      CCSDS-style frames + CRC-16
src/tx_build.m            ccsdsTMWaveformGenerator transmitter
src/channel_make.m, channel_slot.m   hidden truth: dishes, faults, interferers
src/rx_init.m, rx_step.m  the receiver and its supervisor
src/score_run.m           independent scorer
src/exp_*.m               experiments and figures; make_slides.m builds docs/slides.pdf
src/telemetry_source.m    MSL telemetry loader (.npy) with labeled synthetic fallback
tests/run_tests.m         checks the claims depend on
results/                  CSVs, decision and telemetry logs, figures
docs/                     slides.pdf, choir-explainer.html
```

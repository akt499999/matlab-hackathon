# Swarm receivers: find the best settings for a message and a noise level

This is an add-on to Choir.
- **What it does:** you type a message and a noise level. The program finds the best receiver settings (carrier frequency, phase, timing, and gain) for that noise level by itself, and prints them with the decoded message.
- **How:** several receivers that know the message each try different settings and share results. Each round they move toward the best receiver's settings, until they reach the lowest error possible at that noise level.
- **Run it:** `choir\swarm\swarm.bat` from a terminal, or `swarm_receivers` in MATLAB.

```matlab
swarm_receivers                                    % asks for a message and a noise level, then finds the best settings
swarm_receivers('HELLO MARS', 8)                   % same, without the questions
```

- **Requirements:** MATLAB R2026b, no toolboxes.
- **From a terminal:** `matlab -batch "swarm_receivers"` uses the default settings.

## Procedure in the program

1. **Transmitter:** message, then bits, then BPSK, then root-raised-cosine pulse shaping.
2. **Channel:** noise at your chosen level, plus the distortions a real link adds, which the receivers must undo (picked at random each run):
   - a carrier frequency offset
   - a phase offset
   - a timing offset
3. **Receivers:** each receiver knows the message, as a known training sequence. Each receiver does these steps:
   - It decodes the signal with its current carrier frequency and timing.
   - It calculates the phase and gain that best match the known message (closed form).
   - It calculates its error between its symbols and the known symbols (EVM).
4. **Shared search (particle swarm):** in each round, each receiver moves its settings toward its own best result and toward the settings of the best receiver.
   - At the start, the receivers are spread equally across the frequency range, so one receiver always starts near the true value.
5. **Coarse to fine:**
   - The first rounds use only the first symbols, which permits large frequency errors.
   - The later rounds use the full message, which sets the frequency to within a fraction of a hertz.
6. **Stop condition:** at a given Es/N0, the lowest possible error is 1/(Es/N0).
   - When the best receiver is within 15% of this value, the program stops and considers the settings optimal.
   - Bit errors that remain after this come from the noise, not from the settings.

## Example results

| Run | True settings | Found settings | Decoded |
|---|---|---|---|
| `HELLO FROM MARS`, 8 dB, 8 receivers | 40 Hz, 30°, 2.40 samples | 39.5 Hz, 41.6°, 2.95 samples | 0 bit errors, 14 rounds |
| `HI TEAM`, 6 dB, 10 receivers | 100 Hz, 45°, 4.00 samples | 99.7 Hz, 48.6°, 4.72 samples | 0 bit errors, 10 rounds |
| `DEEP SPACE LINK TEST`, 4 dB, 12 receivers | −180 Hz, 120°, 6.40 samples | −179.4 Hz, 105°, 6.06 samples | 3 of 160 bits wrong, near the noise limit (BPSK theory gives approximately 2 at 4 dB) |

If the receivers stop improving before they reach the noise limit, half of them move to settings near the best receiver and continue. After 4 such moves with no improvement, the run stops and shows the best settings.

**Outputs**
- `results/swarm_convergence.png`: the error of each receiver against the noise limit, the frequency, phase, and timing against the true values, and the symbols before and after.
- `results/swarm_log.csv`.

## Limitations

- **Training sequence.** The receivers must know the message. In a real link, this is a preamble; after the preamble, the verified-frame tracking of Choir can continue.
- **Frequency range.** The search covers ±250 Hz around the expected carrier. The spectral search of Choir can supply this coarse value.

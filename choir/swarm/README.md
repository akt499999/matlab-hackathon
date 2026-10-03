# Swarm receivers: learning the exact channel settings together

An add-on to Choir. A typed message is sent as BPSK through a channel whose noise and impairments you set. Several receivers, each starting from different settings, learn the exact carrier frequency, phase, timing and gain needed to decode it, by sharing what works.

```matlab
swarm_receivers                                    % asks for every setting (Enter keeps the default)
swarm_receivers('HELLO MARS', 8, 40, 30, 0.3, 8)   % message, Es/N0 dB, freq offset Hz, phase deg, timing (fraction of a symbol), receivers
```

Runs in plain MATLAB R2026b (no toolboxes). From a terminal, `matlab -batch "swarm_receivers"` uses the defaults.

## How it works

1. **Transmit:** message → bits → BPSK → root-raised-cosine pulse shaping.
2. **Channel (user settings, hidden from the receivers):** noise at the chosen Es/N0, a carrier frequency offset, a phase offset and a timing offset.
3. **Receivers:** every receiver knows the real message (like a known training sequence). Each one:
   - decodes the signal with its current guess of carrier frequency and timing,
   - solves the phase and gain that best match the known message (closed form),
   - scores itself by the error between its symbols and the known ones (EVM).
4. **Sharing (particle swarm):** each round, every receiver nudges its settings toward its own best result and toward the best receiver's settings. Receivers start spread evenly across the frequency range, so one always starts near the truth.
5. **Coarse to fine:** early rounds score only the first few symbols, which tolerates large frequency errors; later rounds use the whole message, which pins the frequency down to a fraction of a hertz.
6. **Knowing the noise level gives the stopping point:** at a given Es/N0 the lowest possible error is 1/(Es/N0). When the best receiver is within 15% of that, its settings are optimal, and any remaining bit errors are caused by the noise, not the settings.

## Example results

| Run | True settings | Learned | Decoded |
|---|---|---|---|
| `HELLO FROM MARS`, 8 dB, 8 receivers | 40 Hz, 30°, 2.40 samples | 39.5 Hz, 41.6°, 2.95 samples | 0 bit errors, 14 rounds |
| `HI TEAM`, 6 dB, 10 receivers | 100 Hz, 45°, 4.00 samples | 99.7 Hz, 48.6°, 4.72 samples | 0 bit errors, 10 rounds |
| `DEEP SPACE LINK TEST`, 4 dB, 12 receivers | −180 Hz, 120°, 6.40 samples | −179.4 Hz, 105°, 6.06 samples | 3 of 160 bits wrong: the noise limit (BPSK theory predicts ~2 at 4 dB) |

If the receivers stall before reaching the noise limit, half of them spread out slightly around the best receiver's settings and keep refining. After 4 spread-outs with no improvement, the run stops and reports the best settings found.

Outputs: `results/swarm_convergence.png` (error per receiver vs the noise limit, frequency/phase/timing vs the truth, symbols before and after) and `results/swarm_log.csv`.

## Limitations

- The receivers need the message (a known training sequence). In a real link this would be a preamble, after which Choir's verified-frame tracking takes over.
- Frequency search range is ±250 Hz around the expected carrier; Choir's spectral search would supply that coarse estimate.

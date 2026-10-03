# Speaker notes

These notes are for `slides.pdf` (12 slides). The talk is 5 minutes, so each slide has approximately 25 seconds. Slide 10 is the live hardware demo. If the time is short, skip slide 4 or slide 8.

**1. Title.**
- Choir is a MATLAB receiver for 8 simulated dishes.
- It calculates the dish weights only from frames that pass three checks.
- With a look-alike spacecraft 10 dB stronger, Choir delivered 88.5% of the frames. SUMPLE delivered 0%.
- The telemetry is real NASA Curiosity data. The radio link is simulated.

**2. Project parts.**
- Track 1 asks for a pipeline that finds, cleans, and decodes weak signals with no human tuning.
- The project has a MATLAB receiver, a breadboard demo with 3 LEDs, and a swarm add-on.

**3. One dish against eight.**
- One dish needs approximately 8 dB to decode a frame.
- Eight dishes decoded all frames at 2 dB each.
- Without interference, Choir gives almost the same results as the other 8-dish receivers.

**4. Four states.**
- Choir changes state without operator input: SEARCH, ALIGN, DECODE, and FALLBACK.
- A frame is verified only if it has a correct CRC, spacecraft ID 42, and the next frame count.
- The dish weights come only from verified frames.

**5. Look-alike spacecraft.**
- A second spacecraft uses the same frame format and the same band. It is 10 dB stronger at each dish.
- SUMPLE aligns the dishes to the stronger signal and delivered 0% of the frames. Choir delivered 88.5%.
- The sync-marker-only receiver uses the same calculation with only 32 known bits. At +20 dB, it delivered 7.3%.

**6. Before/after spectra.**
- This is the Track 1 spectral plot.
- With a +10 dB wide-band source, the SUMPLE output noise floor was 16 dB. The Choir output noise floor was 0.1 dB.

**7. Hidden faults.**
- Each run had six faults at random times. The receiver did not get the fault list.
- Choir delivered 90.6% of the frames and recovered 284 ms after a carrier hop.
- With the supervisor off, the result was 40.0%.

**8. Decision log.**
- Choir recorded each fault within 2 frames and gave the cause. The table shows the program output for seed 301.

**9. Simulink.**
- The same receiver code runs in Simulink, one frame per step.
- It delivered 275 of 300 frames, the same as in MATLAB.

**10. Hardware demo (live).**
- Three LEDs send the same Morse frame to one photoresistor.
- A hidden fault changes one LED, or a look-alike frame goes on 2 of 3 LEDs.
- The majority vote selects the look-alike. Choir rejects it because the ID is wrong.
- Light intensities add, so this demo shows the acceptance rule, not radio combining.

**11. Limitations.**
- In one geometry, the look-alike arrived with a pattern similar to the spacecraft (similarity 0.81). All receivers failed, including the bound.
- Without interference and at −2 dB, SUMPLE was slightly better.
- The radio link is simulated, and the frames are uncoded.

**12. Swarm add-on.**
- Several receivers find the carrier frequency, phase, timing, and gain together. They use a known training message.
- In three reported runs, the frequency error was 0.6 Hz or less.

## Answers to possible questions

- **Is the radio data real?** No. The telemetry values are real NASA Curiosity data. The radio link is simulated because no multi-dish recording was available.
- **Is the method new?** The parts are known: SUMPLE is from JPL, and weights from decoded data are common in wireless engineering. This project is a receiver that operates without operator input, uses only verified frames for the weights, and has a measured comparison against SUMPLE.
- **Why no deep learning?** The combining and decoding calculations are known and almost optimal. No training data was available.
- **Was the receiver tuned on the test data?** No. Development used other seeds. The receiver was frozen before the final run.
- **Was AI used?** Yes. The README states this. The team reviewed and ran the code.

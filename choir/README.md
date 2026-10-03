# Choir project folder

The project description, the results, and the procedure are in the [repository README](../README.md).

To run all calculations, go to this folder in MATLAB R2026b and type:

```matlab
run_all          % runs the tests, then writes all CSV files and figures to results/
```

The code reads real NASA MSL telemetry from `res/` (see the Data section of the README). If the data is not available, the code uses a labeled synthetic signal.

| Folder | Contents |
|---|---|
| `src/` | Receiver, supervisor, simulation, and experiments |
| `tests/` | Checks for the results |
| `results/` | CSV files, decision and telemetry logs, figures |
| `simulink/` | The same receiver in Simulink |
| `swarm/` | Add-on: swarm receivers that find the channel settings together |
| `deck/` | Slide sources (each number on the slides comes from `numbers.json`) |
| `docs/` | `slides.pdf`, `speaker_notes.md`, and the animated explainer |

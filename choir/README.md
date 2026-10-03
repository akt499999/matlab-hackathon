# Choir project folder

The full project description, results and run instructions are in the [repository README](../README.md).

Quick start, from this folder in MATLAB R2026b:

```matlab
run_all          % runs the tests, then writes every CSV and figure to results/
```

Real NASA MSL telemetry is read from `res/` (see the README's Data section). Without it, a labeled synthetic stand-in is used.

| Folder | Contents |
|---|---|
| `src/` | Receiver, supervisor, simulation and experiments |
| `tests/` | Checks the results depend on |
| `results/` | CSVs, decision and telemetry logs, figures |
| `simulink/` | The same receiver stepped inside Simulink |
| `swarm/` | Add-on: swarm receivers that learn channel settings together |
| `deck/` | Slide sources (every slide number comes from `numbers.json`) |
| `docs/` | `slides.pdf` and the animated explainer |

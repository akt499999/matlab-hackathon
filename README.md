# MATLAB in Space Hackathon: Deep-Space Signal Intelligence

Track 1 (Advanced) entry for the **MATLAB in Space Hackathon** at Northeastern University.

**Goal:** build software that finds, cleans, and decodes weak radio signals with no human tuning.

## Project Structure

```
matlab-hackathon/
├── res/                     # datasets (not committed; see Setup)
├── scripts/
│   └── download_dataset.py  # downloads RadioML and converts it to .mat
├── requirements.txt
└── README.md
```

## Requirements

- MATLAB R2026b
- Python 3 (only for the one-time dataset conversion)

## Setup

1. Create and activate a virtual environment, then install dependencies:

   ```bash
   python -m venv .venv
   .venv\Scripts\activate
   pip install -r requirements.txt
   ```

2. Download and convert the dataset (~641 MB download):

   ```bash
   python scripts\download_dataset.py
   ```

   This creates `res/RML2016.10a.mat`. If you already have `RML2016.10a_dict.pkl`, place it in `res/` and the download is skipped.

3. Run MATLAB code from the project root:

   ```bash
   matlab -batch "script_name"
   ```

## Dataset

**RadioML 2016.10A**: synthetic radio signals generated with GNU Radio, with realistic impairments (white noise, multipath fading, frequency offset, sample-rate drift).

| Property | Value |
|---|---|
| Modulations (11) | 8PSK, AM-DSB, AM-SSB, BPSK, CPFSK, GFSK, PAM4, QAM16, QAM64, QPSK, WBFM |
| SNR levels (20) | -20 dB to +18 dB, 2 dB steps |
| Examples | 1,000 per modulation/SNR pair, 220,000 total |
| Sample format | 128 complex samples, stored as I and Q rows |

After conversion, `res/RML2016.10a.mat` contains:

| Variable | Size | Description |
|---|---|---|
| `X` | 220000 × 2 × 128 | I/Q signal samples |
| `mods` | 220000 × 1 | Modulation label per example |
| `snrs` | 220000 × 1 | SNR (dB) per example |

Example: load the first QPSK signal at 10 dB as a complex vector:

```matlab
load('res/RML2016.10a.mat')
idx = find(strcmp(cellstr(mods), 'QPSK') & snrs(:) == 10, 1);
sig = squeeze(X(idx,1,:) + 1i*X(idx,2,:));
```

## Credits & License

- **RadioML 2016.10A** © DeepSig Inc., licensed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
  O'Shea, T. J., & West, N. "Radio Machine Learning Dataset Generation with GNU Radio." *Proceedings of the GNU Radio Conference*, 2016.
  Dataset page: https://www.deepsig.ai/datasets/
- **SatNOGS** (if used): Libre Space Foundation, https://satnogs.org

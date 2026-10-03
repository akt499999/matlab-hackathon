import pickle
import urllib.request
from pathlib import Path

import numpy as np
from scipy.io import savemat

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RES_DIR = PROJECT_ROOT / "res"
INPUT_FILE = RES_DIR / "RML2016.10a_dict.pkl"
OUTPUT_FILE = RES_DIR / "RML2016.10a.mat"
URL = "https://huggingface.co/datasets/FlowVortex/RML/resolve/main/RML2016.10a_dict.pkl?download=true"


def progress(blocks, block_size, total):
    done = min(blocks * block_size, total)
    print(f"\rDownloading: {done / 1e6:.0f} / {total / 1e6:.0f} MB", end="", flush=True)


RES_DIR.mkdir(exist_ok=True)

if not INPUT_FILE.exists():
    tmp = INPUT_FILE.with_suffix(".part")
    urllib.request.urlretrieve(URL, tmp, progress)
    tmp.rename(INPUT_FILE)
    print()

print(f"Loading: {INPUT_FILE}")
with open(INPUT_FILE, "rb") as file:
    data = pickle.load(file, encoding="latin1")

X, mods, snrs = [], [], []
for (modulation, snr), samples in sorted(data.items()):
    X.append(samples)
    mods.extend([modulation] * len(samples))
    snrs.extend([snr] * len(samples))

X = np.concatenate(X).astype(np.float32)
mods = np.array(mods, dtype=object)
snrs = np.array(snrs, dtype=np.int16)

print(f"Saving: {OUTPUT_FILE}  X={X.shape}")
savemat(OUTPUT_FILE, {"X": X, "mods": mods, "snrs": snrs}, do_compression=True)
print("Conversion complete!")

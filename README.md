# MemSnap

Automated **Linux memory forensics** with AI‑driven detection of rootkits, code injection, and backdoors.

## Setup

1. **Lightweight VM**  
   A stripped‑down Ubuntu 24.04 VM has been prepared - idles at ≈159 MB, runs comfortably with 512 MB RAM.  
   *Build tools (git, build‑essential, kernel headers) and SSH are already installed.*

2. **Memory acquisition**  
   [AVML](https://github.com/microsoft/avml) is downloaded automatically by `manage_infect -a` when needed.

## Usage

### 1. Infect & capture memory  
`manage_infect` controls malware components and can capture a compressed memory dump.

```bash
# Infect with all components, then dump RAM
./manage_infect -i -C all -a

# Infect rootkit + code injection only
./manage_infect -i -C rootkit,injection -a

# Clean everything
./manage_infect -c -C all

# Check current state
./manage_infect -s
```

Dumps are named `memdump_<timestamp>_<active_components>.raw`.

### 2. Analyse with Volatility 3  
Activate the Python virtual environment, then run the parallel plugin executor:

```bash
python -m venv venv
source ./venv/bin/activate

./vol_runner memory_dump.raw
        # OR #
python3 ./vol_runner memory_dump.raw
```

Results are saved in `analysis/results/<timestamp>_linux/` as json files.

### 3. Feature extraction (planned)  
A separate script `extract_feats` will parse those outputs and produce a `features.csv` for AI training.  
*Currently the extraction is manual - a documented list of features exists (hidden processes, hooked syscalls, etc.).*

### 4. Train AI model (planned)  
The `features.csv` will be used in Google Colab to train a Random Forest classifier that predicts `rootkit`, `injection`, and `backdoor` threats.

### 5. Report generation (planned)  
Model predictions will be converted into a human‑readable investigation report.

## Project Status

- [x] VM lightweighting (≈159 MB idle, safe for 512 MB hypervisor)
- [x] Infection & capture manager (`manage_infect`)
- [x] Volatility 3 runner (`vol_runner.py`)
- [ ] Automated feature extraction (`extract_feats`)
- [ ] AI model training pipeline
- [ ] Automated investigation report

## Notes

- SSH and networking survive the lightweighting; the system uses **NetworkManager** by default.
- Python code runs inside a **virtual environment** - activate with `source venv/bin/activate` before using Volatility.
- AVML compresses dumps on‑the‑fly, shrinking a 1 GB dump to ≈200 MB.
- Kernel debug symbols for Volatility can be generated as described in the original setup guide (not needed if you use remote ISF URLs).

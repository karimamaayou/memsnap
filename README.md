# MemSnap

Automated **Linux memory forensics** - infects, captures, extracts features, and detects rootkits, code injection, and backdoors using AI.

## Quick start

```bash
git clone https://github.com/kmuratori/memsnap.git
cd memsnap
sudo apt install -y libsnappy-dev build-essential linux-headers-$(uname -r)
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cd assets && gcc -shared -fPIC evil.c -o evil.so && cd ..   # build injection library
# Rootkit: clone, patch, build and copy diamorphine.ko into assets/ (see below)
./memsnap infect -i -a dumps/          # infect all + capture dump
./memsnap extract dumps/ assets/features.csv   # extract features
./memsnap train -i assets/features.csv -o assets/model.pkl  # train model
./memsnap detect dumps/memdump_...rootkit.raw   # detect threats
./memsnap web                           # start web interface (FastAPI)
```

## Setup

1. **System dependencies**
   ```bash
   sudo apt install -y libsnappy-dev build-essential linux-headers-$(uname -r)
   ```

2. **Python environment & Volatility 3**
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

3. **Build assets**
   - Injection library:
     ```bash
     cd assets
     gcc -shared -fPIC evil.c -o evil.so
     cd ..
     ```
   - Rootkit module (Diamorphine):
     ```bash
     cd /tmp
     git clone https://github.com/m0nad/Diamorphine
     cd Diamorphine
     sed -i 's/PROC_ROOT_INO/PROCFS_ROOT_INO/g' diamorphine.c
     make
     cp diamorphine.ko ~/memsnap/assets/
     cd ~/memsnap
     ```
     (Rebuild the module if you change the kernel version.)

4. **Symbol table** - pre‑generated ISF file for kernel `6.17.0-22-generic` is already in `assets/`. For other kernels, generate a new one with `dwarf2json`.

5. **Memory acquisition** - AVML is downloaded automatically on first use.

## Usage

All commands use the `./memsnap` entry point:

| Command | Purpose |
|---------|---------|
| `./memsnap infect -i [components] -a [dir]` | Infect VM, optionally capture a dump |
| `./memsnap extract <dumps_dir> [csv]` | Extract features from dumps -> `features.csv` |
| `./memsnap train -i <csv> -o <model.pkl>` | Train AI model |
| `./memsnap detect <dump> [-m model]` | Detect threats in a single dump (CLI) |
| `./memsnap web` | Launch web-based detection interface (FastAPI) |
| `./memsnap test <dumps_dir>` | Batch run detection on all dumps in a directory |
| `./memsnap vol <dump>` | Run raw Volatility 3 analysis |

Examples:
```bash
./memsnap infect -i rootkit -a dumps/
./memsnap extract dumps/ features.csv
./memsnap train -i features.csv -o assets/model.pkl
./memsnap detect dumps/memdump_...rootkit.raw
./memsnap web          # starts on http://localhost:8501
```

Dumps are named `memdump_<timestamp>_<components>.raw`.

> **Note:** After cleaning with `./memsnap infect -c`, the rootkit may persist. Reboot to fully remove it.

## Project structure

```
memsnap/               -> unified entry script
scripts/
  infect               -> infection & memory capture
  extract              -> feature extraction -> features.csv
  train                -> train AI model
  detect               -> single‑dump CLI verdict
  web                  -> FastAPI server for web UI
  test                 -> batch detection script
assets/
  diamorphine.ko       -> pre‑built rootkit module
  evil.so              -> pre‑built injection library
  model.pkl            -> trained classifier
  features.csv         -> current dataset
  index.html           -> web UI frontend
  app.js               -> web UI logic
  *.json.xz            -> Volatility3 symbol table (kernel 6.17.0-22)
requirements.txt
```

## Known limitations

- **Backdoor detection** ~62% accuracy - one sample (`rootkit_injection`) mimics backdoor port behaviour. A dedicated feature (e.g., process name check for `ncat`) would improve this.
- **Small dataset** (8 dumps) - proof‑of‑concept only; expand with public dumps via `extract --append` for better generalisation.

## Environment

- **VM**: Ubuntu 24.04, kernel `6.17.0-22-generic`, 512 MB RAM, VirtualBox.
- **Volatility**: 3.2.8.0 (installed via `requirements.txt`).
- **Python**: 3.x, inside a venv.

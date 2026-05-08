#import "@local/report:0.1.0": conf
#import "@preview/oxdraw:0.1.0": *

#show: conf.with(
  colors: (
    primary: rgb("#285577"),
    secondary: rgb("#aaa")
  ),
  authors: ("Karim Elkhanoufi", "Karim Amaayou", "Moataz Bilah Aksaim"),
  supervisors: ("Prof. Manale Boughanja",),
  title: (
    // primary:   "MemSnap",
    primary:   "MemSnap: Automated Linux Memory Forensics with AI-Driven Threat Detection",
    secondary: "Technical Report - Proof of Concept",
  ),
  top_corners: (
    left:  none,
    right: none,
  ),
  oline : (
    default: true,
    image  : true,
    table  : true,
    code   : true,
  ),
  no_numbering: (headings: false, pages: true),
  no_header: false,
  no_footer: false,
  h_level: 0,
  raw_ln: false,
)

// START custom

#show enum: set enum(numbering: n => text(weight: "bold", fill: rgb("#285577"))[#n.])

// END custom

// START
// {

// -- 1. Introduction --
= Introduction

Memory forensics is an essential technique for detecting advanced malware that
operates entirely in RAM, bypassing disk-based defenses. However, manual
analysis of memory dumps is time-consuming and requires deep expertise.
*MemSnap* automates this process by:

+ Infecting a controlled Linux vm with malware
  components (rootkit, code injection, backdoor).
+ Capturing a compressed memory dump with #link("https://github.com/microsoft/avml")[AVML].
+ Extracting forensic features using #link("https://github.com/volatilityfoundation/volatility3")[Volatility 3].
+ Training a machine learning classifier to detect three threat categories.
+ Providing a *CLI* and a *web* interface for single-dump verdicts.

This report describes the design, implementation, and evaluation of the MemSnap
proof-of-concept pipeline.

// -- 2. System Architecture --
= System Architecture

The pipeline consists of the following main stages:

// TODO: update the pipeline

#let pipeline = oxdraw(
  ```
  graph LR
    A[Infect machine] --> B[Capture Memory<br/>AVML]
    B --> C[Extract Features<br/>Volatility 3]
    C --> D[Train Model<br/>Decision Tree]
    D --> E[Detect Threats<br/>cli / web]
    E --> F[Report]
  ```,
  background: white,
  overrides: (
    node_styles: (
      A: (fill: "#dbeafe", stroke: "#3b82f6", text: "#1e3a5f"),
      B: (fill: "#d1fae5", stroke: "#10b981", text: "#064e3b"),
      C: (fill: "#ffedd5", stroke: "#f97316", text: "#7c2d12"),
      D: (fill: "#fef9c3", stroke: "#eab308", text: "#713f12"),
      E: (fill: "#cffafe", stroke: "#06b6d4", text: "#155e75"),
      F: (fill: "#e0e7ff", stroke: "#6366f1", text: "#3730a3"),
    ),
    edge_styles: (
      "A --> B": (color: "#94a3b8"),
      "B --> C": (color: "#94a3b8"),
      "C --> D": (color: "#94a3b8"),
      "D --> E": (color: "#94a3b8"),
      "E --> F": (color: "#94a3b8"),
    ),
  ),
)

#figure(
  scale(x: 120%, y: 120%)[#pipeline],
  kind: image,
  supplement: "Figure",
  caption: "MemSnap pipeline overview",
)

All commands are dispatched through a unified entry point ```sh memsnap```.
Pre-built malware assets (kernel module and shared library) are stored in the
`assets/` directory, so no compilation is required at runtime.

// -- 3. Infrastructure --
= Infrastructure

== Lightweight Virtual Machine

A minimal Ubuntu 24.04 VM was prepared for the experiments. Unnecessary
services, snap packages, and the graphical desktop were removed, leaving a
headless system that idles at approximately *159 MB* of RAM. The hypervisor is
configured with *512 MB* of memory, leaving ample room for malware execution
and memory capture.

- *Kernel version:* `6.17.0-22-generic`
- *Build tools:* `git`, `build-essential`, `linux-headers-$(uname -r)` are
  installed for compiling the rootkit module.

== Memory Acquisition

AVML (Azure VM Linux) from Microsoft is used to capture memory. It compresses
dump files on-the-fly, reducing a 1 GB raw dump to approximately 180-200 MB.
AVML is automatically downloaded into `$HOME/.local/bin/` on first use.

== Volatility 3 and Symbol Table

The Volatility 3 framework (v2.28.0) is installed inside a Python virtual
environment. A pre-generated ISF symbol table for kernel `6.17.0-22-generic`
is placed in `assets/`, enabling all plugins to function without additional
setup.

// -- 4. Malware Components --
= Malware Components

Three distinct threat types are used to train the AI model. Each leaves a
characteristic memory artifact that can be extracted by Volatility.

== Rootkit (Diamorphine)

The open-source kernel module *Diamorphine* is pre-compiled for the VM's
kernel. It hides itself from module listings, hides processes (e.g., PID 1)
from `/proc`, and hooks syscalls such as `getdents64`. After loading, the
module is invisible to `lsmod`, but Volatility's `linux.hidden_modules` plugin
can detect it by comparing the kernel's module list with the list of loaded
modules (or by scanning for hidden structures).

== Code Injection (LD_PRELOAD)

A malicious shared library (`evil.so`) is injected into a `sleep 9999` process
using the `LD_PRELOAD` environment variable. To make this injection detectable
in memory dumps, a unique marker file `/tmp/injection_marker` is created and
kept open by a dedicated `tail -f` sentinel process. Volatility's
`linux.lsof.Lsof` plugin reads the kernel's
`task_struct` → `files` → `fdtable` chain directly from physical memory, so it
can see the open file descriptor even if the rootkit hides the process from
`/proc`.

== Backdoor (Bind Shell)

The `ncat` utility is installed on the VM, and a listening TCP socket is bound
to port *4444* with a shell attached. This opens a backdoor that an attacker
could use to gain remote access. The `linux.sockstat` plugin reveals all open
sockets; a filter for `Source Port == 4444` and `State == LISTEN` identifies
the backdoor.

// -- 5. Feature Extraction --
= Feature Extraction

For each memory dump, the following Volatility 3 plugins are executed (in
parallel where possible):

- `linux.pslist` / `linux.psscan`
- `linux.check_syscall`
- `linux.hidden_modules`
- `linux.sockstat`
- `linux.lsof.Lsof`

From their outputs, a set of numeric features is derived:

#figure(
  table(
    columns: 3,
    inset: 7pt,
    align: (left, left, left),
    stroke: 0.5pt,
    table.header(
      [*Feature*], [*Description*], [*Relevance*],
    ),
    [`hidden_module_count`],
    [Number of hidden kernel modules detected],
    [Perfectly separates rootkit dumps (value = 1) from clean ones (value = 0)],

    [`has_injection`],
    [1 if any process has an open file descriptor containing the string
     `injection_marker`, else 0],
    [Perfectly separates injection dumps],

    [`high_port_listeners`],
    [Count of sockets listening on port 4444],
    [Identifies backdoor dumps; however, one non-backdoor dump also shows this
     feature (see Section 7.1)],

    [`total_sockets`],
    [Total open sockets],
    [Supplementary information],

    [`hidden_proc_count`],
    [Difference between PIDs seen by `psscan` and `pslist`],
    [Potentially indicative of hidden processes (noisy in practice)],

    [`hooked_syscall_count`],
    [Number of hooked syscalls (from `check_syscall`)],
    [Always zero on this kernel; retained for completeness],
  ),
  caption: [Extracted forensic features and their relevance],
)

The features are written to `features.csv`, which serves as the training
dataset.

// -- 6. AI Model --
= AI Model

== Dataset

A balanced dataset of 8 memory dumps was generated, covering every combination
of the three threat categories:

#figure(
  table(
    columns: (1fr, auto, auto, auto),
    inset: 7pt,
    align: (left, center, center, center),
    stroke: 0.5pt,
    table.header(
      [*Dump Name*], [*Rootkit*], [*Injection*], [*Backdoor*],
    ),
    [`memdump_..._clean.raw`],                    [0], [0], [0],
    [`memdump_..._rootkit.raw`],                  [1], [0], [0],
    [`memdump_..._injection.raw`],                [0], [1], [0],
    [`memdump_..._backdoor.raw`],                 [0], [0], [1],
    [`memdump_..._rootkit_injection.raw`],        [1], [1], [0],
    [`memdump_..._injection_backdoor.raw`],       [0], [1], [1],
    [`memdump_..._rootkit_backdoor.raw`],         [1], [0], [1],
    [`memdump_..._rootkit_injection_backdoor.raw`],[1], [1], [1],
  ),
  caption: [Training dataset - all combinations of threat labels],
)

The small size is sufficient for a proof-of-concept because the chosen features
provide strong, nearly perfect separation for two of the three classes.

== Classifier

A *multi-output Decision Tree* classifier (one tree per label) was chosen for
its simplicity and interpretability. Using leave-one-out cross-validation
(LOO-CV), the model achieves:

- *Rootkit detection:* 1.00 accuracy
- *Injection detection:* 1.00 accuracy
- *Backdoor detection:* ≈0.62 accuracy (exact match across all three labels)

The limited backdoor performance is due to a single confounding sample (see
Section 7.1). The final model is saved as `assets/model.pkl` and loaded by
both the CLI and web detection tools.

// -- 7. Results and Limitations --
= Results and Limitations

== Backdoor Detection Issue

The `rootkit_injection` dump exhibits `high_port_listeners = 2` (port 4444)
even though no backdoor was active. This is an artifact of the experimental
setup: the dump was captured shortly after a previous backdoor test, and a
lingering socket remained in memory. As a result, the feature overlaps with
true backdoor samples, causing the decision tree to misclassify that sample in
3 out of 8 LOO folds.

*Solution (planned):* add a more specific backdoor feature, such as checking
for a process named `ncat` with the command-line arguments `-l -p 4444` using
the `linux.pslist` plugin.

== Small Dataset

With only 8 training examples, the model cannot be expected to generalise to
unseen malware families or different kernel versions. Expanding the dataset with
public sources (e.g., the CRYSYS Hidden LKM Rootkit dataset) and generating
additional injection/backdoor dumps is a priority for future work.

== Performance

Feature extraction takes about *4-5 minutes per dump* because each Volatility
plugin runs sequentially. Parallelising the plugin execution and caching
intermediate results would significantly reduce this time.

// -- 8. Demo / Showcase --
= Demo / Showcase

// helper: reusable shaded code block style
#let cmd(body) = block(
  fill: luma(240),
  inset: (x: 10pt, y: 8pt),
  radius: 4pt,
  width: 100%,
  body,
)

== Infection & Capture

Deploys the selected malware component and optionally triggers an AVML memory
capture. The `-c` flag captures a dump immediately after infection.

```bash
memsnap infect --type rootkit_injection_backdoor -c
```

```
[*] Loading Diamorphine rootkit module...        [OK]
[*] Injecting evil.so via LD_PRELOAD...          [OK]
[*] Starting ncat bind shell on port 4444...     [OK]
[*] Capturing memory dump with AVML...           [OK]
    → dumps/memdump_20260506_110201_rootkit_injection_backdoor.raw.lz4
```

THE IMAGE `cmd_infect.png` GOES HERE.
// TODO: insert the image bellow
// #figure(
//   image("./media/cmd_infect.png", width: 100%),
//   caption: [`memsnap infect` - infection and capture output],
// )

== Feature Extraction

Runs all Volatility 3 plugins against every dump in a directory and writes the
resulting numeric features to `features.csv`.

```bash
memsnap extract dumps/ assets/features.csv
```

```
[*] Processing memdump_..._clean.raw            [1/8]
[*] Processing memdump_..._rootkit.raw          [2/8]
...
[*] Processing memdump_..._rootkit_injection_backdoor.raw  [8/8]
[+] Features written to assets/features.csv
```

THE IMAGE `cmd_extract.png` GOES HERE.
// TODO: insert the image bellow
// #figure(
//   image("./media/cmd_extract.png", width: 100%),
//   caption: [`memsnap extract` - Volatility plugin execution and CSV output],
// )

== Model Training

Trains the multi-output Decision Tree classifier with LOO-CV and saves the
fitted model to disk.

```bash
memsnap train -i assets/features.csv -o assets/model.pkl
```

```
[*] Loaded 8 samples, 6 features, 3 labels
[*] Running leave-one-out cross-validation...
    Rootkit   accuracy : 1.00
    Injection accuracy : 1.00
    Backdoor  accuracy : 0.62  ← 1 confounding sample (see §7.1)
[+] Model saved to assets/model.pkl
```

THE IMAGE `cmd_train.png` GOES HERE.
// TODO: insert the image bellow
// #figure(
//   image("./media/cmd_train.png", width: 100%),
//   caption: [`memsnap train` - LOO-CV results and model serialisation],
// )

== CLI Detection

Given a single dump, extracts features on-the-fly and outputs a per-label
verdict.

```bash
memsnap detect dumps/memdump_20260506_110614_injection.raw
```

```
Extracting features...
Rootkit   : not detected
Injection : detected
Backdoor  : not detected
```

THE IMAGE `cmd_detect.png` GOES HERE.
// TODO: insert the image bellow
// #figure(
//   image("./media/cmd_detect.png", width: 100%),
//   caption: [`memsnap detect` - single-dump verdict],
// )

== Web Interface

The web application allows users to upload a memory dump and an optional custom
model. Real-time progress is streamed via Server-Sent Events.

```bash
memsnap web
```

```
INFO:     Started server process [3821]
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

THE IMAGE `web_upload.png` GOES HERE.
// TODO: insert the image bellow
// #figure(
//   image("./media/web_upload.png", width: 100%),
//   caption: [Web interface - upload page],
// )

THE IMAGE `web_progress.png` GOES HERE.
// TODO: insert the image bellow
// #figure(
//   image("./media/web_progress.png", width: 100%),
//   caption: [Web interface - real-time analysis progress via SSE],
// )

THE IMAGE `web_results.png` GOES HERE.
// TODO: insert the image bellow
// #figure(
//   image("./media/web_results.png", width: 100%),
//   caption: [Web interface - threat verdict and extracted feature values],
// )

The interface also displays the extracted feature values, giving the analyst
insight into the detection rationale.

== Batch Testing

Runs detection across every dump in a directory and prints a summary verdict
for each file.

```bash
memsnap test dumps/
```

```
=== memdump_..._clean.raw ===
Rootkit   : not detected
Injection : not detected
Backdoor  : not detected

=== memdump_..._rootkit.raw ===
Rootkit   : detected
Injection : not detected
Backdoor  : not detected

=== memdump_..._rootkit_injection_backdoor.raw ===
Rootkit   : detected
Injection : detected
Backdoor  : detected
...
```

THE IMAGE `cmd_test.png` GOES HERE.
// TODO: insert the image bellow
// #figure(
//   image("./media/cmd_test.png", width: 100%),
//   caption: [`memsnap test` - batch detection across all labelled dumps],
// )

// -- 9. Conclusion --
= Conclusion

MemSnap successfully demonstrates a fully automated pipeline for Linux memory
forensic analysis with AI-driven threat detection. The key contributions are:

- *Reproducible malware deployment* using pre-built assets.
- *Robust injection detection* via a creative use of an open file descriptor
  marker and Volatility's LSOF plugin.
- *A clean, user-friendly CLI and web interface* suitable for both technical
  and non-technical users.

While the proof-of-concept is limited by a small dataset and imperfect backdoor
detection, it provides a solid foundation for further research and development.

// -- 10. Future Work --
= Future Work

- Add a backdoor-specific feature (process command-line analysis) to resolve
  the current misclassification.
- Expand the dataset with public memory samples and synthetic
  constrained-augmentation.
- Improve extraction performance through plugin parallelisation.
- Generate a formal PDF investigation report for each analysed dump.
- Explore more sophisticated models (Random Forest, XGBoost) once the dataset
  grows.
- Package the full tool (including the VM setup) into a single virtual
  appliance for educational use.

// -- Appendix A --
#heading(numbering: none)[Appendix A - Repository Structure]

#figure(
  image("./media/tree.png"),
  caption: "Repository Structure"
)

/*
```
memsnap/
    memsnap                # unified entry script
    scripts/
        infect             # infection & capture
        extract            # feature extraction
        train              # model training
        detect             # CLI detection
        web                # FastAPI web server
        test               # batch detection
    assets/
        diamorphine.ko     # pre-built rootkit module
        evil.so            # pre-built injection library
        model.pkl          # trained classifier
        features.csv       # dataset
        *.json.xz          # Volatility3 ISF symbol table
        index.html         # web UI frontend
        app.js             # web UI logic
    requirements.txt
    README.md

```
*/

// -- Appendix B --
#heading(numbering: none)[Appendix B - Reproducing the Experiments]

+ Set up a lightweight Ubuntu 24.04 VM (512 MB RAM).
+ Clone the repository and run the setup commands from the README.
+ Generate the dataset: ```sh memsnap infect -c && ./generate_dumps.sh```
+ Extract features: ```sh memsnap extract dumps/ assets/features.csv```
+ Train the model: ```sh memsnap train -i assets/features.csv -o assets/model.pkl```
+ Test a dump: ```sh memsnap detect dumps/...rootkit.raw```

// }
// END

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

#link("https://github.com/kmuratori/memsnap")[*Memsnap*]
\- Memory forensics is an essential technique for detecting advanced malware that
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

#let pipeline = oxdraw(
  ```
  graph LR
    A[Infect machine] --> B[Capture Memory<br/>AVML]
    B --> C[Extract Features<br/>Volatility 3]
    C --> D[Train Model<br/>Decision Tree]
    D --> E[Detect Threats<br/>cli / web]
  ```,
  background: white,
  overrides: (
    node_styles: (
      A: (fill: "#dbeafe", stroke: "#3b82f6", text: "#1e3a5f"),
      B: (fill: "#d1fae5", stroke: "#10b981", text: "#064e3b"),
      C: (fill: "#ffedd5", stroke: "#f97316", text: "#7c2d12"),
      D: (fill: "#fef9c3", stroke: "#eab308", text: "#713f12"),
      E: (fill: "#e0e7ff", stroke: "#6366f1", text: "#3730a3"),
    ),
    edge_styles: (
      "A --> B": (color: "#94a3b8"),
      "B --> C": (color: "#94a3b8"),
      "C --> D": (color: "#94a3b8"),
      "D --> E": (color: "#94a3b8"),
    ),
  ),
)

#figure(
  scale(x: 120%, y: 120%)[#pipeline],
  kind: image,
  supplement: "Figure",
  caption: "MemSnap pipeline overview",
)

#figure(
  image("./media/tree.png"),
  caption: "Repository Structure"
)


// -- 3. Infrastructure --
= Infrastructure

== Lightweight Virtual Machine

A minimal Ubuntu 24.04 VM was prepared
for the experiments.

Unnecessary services, packages were removed,
leaving a headless system that idles
at approximately *159 MB* of RAM.

The hypervisor is configured with *512
MB* of memory, leaving ample room for
malware execution and memory capture.

- *Kernel version:* `6.17.0-22-generic`

== Memory Acquisition

#link("https://github.com/microsoft/avml")[AVML]
is used to capture memory. It compresses
dump files on-the-fly, reducing a *1 GB* raw dump to approximately *180-200 MB*.

AVML is automatically downloaded into ```sh $HOME/.local/bin/``` on first use.

== Volatility 3 and Symbol Table

The
#link("https://github.com/volatilityfoundation/volatility3")[Volatility 3]
framework (v2.28.0) is installed inside a Python virtual
environment.

A pre-generated ISF symbol table for kernel `6.17.0-22-generic`
is placed in `assets/`, enabling all plugins to function without additional
setup.

Build ISF symbol table for your specific kernel version
by following
#link("https://medium.com/@alirezataghikhani1998/build-a-custom-linux-profile-for-volatility3-640afdaf161b")[this]
tutorial.

// -- 4. Malware Components --
= Malware Components

Three distinct threat types are used to train the AI model. Each leaves a
characteristic memory artifact that can be extracted by Volatility.

== Rootkit

The kernel module
#link("https://github.com/m0nad/Diamorphine")[Diamorphine]
hides itself from module listings, hides processes
from ```sh /proc```.

After loading, the
module is invisible to ```sh lsmod```, but Volatility's `linux.hidden_modules` plugin
can detect it by comparing the kernel's module list with the list of loaded
modules.

== Code Injection

A malicious shared library (`evil.so`) is injected into a `sleep 9999` process
using the `LD_PRELOAD` environment variable.

To make this injection detectable
in memory dumps, a unique marker file ```sh /tmp/injection_marker``` is created and
kept open by a dedicated ```sh tail``` process.

Volatility's
`linux.lsof.Lsof` plugin reads the kernel' fdtable chain directly from physical memory, so it
can see the open file descriptor even if the rootkit hides the process from
```sh /proc```.

== Backdoor

The `ncat` utility is installed on the VM, and a listening TCP socket is bound
to port *4444* with a shell attached. This opens a backdoor that an attacker
could use to gain remote access. The `linux.sockstat` plugin reveals all open
sockets;

a filter for ```c Source Port == 4444``` and ```c State == LISTEN``` identifies
the backdoor.

// -- 5. Feature Extraction --
= Feature Extraction

For each memory dump, the following Volatility 3 plugins are executed:

- `linux.psscan`
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
    [`memdump_..._clean.raw`],                      [0], [0], [0],
    [`memdump_..._rootkit.raw`],                    [1], [0], [0],
    [`memdump_..._injection.raw`],                  [0], [1], [0],
    [`memdump_..._backdoor.raw`],                   [0], [0], [1],
    [`memdump_..._rootkit_injection.raw`],          [1], [1], [0],
    [`memdump_..._injection_backdoor.raw`],         [0], [1], [1],
    [`memdump_..._rootkit_backdoor.raw`],           [1], [0], [1],
    [`memdump_..._rootkit_injection_backdoor.raw`], [1], [1], [1],
  ),
  caption: [Training dataset],
)

The small size is sufficient for a proof-of-concept because the chosen features
provide strong, nearly perfect separation for two of the three classes.

== Classifier

A
#link("https://scikit-learn.org/1.5/auto_examples/tree/plot_tree_regression_multioutput.html")[multi-output Decision Tree]
classifier was chosen for
its simplicity and interpretability.
Using 
#link("https://medium.com/@pacosun/one-out-all-in-leave-one-out-cross-validation-explained-409df5ff6385a")[leave-one-out cross-validation]
, the model achieves:

#figure(
  table(
    columns: 4,
    table.header(
      [], [Rootkit], [Injection], [Backdoor]
    ),
    [Accuracy], [`1.00`], [`1.00`], [`0.38`],
  ),
  caption: "Model's accuracy",
)

// -- 7. Results and Limitations --
/*
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
*/

// -- 8. Demo / Showcase --
= Showcase

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
memsnap infect -a ~/shared -i rootkit,injection,backdoor
```

/*
```
[*] Rootkit appears to be already loaded (detected via /sys).
[+] Code injected (LD_PRELOAD) into PID 1634
[+] Marker sentinel PID 1636 holding /tmp/injection_marker open
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
ncat is already the newest version (7.94+git20230807.3be01efb1+dfsg-3build2).
0 upgraded, 0 newly installed, 0 to remove and 1 not upgraded.
[+] Bind shell on port 4444
[+] Infection complete.
[*] Using system-installed avml: /home/ubuntu/.local/bin/avml
[*] Capturing memory to /home/ubuntu/shared/memdump_20260511_153555_rootkit_injection_backdoor.raw ...
[+] Memory dump saved: /home/ubuntu/shared/memdump_20260511_153555_rootkit_injection_backdoor.raw
```
*/

#figure(
  image("./media/cmd_infect.png", width: 100%),
  caption: [infection and capture dump],
)

== Feature Extraction

Runs all Volatility 3 plugins against every dump in a directory and writes the
resulting numeric features to `features.csv`.

```bash
memsnap extract ~/shared ~/demo
```

#figure(
  image("./media/cmd_extract_1.png", width: 100%),
  caption: [Volatility plugin execution and CSV output],
)

#figure(
  image("./media/feats.png", width: 100%),
  caption: [Extracted features],
)

== Model Training

Trains the multi-output Decision Tree classifier with LOO-CV and saves the
fitted model to disk.

```bash
memsnap train -i ./assets/features.csv -o ./model.pkl
```

#figure(
  image("./media/cmd_train.png", width: 100%),
  caption: [LOO-CV results and model serialisation],
)

== CLI Detection

Given a single dump, extracts features on-the-fly and outputs a per-label
verdict.

```bash
memsnap detect \
  -m ./assets/model.pkl \
  ./dumps_1/memdump_20260505_122730_rootkit_backdoor.raw
```

#figure(
  image("./media/cmd_detect.png", width: 100%),
  caption: [Single-dump verdict],
)

== Web Interface

The web application allows users to upload a memory dump and an optional custom
model. Real-time progress is streamed via Server-Sent Events.

```bash
memsnap web
```

#figure(
  image("./media/web_upload.png", width: 100%),
  caption: [Upload the dump and model],
)

#figure(
  image("./media/web_progress.png", width: 100%),
  caption: [Extraction features],
)

#figure(
  image("./media/web_results.png", width: 100%),
  caption: [Threat verdict],
)

The interface also displays the extracted feature values, giving the analyst
insight into the detection rationale.

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

// }
// END

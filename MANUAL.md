# Paired Analysis 1 (Ca²⁺) — User Manual

**Current version:** 260603
**Language:** MATLAB
**Contact:** han.q.zhao@warwick.ac.uk

---

## Contents

1. [Overview](#1-overview)
2. [Software requirements](#2-software-requirements)
3. [Folder structure before you start](#3-folder-structure-before-you-start)
4. [The template spreadsheet](#4-the-template-spreadsheet)
5. [Paradigm files](#5-paradigm-files)
6. [How to run the pipeline](#6-how-to-run-the-pipeline)
7. [Stage 0_1 — Data organisation (concatenation)](#7-stage-0_1--data-organisation)
8. [Stage 0_2 — X-Y alignment](#8-stage-0_2--x-y-alignment)
9. [Stage 0_3 — Cross-run alignment](#8b-stage-0_3--cross-run-alignment)
10. [Stage 1_1 — Filtering and max projection](#9-stage-1_1--filtering-and-max-projection)
11. [Stage 1_1b — Combined max projection](#9b-stage-1_1b--combined-max-projection)
12. [Stage 1_2 — Active bouton detection](#10-stage-1_2--active-bouton-detection)
13. [Stage 1_4 — Pairing and merging data](#11-stage-1_4--pairing-and-merging-data)
14. [Output file reference](#12-output-file-reference)

---

## 1. Overview

This pipeline processes iGluSnFR image stacks acquired alongside WinWCP
electrophysiology recordings in the **calcium-concentration paradigm**, where
the same ROI of a cell is imaged twice — once at 1 mM and once at 2 mM
external [Ca²⁺]. The pipeline pairs these runs, builds a shared bouton mask
across both conditions, and emits only successfully paired data.

It runs in sequential stages, each writing into a dedicated folder so any
stage can be inspected or re-run independently.

```
raw/                         (your raw data — never modified)

Stage_1_organised/           ← output of Stage 0_1
Stage_2_aligned/             ← output of Stage 0_2
Stage_2b_cross_aligned/      ← output of Stage 0_3
Stage_3_A1/                  ← output of Stages 1_1, 1_1b and 1_2
Analysis_1_Results.mat       ← output of Stage 1_4
Analysis_1_template_paired.xlsx  ← emitted by Stage 1_4 (concatenated variant)
Analysis_1_template_split.xlsx   ← emitted by Stage 1_4 (split variant)
```

Stages 0_3 and 1_1b are calcium-paradigm specific and place every paired
run into a common coordinate frame with a shared max projection. Stage 1_4
comes in two variants — see Section 11. `Analysis_1_Results.mat` is the
input to Analysis 2 and beyond.

---

## 2. Software requirements

- **MATLAB** R2020b or later (earlier versions may work but are untested)
- **Image Processing Toolbox** — required for all stages
- **Parallel Computing Toolbox** — optional but recommended; used for TIFF
  loading and spatial filtering (falls back to serial automatically if
  absent)

No additional toolboxes or external packages are required.

---

## 3. Folder structure before you start

Set your MATLAB working directory to the root of the analysis folder (the
folder containing `pipeline_config.m`). All paths in the scripts are
relative to this location.

### Required files and folders

```
<analysis_root>/
├── pipeline_config.m              ← edit this before running
├── run_pipeline.m                 ← runs all stages in sequence
├── Analysis_1_template_new.xlsx   ← cell spreadsheet (see Section 4)
├── _paradigms/                    ← paradigm definition files (see Section 5)
│     └── par<N>.xlsx
├── raw/                           ← raw data (see below)
│     └── <cell_folder>/
│           └── <run_name>_<part>/
│                 ├── *.tif
│                 └── *.wcp
└── +A1_funs/                      ← helper functions (do not modify)
```

### Raw data layout

Each cell has its own folder inside `raw/`. The folder name becomes the
identifier used throughout the pipeline. The paired-Ca acquisition uses the
VAMP-style multi-part scheme: each run is split across several subfolders
named `<run_name>_1`, `<run_name>_2`, … (up to 5 parts). If a part has
multiple versions (e.g. `<run_name>_2_3`), the latest is selected
automatically.

| File | Description |
|------|-------------|
| `*_MMStack_Default.ome.tif` | Raw image stack from the camera |
| `*.wcp` | WinWCP electrophysiology file(s) — concatenated in time order |

---

## 4. The template spreadsheet

All stages read experiment metadata from an Excel spreadsheet (default:
`Analysis_1_template_new.xlsx`). Row 1 is the header — do not delete it.
Each subsequent row describes one imaging run.

| Column | Header | Description |
|--------|--------|-------------|
| 1 | Cell number | Integer index identifying the cell. Used as the primary key into the `Results_A1` struct in Stage 1_4. Multiple runs from the same cell share the same value here. |
| 2 | Folder | Name of the cell folder inside `raw/` (and all stage output folders). |
| 3 | Run name | Name of the run subfolder inside the cell folder. Also used as the base filename for saved `.mat` and `.tif` files. Must follow `<ROI>_<run>_<Ca>mM`. |
| 4 | Run index | Integer index of this run within the cell (e.g. 1, 2, 3…). Represents how many times the cell has been stimulated. |
| 5 | ROI index | Index of the imaged field of view. **Paired runs must share this value** — it is the grouping key for all pairing logic. |
| 6 | Paradigm | Paradigm number corresponding to a file in `_paradigms/`. Use `0` if no alignment sub-sweeps are needed (Stage 0_2 will skip registration). |
| 7 | Acquisition | `0` = 4 ms global shutter; `1` = 2 ms interleaving shutter. Determines which calculation module is used in Stage 1_4. |

Additional columns (iGluSnFR variant, Construct, Background, Transfected,
Data set, Rig, WCP format, etc.) may be present and are passed through
unchanged into the emitted paired/split spreadsheets.

### Run-name convention for the calcium paradigm

Run names follow `<ROI>_<run>_<Ca>mM`, e.g. `1_3_2mM` = ROI 1, run 3,
2 mM Ca²⁺. The `<Ca>mM` token is parsed by Stage 1_4 to identify the two
conditions of a pair; pairing itself is keyed on the **ROI-index column
(column 5)**.

---

## 5. Paradigm files

Paradigm files define how the imaging acquisition is divided into
sub-sweeps for motion correction (Stage 0_2) and baseline removal
(Stage 1_1).

**Location:** `_paradigms/par<N>.xlsx`, where `<N>` matches the Paradigm
column in the template.

**Format:** a single-column table where each row gives the number of
frames in one sub-sweep. The rows are read in order and must sum to the
total number of acquired frames.

### Currently defined paradigms

| Number | Description | Total frames |
|--------|-------------|--------------|
| 11 | 20× PPR, 5× 20 Hz trains | 6025 |
| 101 | 20× PPR, 1× 20 Hz 50-AP train, 5× recovery pulses | 8800 |

To add a new paradigm, create `_paradigms/par<N>.xlsx` with the appropriate
frame counts per sub-sweep.

---

## 6. How to run the pipeline

### Quick start

1. Open `pipeline_config.m` and set the key fields:

   ```matlab
   experiment        = 'VAMP';                            % concatenation variant
   select_f          = 2;                                 % Excel row(s) to process
   Analysis_template = 'Analysis_1_template_new.xlsx';
   ```

2. Set which stages to run:

   ```matlab
   run_stage_0_1  = true;
   run_stage_0_2  = true;
   run_stage_0_3  = true;   % cross-run alignment (calcium pairing)
   run_stage_1_1  = true;
   run_stage_1_1b = true;   % combined max projection (calcium pairing)
   run_stage_1_2  = true;
   run_stage_1_4  = true;
   ```

3. Run `run_pipeline.m` (press F5 or click Run).

`run_pipeline.m` invokes `Analysis_1_4_merging_data.m` (the **concatenated**
variant). To produce the **split** variant instead, run
`Analysis_1_4_split_merging_data.m` directly — see Section 11.

### Running a single stage

Each stage script can also be run independently. Open the script, set
`select_f` and `Analysis_template` at the top, and run it directly.

### Processing multiple rows

Set `select_f` to a range or list of Excel row numbers:

```matlab
select_f = 2:10;        % rows 2 through 10
select_f = [2 5 9];     % specific rows
```

Important: pairing in Stages 0_3, 1_1b and 1_4 is restricted to `select_f`.
To pair two runs, both rows must be in `select_f` simultaneously.

---

## 7. Stage 0_1 — Data organisation

**Script:** `Analysis_0_1_concatenation_VAMP.m`

This stage reorganises raw data into a consistent structure and
concatenates the multi-part VAMP-style acquisition.

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template_new.xlsx` | Defines which runs to process |
| `raw/<folder>/<run_name>_<p>/` | Raw image stack (`_MMStack_Default.ome.tif`) and WinWCP files (`*.wcp`) for each part `p = 1…5` |

Five sub-folders (`<run_name>_1` … `<run_name>_5`) are stitched together.
If a sub-folder has multiple versions (e.g. `<run_name>_2_3`), the latest
version is selected automatically.

### Channel assignments

| Channel in output (`Y`) | Source |
|-------------------------|--------|
| Column 1 — current (pA) | AI0 |
| Column 2 — command voltage | AI1 |
| Column 3 — camera exposure | AI5 |
| Column 4 — camera trigger | AI3 |

### Output

```
Stage_1_organised/
  └── <folder>/
        ├── <run_name>.mat        (T and Y arrays — ephys data)
        └── <run_name>/
              └── <run_name>.tif  (image stack, concatenated from raw/)
```

---

## 8. Stage 0_2 — X-Y alignment

**Scripts:** `Analysis_0_2_alignment.m`, `Analysis_0_2b_alignment_split.m`

Corrects inter-sweep XY drift by registering each sub-sweep to the first,
then applies the transforms to every frame within that sub-sweep.

The `_split` variant is for **dual red/green channel acquisitions**, where
the camera frame is split down the middle (left = red, right = green). It
detects the split point on the whole-stack mean, keeps only the right
(green) half, and then runs the standard alignment workflow on it. Output
layout is identical to the standard script, so downstream stages need no
changes.

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template_new.xlsx` | Defines which runs to process and their paradigm number |
| `Stage_1_organised/<folder>/<run_name>/<run_name>.tif` | Concatenated image stack |
| `_paradigms/par<N>.xlsx` | Sub-sweep frame counts |

### Algorithm

1. The image stack is split into sub-sweeps according to the paradigm file.
2. A mean image is computed for each sub-sweep.
3. The first sub-sweep mean is used as the reference (anchor).
4. Each subsequent sub-sweep mean is registered to the anchor using
   `imregtform()` (2D translation, monomodal intensity-based, up to 300
   iterations).
5. The translation transform is applied to every individual frame in that
   sub-sweep using `imwarp()` with linear interpolation.
6. Pixels that receive no data after any translation (zero-padded borders)
   are identified across the whole time series, and the stack is cropped
   to the region valid in all frames.
7. The ephys `.mat` file is copied forward to `Stage_2_aligned/`.

If the Paradigm column is `0`, alignment is skipped (the stack is copied
through unchanged).

### Output

```
Stage_2_aligned/
  └── <folder>/
        ├── <run_name>.mat
        └── <run_name>/
              ├── aligned.tif             (motion-corrected, cropped stack)
              ├── aligned_averages.tif    (mean image per sub-sweep, after alignment)
              ├── unaligned_averages.tif  (mean image per sub-sweep, before alignment)
              └── transforms.csv          (X and Y shift per sub-sweep, pixels)
```

### Parameters (inside script)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `optimizer.MaximumIterations` | 300 | Registration convergence limit |
| `optimizer.MaximumStepLength` | 0.0625 | Largest step size |
| Gaussian blur for registration | σ = 2 px | Applied to sub-sweep means before registration |

---

## 8b. Stage 0_3 — Cross-run alignment

**Script:** `Analysis_0_3_cross_run_alignment.m`

Co-registers same-ROI runs in 2D so they share a single coordinate frame.
This is what makes a shared bouton mask across the pair possible (Stages
1_1b, 1_2).

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template_new.xlsx` | Defines which rows to process |
| `Stage_2_aligned/<folder>/<run_name>/aligned.tif` | Within-run aligned stack |
| `Stage_2_aligned/<folder>/<run_name>.mat` | Ephys data (copied through) |

### Algorithm

1. **Group rows** in `select_f` by `(Cell number, ROI index)`. Within each
   group the row with the lowest Run index is the **anchor**.
2. **Load every member's stack** from `Stage_2_aligned/` and **zero-pad**
   smaller members to the largest member's `(H, W)` so registration can be
   done in a common frame.
3. **Compute the whole-stack mean** of each member.
4. **Register** the Gaussian-blurred mean of every non-anchor member to
   that of the anchor with `imregtform` (2D translation, monomodal,
   identical optimizer settings to Stage 0_2).
5. **Apply** each transform frame-by-frame to its member's stack using
   `imwarp` with linear interpolation.
6. **Crop** all members of the group to the bounding box of the
   intersection of their valid (non-zero) regions across all frames, so
   every member ends up at the same final `(H, W)`.
7. Groups with only one member in `select_f` (singletons) are passed
   through with an identity transform — they receive no cropping beyond
   what Stage 0_2 already applied.
8. **Registration-quality check.** After warping and cropping, the
   normalised correlation (NCC) is computed between the anchor's mean
   image and each non-anchor's warped mean image, restricted to the final
   crop window. If any non-anchor scores below `MIN_NCC` (default 0.5)
   the script prints a `[WARN]` line. The NCC values are also written to
   `transforms.csv` for later inspection.

### Output

```
Stage_2b_cross_aligned/
  └── <folder>/
        ├── <run_name>.mat
        └── <run_name>/
              ├── aligned.tif    (cross-aligned, common-crop stack)
              └── transforms.csv (per-member: Run index, X- and Y-shift, NCC vs anchor)
```

### Important notes

- **Grouping is restricted to `select_f`.** If you only select one row of a
  pair, that row is treated as a singleton (no cross-registration). To
  cross-align a pair, both rows must be in `select_f` simultaneously.
- **All members of a group must have a `Stage_2_aligned/.../aligned.tif`**
  available; if one is missing the whole group errors out (logged against
  every member).
- Re-running Stage 0_3 is safe — it always reads from `Stage_2_aligned/`
  and overwrites `Stage_2b_cross_aligned/`.

---

## 9. Stage 1_1 — Filtering and max projection

**Script:** `Analysis_1_1_max_proj.m`

Denoises the image stack and produces a maximum-intensity projection used
for bouton detection.

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template_new.xlsx` | Defines runs and paradigm |
| `Stage_2b_cross_aligned/<folder>/<run_name>/aligned.tif` | Cross-aligned image stack |
| `_paradigms/par<N>.xlsx` | Sub-sweep frame counts (for baseline removal) |

### Algorithm

1. **Spatial filtering** — applied frame by frame (parallelised):
   - Wiener filter (5 × 5 window)
   - Median filter (3 × 3 window)
2. **Temporal filtering** — applied pixel by pixel (parallelised):
   - Baseline removal using the SNIP algorithm (sub-sweep by sub-sweep,
     using the paradigm file)
   - Binomial smoothing filter (order 3)
   - A constant offset of +2000 is added before scaling to `uint16` to
     prevent clipping at zero after baseline subtraction
3. **Max projection** — pixel-wise maximum across the time axis.

### Output

```
Stage_3_A1/
  └── <folder>/
        ├── <run_name>.mat        (ephys data, copied forward)
        └── <run_name>/
              ├── Max_img_filt.tif        (maximum intensity projection — primary output)
              ├── max_proj_unscaled.mat   (pre-scale16 max projection + forward
              │                            transform; consumed by Stage 1_1b to
              │                            put paired runs on a common ΔF scale
              │                            before combining)
              ├── Img_filt.tif            (full filtered stack — optional, large file)
              └── Cml_img_filt.tif        (cumulative max projection — optional)
```

### Parameters (inside script)

| Parameter | Variable | Default | Description |
|-----------|----------|---------|-------------|
| Wiener filter size | `n` | 5 | Window size (odd number ≥ 3) |
| Median filter size | `m` | 3 | Window size (odd number ≥ 3) |
| Binomial filter order | `bi_order` | 3 | Higher = smoother |
| Save full filtered stack | `save_process` | `'No'` | Change to `'Yes'` to save `Img_filt.tif` |
| Save cumulative max | `save_process_cml` | `'No'` | Change to `'Yes'` to save `Cml_img_filt.tif` |

---

## 9b. Stage 1_1b — Combined max projection

**Script:** `Analysis_1_1b_combined_max.m`

Combines the per-run max projections of all members of a `(Cell, ROI)`
group into a single projection so that Stage 1_2 detects boutons jointly
across both Ca²⁺ conditions. A bouton that is silent at one concentration
but active at the other is still detected, as long as it appears in
*either* projection.

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template_new.xlsx` | Defines runs to process |
| `Stage_3_A1/<folder>/<run_name>/max_proj_unscaled.mat` | Pre-scale16 max projection + forward transform (`max_proj_unscaled`, `norm_scale`) from Stage 1_1 |

### Algorithm

1. Group rows in `select_f` by `(Cell number, ROI index)`.
2. For each group, load every member's `max_proj_unscaled.mat`.
3. Invert each member's Stage 1_1 forward transform:
   `(max_proj_unscaled − 2000) / norm_scale`. This subtracts the +2000
   pipeline offset and undoes the two `scale16fast` stretches, putting
   every run on a common ΔF scale that is proportional to raw camera
   counts.
4. Take the pixel-wise maximum across all members on this common scale.
5. Apply `scale16` once to map the combined projection to uint16.
6. Write the result as `Max_img_combined.tif` into every member's
   `Stage_3_A1/<folder>/<run_name>/` folder. The file is therefore
   duplicated across the runs of a pair.

This is amplitude-preserving: a dim run contributes proportionally less to
the combined max than a bright run, instead of being stretched up to
match.

### Output

```
Stage_3_A1/<folder>/<run_name>/Max_img_combined.tif
```

### Important notes

- Stage 0_3 must have been run first — otherwise the per-run max
  projections will be in different coordinate frames and the script will
  refuse to combine them.
- Singleton groups (one row in `select_f` for that ROI) produce a
  `Max_img_combined.tif` that is functionally equivalent to the per-run
  `Max_img_filt.tif`.

---

## 10. Stage 1_2 — Active bouton detection

**Script:** `Analysis_1_2_abd.m`

Detects individual synaptic boutons in the combined max projection and
extracts their fluorescence time traces from the aligned image stack.

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template_new.xlsx` | Defines which runs to process |
| `Stage_3_A1/<folder>/<run_name>/Max_img_combined.tif` | Combined max projection (for segmentation) |
| `Stage_2b_cross_aligned/<folder>/<run_name>/aligned.tif` | Full image stack (for trace extraction) |

### Algorithm

1. **Adaptive thresholding** — the max projection is thresholded locally
   using a sliding window (`adaptthresh`). Pixels brighter than their
   local neighbourhood (scaled by the threshold parameter) form a binary
   mask.
2. **Morphological cleaning** — the mask is opened then closed with a
   disk structuring element (radius 2 px).
3. **Watershed separation** — touching boutons are separated using a
   marker-controlled watershed. A combined image is formed from the
   inverted intensity and the inverted distance transform
   (weighted 0.8 / 0.2). H-minima suppression prevents over-segmentation.
4. **Label and extract** — each connected component is labelled, region
   properties are computed, and the nearest-neighbour distance matrix is
   calculated.
5. **Trace extraction** — the mean pixel intensity within each bouton
   mask is extracted for every frame of the aligned stack.

Paired runs share the same combined max projection, so the bouton mask,
metadata, and visualisation files will be identical across the runs of a
pair. Trace extraction still runs independently against each run's own
aligned stack, so `mean_traces.csv` differs between paired runs. Bouton
indices are comparable across the pair.

### Output

```
Stage_3_A1/<folder>/<run_name>/
├── mask.tif                     (binary mask of all detected boutons)
├── boutons/                     (individual binary mask per bouton)
│     ├── bouton_1.tif
│     └── bouton_N.tif
├── bouton_metadata.csv          (shape properties, see table below)
├── mean_traces.csv              (fluorescence trace per bouton, rows = frames)
├── bouton_plots/                (PNG plot of each bouton's trace)
├── bouton_figs/                 (MATLAB .fig of each bouton's trace)
└── bouton_visualisation.tif     (max projection with bouton outlines overlaid)
```

### bouton_metadata.csv columns

| Column | Description |
|--------|-------------|
| 1 | Bouton number |
| 2 | Area (pixels) |
| 3 | Major axis length (from ellipse fit to mask) |
| 4 | Minor axis length |
| 5 | Centroid X coordinate |
| 6 | Centroid Y coordinate |
| 7 | Nearest neighbour index (by minimum boundary distance) |
| 8 | Nearest neighbour distance — minimum (pixels) |
| 9 | Nearest neighbour distance — centroid to centroid (pixels) |

### Parameters (inside script)

| Parameter | Variable | Default | Description |
|-----------|----------|---------|-------------|
| Threshold fraction | `adaptive_threshold` | 0.4 | Sensitivity of adaptive thresholding |
| Threshold window | `w` | 15 | Neighbourhood size for adaptive threshold |
| Intensity/distance weight | `weight` | 0.8 | Balance intensity vs. distance transform |
| H-minima depth | `h` | 0.02 | Merge depth for touching boutons |

---

## 11. Stage 1_4 — Pairing and merging data

Stage 1_4 aggregates per-run outputs into `Results_A1` and emits a new
spreadsheet containing **only the runs that survived pairing**. There are
two variants — both pair on `(Cell number, ROI index)` and discard data
that cannot be paired.

| Script | One slot of `Results_A1` per … | Emits | When to use |
|--------|-------------------------------|-------|-------------|
| `Analysis_1_4_merging_data.m` | **pair** (1 mM and 2 mM concatenated) | `Analysis_1_template_paired.xlsx` (one row per pair) | Downstream analyses that want a single time-axis per ROI |
| `Analysis_1_4_split_merging_data.m` | **run** (1 mM and 2 mM as separate slots) | `Analysis_1_template_split.xlsx` (one row per paired run) | Downstream analyses that need to keep the two Ca²⁺ conditions separate |

`run_pipeline.m` calls the **concatenated** variant. Run
`Analysis_1_4_split_merging_data.m` directly from MATLAB to produce the
split variant. Both can be run against the same `Stage_3_A1/` outputs;
they write to the same `Analysis_1_Results.mat` so re-running one after
the other will overwrite slots produced by the previous.

### Pairing rules (both variants)

For each `(Cell, ROI)` group inside `select_f`:

- **1 row (singleton).** Concatenated variant: skipped by default; set
  `include_singletons = true` before running to keep it as a one-run
  entry. Split variant: always skipped.
- **2 rows.** Their `<Ca>mM` tokens must be `{1, 2}`; otherwise the group
  errors out (concatenated) or is skipped (split).
- **≥ 3 rows.** The first two rows (in input-list order) are kept iff
  their Ca tokens are `{1, 2}`; the remainder are dropped with a
  `NOTE`. If the first two share a Ca, the group is dropped.

### Run-indexing convention

Both variants follow the convention in
`_claude/run_indexing_convention.md`: slots inside `Results_A1` are
addressed by **slot position** (match index), not by `Run_index` or
`Imaged_area_index`. This guarantees no zero-padded gaps and that **only
successfully processed runs appear in the output**.

- Concatenated variant: rollback on error — if a fresh `(Cell, ROI)` slot
  is appended and the merge throws, the slot is spliced out before
  saving.
- Split variant: compute-then-commit — both runs of a pair are buffered
  before any `Results_A1` write; if either run errors the whole pair is
  dropped.

Downstream code should look up a specific run by
`idx = find(Results_A1(cell).Run_index == k)` (or
`Imaged_area_index == roi` for the concatenated variant), then read
`Results_A1(cell).Frame_data(idx).data`, etc.

There is **no `Calcium_mM` field** in the current `Results_A1`. If an
older results file with this field is loaded, both scripts strip it on
load. Ca information is recoverable from the `<Ca>mM` token in
`Run_name` (split variant) or implied by the slot layout (concatenated
variant: first half of the time axis is 1 mM, second half is 2 mM).

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template_new.xlsx` | Defines which runs to merge and their metadata |
| `Stage_3_A1/<folder>/<run_name>/bouton_metadata.csv` | Bouton shape properties |
| `Stage_3_A1/<folder>/<run_name>/mean_traces.csv` | Fluorescence traces |
| `Stage_3_A1/<folder>/<run_name>/mean_traces_plus_rings.mat` | Ring traces (optional) |
| `Stage_3_A1/<folder>/<run_name>.mat` | Ephys data for frame and AP timing |

### Algorithm

For each `(Cell, ROI)` group, after the pairing rules above resolve which
rows to keep, both variants:

1. Load `bouton_metadata.csv` and `mean_traces.csv` for each kept run.
2. Load the ephys data and run the appropriate **Calculation Unit
   Module** to extract frame and AP timing:
   - `Calculation_Unit_Module_Analysis_1_4_new.m` — interleaving
     acquisition (Acquisition = 1)
   - `Calculation_Unit_Module_Analysis_1_4_old.m` — global-shutter
     acquisition (Acquisition = 0)
3. (Concatenated variant only) For pairs, verify that the bouton count
   matches between the two runs; error out the pair otherwise.
4. Build the slot's output payload (see below), then commit to
   `Results_A1`.
5. After every group, save `Analysis_1_Results.mat` so progress is
   preserved.
6. After all groups, rebuild the emitted spreadsheet **from
   `Results_A1`** so it reflects the actual content of the results
   file, not just the rows processed in this run.

### Concatenated variant — payload semantics

For a pair, the two runs are concatenated **1 mM first, 2 mM second** in
every time-resolved field. The 2 mM run's indices are offset by the size
of the 1 mM run:

- **`Frame_data(idx).data{1,1}`** — vertically stacked. Frame indices,
  ephys-sample columns, and second columns of the 2 mM block are shifted
  by `N_frames_1`, `N_samples_1`, and `T_end_1` respectively. Within-frame
  quantities (durations, t1, t2) are unchanged.
- **`Frame_data(idx).data{1, j>1}`** — trailing per-run summary cells are
  **averaged** between the two runs.
- **`AP_data(idx).data{1,1}`** — vertically stacked. 2 mM AP indices,
  frame indices, sample indices and time columns are shifted by
  `N_AP_1`, `N_frames_1`, `N_samples_1`, `T_end_1`.
- **`Bouton(idx).data`** — rows of the 2 mM block come after the 1 mM
  block; the frame-index column (column 1) continues across the
  boundary so that each row's frame index matches the concatenated
  `Frame_data`.
- **`Bouton_metadata(idx).data`** — taken from the 1 mM run; identical
  to the 2 mM run by virtue of the shared bouton mask (Section 10).
- **`Bouton_rings(idx).data`** — concatenated along the time dimension
  if both runs have numeric rings; otherwise an empty struct.

Slot `Run_name` is `<ROI>_1mM_2mM`; slot `Run_index` is the digit-
concatenation of the two runs' Run-index values (e.g. runs 1 and 3 →
`13`).

For a singleton (when `include_singletons = true`), the slot is the
single run's data unchanged.

### Split variant — payload semantics

Each run becomes its own slot with the original `Run_index`, `Run_name`,
`Imaged_area_index`, `Paradigm`, and `Acquisition` from the input
template. `Frame_data`, `AP_data`, `Bouton`, `Bouton_metadata`, and
`Bouton_rings` are read straight through — no concatenation, no
offsets.

### Output

**`Analysis_1_Results.mat`** — contains a struct array `Results_A1`.
Each element corresponds to one cell (indexed by Cell number column).
Within each element:

| Field | Description |
|-------|-------------|
| `Folder` | Cell folder name |
| `Run_name` | Cell array of run names for this cell's slots |
| `Run_index` | Vector of run indices, one per slot |
| `Imaged_area_index` | Vector of ROI indices, one per slot |
| `Paradigm` | Vector of paradigm numbers, one per slot |
| `Acquisition` | Vector of acquisition modes, one per slot |
| `Frame_data(idx).data` | Frame timing for slot `idx` (see below) |
| `AP_data(idx).data` | Action potential timing for slot `idx` |
| `Bouton_metadata(idx).data` | Same as `bouton_metadata.csv` (identical across the runs of a pair in the split variant) |
| `Bouton(idx).data` | Frame index + mean fluorescence per bouton |
| `Bouton_rings(idx).data` | Ring traces (if available) |

**`Analysis_1_template_paired.xlsx`** (concatenated variant) — one row per
emitted `(Cell, ROI)` pair. Columns 1–7 come from `Results_A1`; columns
8+ (inert metadata) are copied from the matching input-template row,
preferring the 1 mM row of the pair.

**`Analysis_1_template_split.xlsx`** (split variant) — one row per
emitted paired run, **only** if its `(Cell, ROI)` group in `Results_A1`
contains exactly the pair `{1 mM, 2 mM}`. Columns 1–7 come from
`Results_A1`; columns 8+ from the matching input-template row (matched
by `(Cell, Run name)`). Sorted by `(Cell, Run index)`.

Both spreadsheets are **rebuilt from `Results_A1`**, not appended to, so
they always reflect the actual content of the results file.

### Frame_data columns (Acquisition = 1, new module)

`Results_A1(cell).Frame_data(idx).data{1,1}`:

| Column | Description |
|--------|-------------|
| 1 | Frame index |
| 2 | Frame start — ephys sample index |
| 3 | Frame end — ephys sample index |
| 4 | Frame duration — ephys samples |
| 5 | Frame start — seconds |
| 6 | Frame end — seconds |
| 7 | Frame duration — seconds |
| 8 | t1 — time until last pixel row starts exposing (samples) |
| 9 | t2 — total exposure time (samples) |
| 10 | t1 — seconds |
| 11 | t2 — seconds |

`Results_A1(cell).Frame_data(idx).data{1,j}` for `j > 1`:

| j | Content |
|---|---------|
| 2 | Mean frame period (seconds) |
| 3 | Mean t1 (seconds) |
| 4 | Mean t2 (seconds) |

`t1` and `t2` are needed for AP-frame correction in Analysis 2+ and are
only present for interleafing-shutter data. In the concatenated variant
for a pair, the `j > 1` summary cells are the mean of the two runs'
values.

### AP_data columns

`Results_A1(cell).AP_data(idx).data{1,1}`:

| Column | Description |
|--------|-------------|
| 1 | AP index |
| 2 | Frame where AP belongs (adjusted) |
| 3 | AP peak — ephys sample index |
| 4 | AP peak — seconds |
| 5 | AP amplitude (pA) |
| 6 | True frame (shifted by −1 when the number of processed imaging frames differs from the ephys frame count — this column is what downstream analysis uses) |

### Bouton data columns

`Results_A1(cell).Bouton(idx).data`:

| Column | Description |
|--------|-------------|
| 1 | Frame index (image-corrected; may differ from ephys frame index by 1 in some experiments) |
| 2+ | Mean fluorescence intensity for each detected bouton |

---

## 12. Output file reference

| File | Stage | Location |
|------|-------|----------|
| `<run_name>.mat` | 0_1 | `Stage_1_organised/<folder>/` |
| `<run_name>.tif` | 0_1 | `Stage_1_organised/<folder>/<run_name>/` |
| `aligned.tif` | 0_2 | `Stage_2_aligned/<folder>/<run_name>/` |
| `aligned_averages.tif` | 0_2 | `Stage_2_aligned/<folder>/<run_name>/` |
| `unaligned_averages.tif` | 0_2 | `Stage_2_aligned/<folder>/<run_name>/` |
| `transforms.csv` | 0_2 | `Stage_2_aligned/<folder>/<run_name>/` |
| `aligned.tif` | 0_3 | `Stage_2b_cross_aligned/<folder>/<run_name>/` |
| `transforms.csv` | 0_3 | `Stage_2b_cross_aligned/<folder>/<run_name>/` (per-member; same content across the group) |
| `Max_img_filt.tif` | 1_1 | `Stage_3_A1/<folder>/<run_name>/` |
| `max_proj_unscaled.mat` | 1_1 | `Stage_3_A1/<folder>/<run_name>/` (consumed by 1_1b) |
| `Max_img_combined.tif` | 1_1b | `Stage_3_A1/<folder>/<run_name>/` (duplicated across paired runs) |
| `mask.tif` | 1_2 | `Stage_3_A1/<folder>/<run_name>/` (duplicated across paired runs) |
| `bouton_metadata.csv` | 1_2 | `Stage_3_A1/<folder>/<run_name>/` (duplicated across paired runs) |
| `mean_traces.csv` | 1_2 | `Stage_3_A1/<folder>/<run_name>/` (per-run) |
| `bouton_visualisation.tif` | 1_2 | `Stage_3_A1/<folder>/<run_name>/` (duplicated across paired runs) |
| `Analysis_1_Results.mat` | 1_4 | analysis root folder |
| `Analysis_1_template_paired.xlsx` | 1_4 (concatenated) | analysis root folder |
| `Analysis_1_template_split.xlsx` | 1_4 (split) | analysis root folder |

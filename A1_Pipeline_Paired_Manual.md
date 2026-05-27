# Analysis 1 iGluSnFR Analysis Pipeline — User Manual

**Current version:** 260518  
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
9. [Stage 0_3 — Cross-run alignment (calcium paradigm)](#8b-stage-0_3--cross-run-alignment)
10. [Stage 1_1 — Filtering and max projection](#9-stage-1_1--filtering-and-max-projection)
11. [Stage 1_1b — Combined max projection](#9b-stage-1_1b--combined-max-projection)
12. [Stage 1_2 — Active bouton detection](#10-stage-1_2--active-bouton-detection)
13. [Stage 1_4 — Merging data](#11-stage-1_4--merging-data)
14. [Output file reference](#12-output-file-reference)

---

## 1. Overview

This pipeline processes iGluSnFR image stacks acquired alongside WinWCP electrophysiology recordings. It runs in sequential stages, each writing its outputs into a dedicated folder so that any stage can be inspected or re-run independently.

```
raw/                         (your raw data — never modified)

Stage_1_organised/           ← output of Stage 0_1
Stage_2_aligned/             ← output of Stage 0_2
Stage_2b_cross_aligned/      ← output of Stage 0_3 (calcium paradigm only)
Stage_3_A1/                  ← output of Stages 1_1, 1_1b and 1_2
Analysis_1_Results.mat       ← output of Stage 1_4
```

**Stage 0_1** is experiment-specific. **Stages 0_3 and 1_1b** are only used
for the calcium-concentration paradigm, where paired runs of the same ROI
are recorded at two different [Ca²⁺]. They can be left disabled
(`run_stage_0_3 = false`, `run_stage_1_1b = false`) for other experiments —
in that case Stage 1_1 and 1_2 must also be reverted to read from
`Stage_2_aligned/` and `Max_img_filt.tif` respectively. All other stages
are universal. `Analysis_1_Results.mat` will be used for Analysis 2 and
beyond.

---

## 2. Software requirements

- **MATLAB** R2020b or later (earlier versions may work but are untested)
- **Image Processing Toolbox** — required for all stages
- **Parallel Computing Toolbox** — optional but recommended; used for TIFF loading and spatial filtering (falls back to serial automatically if absent)

No additional toolboxes or external packages are required.

---

## 3. Folder structure before you start

Set your MATLAB working directory to the root of the analysis folder (the folder containing `pipeline_config.m`). All paths in the scripts are relative to this location.

### Required files and folders

```
<analysis_root>/
├── pipeline_config.m          ← edit this before running
├── run_pipeline.m             ← runs all stages in sequence
├── Analysis_1_template.xlsx   ← cell spreadsheet (see Section 4)
├── _paradigms/                ← paradigm definition files (see Section 5)
│     └── par<N>.xlsx
├── raw/                       ← raw data (see below)
│     └── <cell_folder>/
│           └── <run_name>/
│                 ├── *.tif
│                 └── *.wcp
└── +A1_funs/                  ← helper functions (do not modify)
```

### Raw data layout

Each cell has its own folder inside `raw/`. The folder name becomes the identifier used throughout the pipeline (it appears in every stage output). Inside each cell folder, each imaging sweep/sub-sweep has its own subfolder.

| File | Description |
|------|-------------|
| `<raw_stack>.tif` | Raw image stack from the camera |
| `*.wcp` | WinWCP electrophysiology file(s); multiple files may be concatenated in time order depending on experiment. |

**For the VAMP experiment multi-part acquisitions**, each run is split across several subfolders named `<run_name>_1`, `<run_name>_2`, etc. (up to 5 parts). The pipeline selects the latest version of each part automatically.

---

## 4. The template spreadsheet

All stages read experiment metadata from an Excel spreadsheet (default: `Analysis_1_template.xlsx`). Row 1 is the header — do not delete it. Each subsequent row describes one imaging run.

| Column | Header | Description |
|--------|--------|-------------|
| 1 | Cell number | Integer index identifying the cell. Used as the primary key into the `Results_A1` struct in Stage 1_4. Multiple runs from the same cell share the same value here. |
| 2 | Folder | Name of the cell folder inside `raw/` (and all stage output folders). |
| 3 | Run name | Name of the run subfolder inside the cell folder. Also used as the base filename for saved `.mat` and `.tif` files. Usually `<ROI>_<run>`. |
| 4 | Run index | Integer index of this run within the cell (e.g. 1, 2, 3…). Importantly, this number represents how many times the cell has been stimulated. |
| 5 | ROI index | Index of the imaged area / field of view (if multiple FOVs were acquired for the same cell). |
| 6 | Paradigm | Paradigm number corresponding to a file in `_paradigms/`. Use `0` if no alignment sub-sweeps are needed (Stage 0_2 will skip registration). Use `x` for paradigm $x$. |
| 7 | Acquisition | `0` = 4 ms global shutter; `1` = 2 ms interleaving shutter. Determines which calculation module is used in Stage 1_4. |

Additional columns (iGluSnFR variant, Construct, Background, Transfected, Data set, Rig, WCP format, etc.) may be present and are ignored by the pipeline scripts.

### Run-name convention for the calcium paradigm

For experiments where the same ROI is recorded at two different external
calcium concentrations, run names follow `<ROI>_<run>_<Ca>mM`, e.g.
`1_3_2mM` = ROI 1, run 3, 2 mM Ca²⁺. The pipeline groups paired runs by
the **ROI-index column (column 5)** — the run name is informative only.
The `<Ca>mM` suffix is parsed by Stage 1_4 to populate the `Calcium_mM`
field in `Results_A1`.

---

## 5. Paradigm files

Paradigm files define how the imaging acquisition is divided into sub-sweeps for motion correction (Stage 0_2) and baseline removal (Stage 1_1).

**Location:** `_paradigms/par<N>.xlsx`, where `<N>` matches the Paradigm column in the template.

**Format:** a single-column table where each row gives the number of frames in one sub-sweep. The rows are read in order and must sum to the total number of acquired frames.

### Currently defined paradigms

| Number | Description | Total frames | Experiments |
|--------|-------------|--------------|-------------|
| 1 | 9× PPR, 1× 5 Hz train | 1700 | DKD and earlier |
| 11 | 20× PPR, 5× 20 Hz trains | 6025 | EM |
| 101 | 20× PPR, 1× 20 Hz 50-AP train, 5× recovery pulses | 8800 | VAMP2 |

To add a new paradigm, create `_paradigms/par<N>.xlsx` with the appropriate frame counts per sub-sweep.

---

## 6. How to run the pipeline

### Quick start

1. Open `pipeline_config.m` and set the three key fields:

   ```matlab
   experiment        = 'EM_825';            % 'EM_707', 'EM_825', or 'VAMP'
   select_f          = 2;                   % Excel row(s) to process
   Analysis_template = 'Analysis_1_template.xlsx';
   ```

2. Set which stages to run (set to `false` to skip a stage you have already completed):

   ```matlab
   run_stage_0_1  = true;
   run_stage_0_2  = true;
   run_stage_0_3  = true;   % cross-run alignment (calcium paradigm)
   run_stage_1_1  = true;
   run_stage_1_1b = true;   % combined max projection (calcium paradigm)
   run_stage_1_2  = true;
   run_stage_1_4  = true;
   ```

3. Run `run_pipeline.m` (press F5 or click Run).

### Running a single stage

Each stage script can also be run independently. Open the script, set `select_f` and `Analysis_template` at the top, and run it directly.

### Processing multiple rows

Set `select_f` to a range or list of Excel row numbers:

```matlab
select_f = 2:10;        % rows 2 through 10
select_f = [2 5 9];     % specific rows
```

---

## 7. Stage 0_1 — Data organisation

**Scripts:** `Analysis_0_1_concatenation_EM_707.m`, `Analysis_0_1_concatenation_EM_825.m`, `Analysis_0_1_concatenation_VAMP.m`

This stage reorganises raw data into a consistent structure and concatenates multi-file recordings.

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template.xlsx` | Defines which runs to process |
| `raw/<folder>/<run_name>/` | Raw image stack (`.tif`) and WinWCP files (`.wcp`) |

For **EM_707 and EM_825**, the WCP files within each run folder are matched by filename pattern and concatenated in time order. The patterns expected are:

```
*_001.iGluSnFR_2ms_PPR_6025f_1.*.wcp
*_001.iGluSnFR_2ms_PPR_6025f_2*.wcp
*_001.iGluSnFR_2ms_train_6025f_3.*.wcp
```

However, some recordings were taken with the following pattern:

```
*_001.Prot1_10x_PPR_v2_5300f.*.wcp
*_001.Prot2_10x_PPR_v2.*.wcp
*_001.Prot3_20Hz_multiTrain.*.wcp;
```

For **VAMP**, five sub-folders (`<run_name>_1` through `<run_name>_5`) are stitched together. If a sub-folder has multiple versions (e.g. `<run_name>_2_3`), the latest version is selected automatically.

### Channel assignments

| Channel in output (`Y`) | 707 rig source | 825 rig source |
|--------------------------|---------------|----------------------|
| Column 1 — current (pA) | AI0 | AI0 |
| Column 2 — command voltage | AI1 | AI1 |
| Column 3 — camera exposure | AI3 | AI5 |
| Column 4 — camera trigger | AI4 | AI3 |

### Output

```
Stage_1_organised/
  └── <folder>/
        ├── <run_name>.mat        (T and Y arrays — ephys data)
        └── <run_name>/
              └── <run_name>.tif  (image stack, concatenated from raw/)
```

| File | Description |
|------|-------------|
| `<run_name>.mat` | MATLAB workspace containing `T` (time vector, seconds) and `Y` (electrophysiology matrix, columns as above) |
| `<run_name>.tif` | Copy of the raw image stack |

---

## 8. Stage 0_2 — X-Y alignment

**Script:** `Analysis_0_2_alignment.m`

Corrects inter-sweep XY drift by registering each sub-sweep to the first, then applies the transforms to every frame within that sub-sweep.

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template.xlsx` | Defines which runs to process and their paradigm number |
| `Stage_1_organised/<folder>/<run_name>/<run_name>.tif` | Concatenated image stack |
| `_paradigms/par<N>.xlsx` | Sub-sweep frame counts |

### Algorithm

1. The image stack is split into sub-sweeps according to the paradigm file.
2. A mean image is computed for each sub-sweep.
3. The first sub-sweep mean is used as the reference (anchor).
4. Each subsequent sub-sweep mean is registered to the anchor using `imregtform()` (2D translation, monomodal intensity-based, up to 300 iterations).
5. The resulting translation transform is applied to every individual frame in that sub-sweep using `imwarp()` with linear interpolation.
6. Pixels that receive no data after any translation (zero-padded borders) are identified across the whole time series, and the stack is cropped to the region valid in all frames.
7. The ephys `.mat` file is copied forward to `Stage_2_aligned/`.

If the Paradigm column is `0` for a run, alignment is skipped (the stack is copied through unchanged).

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
| Gaussian blur for registration | σ = 2 px | Applied to sub-sweep means before registration to improve robustness |

---

## 8b. Stage 0_3 — Cross-run alignment

**Script:** `Analysis_0_3_cross_run_alignment.m`

Used only for the **calcium-concentration paradigm**, where the same ROI of
a cell is recorded twice at two different external [Ca²⁺]. Stage 0_3
co-registers same-ROI runs in 2D so they share a single coordinate frame.
This is what makes a shared bouton mask across the pair possible
(Stages 1_1b, 1_2).

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template.xlsx` | Defines which rows to process |
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
   identical optimizer settings to Stage 0_2: 300 iterations, max step
   0.0625, relaxation 0.5).
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
   the script prints a `[WARN]` line — this is the symptom you see when
   two runs were labelled as the same ROI but are actually different
   fields of view, so registration could not find a real match. The NCC
   values are also written to `transforms.csv` for later inspection.

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

Denoises the image stack and produces a maximum-intensity projection used for bouton detection.

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template.xlsx` | Defines runs and paradigm |
| `Stage_2b_cross_aligned/<folder>/<run_name>/aligned.tif` | Cross-aligned image stack |
| `_paradigms/par<N>.xlsx` | Sub-sweep frame counts (for baseline removal) |

### Algorithm

1. **Spatial filtering** — applied frame by frame (parallelised):
   - Wiener filter (5 × 5 window)
   - Median filter (3 × 3 window)
2. **Temporal filtering** — applied pixel by pixel (parallelised):
   - Baseline removal using the SNIP algorithm (sub-sweep by sub-sweep, using paradigm file)
   - Binomial smoothing filter (order 3)
   - A constant offset of +2000 is added before scaling to `uint16` to prevent clipping at zero after baseline subtraction
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

Used only for the **calcium-concentration paradigm**. Combines the per-run
max projections of all members of a `(Cell, ROI)` group into a single
projection so that Stage 1_2 detects boutons jointly across both Ca²⁺
conditions. A bouton that is silent at one concentration but active at the
other is still detected, as long as it appears in *either* projection.

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template.xlsx` | Defines runs to process |
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

This is amplitude-preserving: a dim run contributes proportionally less
to the combined max than a bright run, instead of being stretched up to
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
  `Max_img_filt.tif` (same content, re-scaled to uint16 from the
  unscaled projection).

---

## 10. Stage 1_2 — Active bouton detection

**Script:** `Analysis_1_2_abd.m`

Detects individual synaptic boutons in the maximum projection and extracts their fluorescence time traces from the aligned image stack.

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template.xlsx` | Defines which runs to process |
| `Stage_3_A1/<folder>/<run_name>/Max_img_combined.tif` | Combined max projection (for segmentation) |
| `Stage_2b_cross_aligned/<folder>/<run_name>/aligned.tif` | Full image stack (for trace extraction) |

### Algorithm

1. **Adaptive thresholding** — the max projection is thresholded locally using a sliding window (`adaptthresh`). Pixels brighter than their local neighbourhood (scaled by the threshold parameter) form a binary mask.
2. **Morphological cleaning** — the mask is opened then closed with a disk structuring element (radius 2 px) to remove small speckles and fill gaps.
3. **Watershed separation** — touching boutons are separated using a marker-controlled watershed. A combined image is formed from the inverted intensity and the inverted distance transform (weighted 0.8 / 0.2). H-minima suppression prevents over-segmentation of noisy flat regions. The watershed ridge lines are applied as boundaries.
4. **Label and extract** — each connected component in the final mask is labelled, region properties are computed, and the nearest-neighbour distance matrix is calculated.
5. **Trace extraction** — the mean pixel intensity within each bouton mask is extracted for every frame of the aligned stack.

For the calcium paradigm, paired runs share the same combined max
projection input, so the bouton mask, metadata, and visualisation files
will be identical across the runs of a pair. Trace extraction still runs
independently against each run's own aligned stack, so `mean_traces.csv`
differs between paired runs. Bouton indices are comparable across the
pair.

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
| Threshold fraction | `adaptive_threshold` | 0.4 | Sensitivity of adaptive thresholding (0–1; increase to detect fewer, dimmer boutons) |
| Threshold window | `w` | 15 | Neighbourhood size for adaptive threshold (pixels, odd) |
| Intensity/distance weight | `weight` | 0.8 | Balance between intensity (1.0) and distance transform (0.0) in the watershed input |
| H-minima depth | `h` | 0.02 | Minimum depth of a local minimum to be treated as a separate bouton; increase to merge more touching boutons |

---

## 11. Stage 1_4 — Merging data

**Script:** `Analysis_1_4_merging_data.m`

Aggregates all per-run outputs into a single MATLAB struct (`Results_A1`) saved as `Analysis_1_Results.mat`.

### Input

| Source | Description |
|--------|-------------|
| `Analysis_1_template.xlsx` | Defines which runs to merge and their metadata |
| `Stage_3_A1/<folder>/<run_name>/bouton_metadata.csv` | Bouton shape properties |
| `Stage_3_A1/<folder>/<run_name>/mean_traces.csv` | Fluorescence traces |
| `Stage_3_A1/<folder>/<run_name>/mean_traces_plus_rings.mat` | Ring traces (optional; included if present) |
| `Stage_3_A1/<folder>/<run_name>.mat` | Ephys data for frame and AP timing |

### Algorithm

For each run, the script:

1. Loads bouton metadata and traces from `Stage_3_A1/`.
2. Loads the ephys data and runs the appropriate **Calculation Unit Module** to extract frame timing and action potential timing:
   - `Calculation_Unit_Module_Analysis_1_4_new.m` — for interleaving acquisition (Acquisition column = 1)
   - `Calculation_Unit_Module_Analysis_1_4_old.m` — for global-shutter acquisition (Acquisition column = 0)
3. Stores all data into the `Results_A1` struct at the index given by the Cell number column.
4. Saves `Analysis_1_Results.mat` after each row so progress is not lost if an error occurs.

### Output

**`Analysis_1_Results.mat`** — contains a struct array `Results_A1`. Each element corresponds to one cell (indexed by the Cell number column). Within each element:

| Field | Description |
|-------|-------------|
| `Folder` | Cell folder name |
| `Run_name` | Run name(s) for this cell |
| `Run_index` | Run index number(s) |
| `Imaged_area_index` | ROI index |
| `Paradigm` | Paradigm number |
| `Acquisition` | Acquisition mode |
| `Calcium_mM` | External [Ca²⁺] in mM, parsed from the `<Ca>mM` suffix of the run name (calcium paradigm). `NaN` if the suffix is absent. |
| `Frame_data(run).data` | Frame timing (see below) |
| `AP_data(run).data` | Action potential timing (see below) |
| `Bouton_metadata(run).data` | Same as `bouton_metadata.csv` (identical across paired runs in the calcium paradigm) |
| `Bouton(run).data` | Frame index + mean fluorescence per bouton (per-run, but bouton indices match across a pair) |
| `Bouton_rings(run).data` | Ring traces (if available) |

### Frame_data columns (new acquisition, Acquisition = 1)

`Results_A1(cell).Frame_data(run).data{1,1}`:

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

Columns 8-11 are only present for new interleafing shutter data.

`Results_A1(cell).Frame_data(run).data{1,j}` for j > 1:

| j | Content |
|---|---------|
| 2 | Mean frame period (seconds) |
| 3 | Mean t1 (seconds) |
| 4 | Mean t2 (seconds) |

`t1` and `t2` are needed to correct for the AP frame if needed in Analysis 2 and beyond. They are again only present in the new data.

### AP_data columns

`Results_A1(cell).AP_data(run).data{1,1}`:

| Column | Description |
|--------|-------------|
| 1 | AP index |
| 2 | Frame where AP belongs (adjusted) |
| 3 | AP peak — ephys sample index |
| 4 | AP peak — seconds |
| 5 | AP amplitude (pA) |
| 6 | True frame (shifted by −1 when the number of processed imaging frames differs from the electrophysiology frame count — This column is always used in downstream analysis) |

### Bouton data columns

`Results_A1(cell).Bouton(run).data`:

| Column | Description |
|--------|-------------|
| 1 | Frame index (image-corrected; may differ from ephys frame index by 1 in some experiments) |
| 2+ | Mean fluorescence intensity for each detected bouton |

---

## 12. Output file reference

Summary of all files produced across stages:

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

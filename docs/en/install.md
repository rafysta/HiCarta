# Installation

HiCarta runs on your own machine as a local Shiny app. No server or account is
needed.

## 1. Install R

Install R (≥ 4.1) from <https://cran.r-project.org>.

- **Windows** — the installer puts R under `C:\Program Files\R\R-x.y.z`. The
  launcher finds it automatically.
- **macOS** — the CRAN `.pkg`, or `brew install --cask r`.

You do **not** need RStudio, but it is fine to have it.

## 2. Get HiCarta

```
git clone https://github.com/rafysta/HiCarta.git
```

or download the ZIP from GitHub and extract it.

## 3. First launch (installs R packages)

- **Windows** — double‑click `run_windows.bat`
- **macOS** — double‑click `run_mac.command`

On the first run the launcher checks for the required packages and, if any are
missing, runs `R/install_libraries.R`. Required packages:

| Package | Source | Purpose |
|---|---|---|
| shiny, leaflet, htmlwidgets, base64enc | CRAN | app + tiled map |
| data.table | CRAN | fast text reading |
| RColorBrewer | CRAN | colour palettes |
| strawr | CRAN | random access to `.hic` |
| rtracklayer | Bioconductor | bigWig / BED tracks |

> `rtracklayer` comes from Bioconductor and can take a few minutes to install the
> first time. This is normal.

To install everything manually instead:

```r
source("R/install_libraries.R")
```

## 4. Run

The app opens a browser tab at `http://127.0.0.1:7788`. To stop it, close the
launcher window (Windows) or press `Ctrl+C` / close the Terminal window (macOS).
If port 7788 is busy, the launcher closes the previous instance automatically.

---

## Troubleshooting

**"Could not find Rscript"** — R is not installed or not on `PATH`. Install R,
then relaunch. On Windows the launcher also scans `C:\Program Files\R\`.

**`rtracklayer` fails to install** — make sure you have internet access on the
first run. You can install it directly:

```r
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
BiocManager::install("rtracklayer")
```

**Nothing appears / blank map** — confirm a dataset is loaded in the **Data**
panel and a region is set in **Region**, then click **Open map**.

**Slow first open of a remote `.hic`** — the file is downloaded once into
`_hic_cache/`. Later opens read from that cache and are fast. Delete
`_hic_cache/` to reclaim disk space (it will re‑download on demand).

**macOS "cannot be opened because it is from an unidentified developer"** —
right‑click `run_mac.command` → Open, or run `chmod +x run_mac.command` once.

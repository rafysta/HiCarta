# HiCarta

**Interactive Hi-C contact map viewer** built with R + Shiny + Leaflet.

![](images/overview.png)

HiCarta lets you explore Hi-C contact maps like a web map — **drag to pan, scroll
to zoom**. It streams only the tiles you are looking at, so it stays responsive on
high‑resolution maps and large genomes, reads `.hic` files directly, and overlays
1‑D tracks (bigWig, BED, gene models, Border Strength).

<div class="grid cards" markdown>

- :material-download: **[Installation](install.md)** — install R and launch the app
- :material-book-open-variant: **[Usage](usage.md)** — load data, navigate, add tracks
- :material-file-table: **[Data formats](data-formats.md)** — `.hic`, tracks, hic200 conversion

</div>

## What it does

- Reads `.hic` (Juicer) with random access via `strawr`, switching resolution with
  zoom (level of detail).
- Renders 256 px tiles on demand; a single absolute colour scale keeps tiles
  seamless.
- Caches remote `.hic` / bigWig locally after the first open for fast reloads.
- Overlays synced 1‑D tracks: bigWig, BED, gene models (GFF3), Border Strength.

## Quick start

1. Install R (≥ 4.1) from <https://cran.r-project.org>.
2. `git clone https://github.com/rafysta/HiCarta.git`
3. Double‑click `run_windows.bat` (Windows) or `run_mac.command` (macOS). The
   first launch installs the required R packages.
4. A browser tab opens at `http://127.0.0.1:7788`.

See **[Installation](install.md)** for details.

---

Created by **Hideki Tanizawa** (<rafysta@gmail.com>).
Source: [github.com/rafysta/HiCarta](https://github.com/rafysta/HiCarta) ·
Released under the MIT License.

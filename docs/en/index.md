# HiCarta

An **interactive Hi-C contact map viewer**. The name comes from *Carta* — "nautical chart" in Italian and Latin — reflecting the idea of freely navigating and drawing a Hi-C contact map.

![](../images/overview.png){ width="697" }

HiCarta lets you explore a Hi-C contact map like Google Maps — **drag to pan, scroll to zoom**. It loads only the tiles currently in view, so it stays responsive even on high-resolution maps and large genomes. It reads `.hic` files directly and overlays 1-D tracks (bigWig, BED, gene models, Border Strength).

<div class="grid cards" markdown>

- :material-download: **[Installation](install.md)** — up and running in 3 steps (Windows)
- :material-star-four-points: **[What HiCarta can do](features.md)** — the full feature list
- :material-book-open-variant: **[Usage](usage.md)** — a task-oriented how-to guide
- :material-view-dashboard-outline: **[Screens & controls](interface.md)** — details of each menu
- :material-file-table: **[Data formats](data-formats.md)** — `.hic`, tracks, hic200 conversion

</div>

## What you can do

- Read `.hic` (Juicer format) and switch resolution as you zoom (level of detail).
- Overlay multiple 1-D tracks (bigWig, BED, gene models (GFF3), Border Strength) synced to the map.
- Bookmark regions of interest, and save/restore the whole view as a session.
- Export a chosen region as a high-quality, publication-ready image (PNG / PDF) or print it.

For the complete list, see **[What HiCarta can do](features.md)**.

## Quick start (Windows)

1. Install R (4.1 or later) from <https://cran.r-project.org>.
2. Get it from [GitHub](https://github.com/rafysta/HiCarta) via **Code → Download ZIP** and unzip.

    ![](../images/download.png){ width="400" }

3. Double-click `run_windows.bat`. On first launch, the required R packages are installed automatically.
4. The app opens in your default browser.

See **[Installation](install.md)** for details, and **[Setup details](setup-details.md)** for macOS and manual installation.

---

Author: **Hideki Tanizawa** (<rafysta@gmail.com>)
Source: [github.com/rafysta/HiCarta](https://github.com/rafysta/HiCarta) ·
Released under the MIT License.

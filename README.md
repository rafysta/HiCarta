# HiCarta
**Interactive Hi-C contact map viewer** built with R + Shiny + Leaflet.

📖 **Documentation site: <https://rafysta.github.io/HiCarta/>**

![](https://rafysta.github.io/HiCarta/images/overview.png)

HiCarta lets you explore Hi-C contact maps like a web map: **drag to pan, scroll to
zoom**. It streams only the tiles you are looking at, so it stays fast even on
high‑resolution maps and large genomes. It reads `.hic` files directly (via
`strawr`) and overlays 1‑D tracks (bigWig, BED, gene models, Border Strength).

> HiCarta is a rewrite of an older Java viewer that loaded whole text matrices
> into memory and broke on large data. Every reader now takes a `(chr, start, end)`
> region and returns only that block.

---

## Quick start

1. **Install R** (≥ 4.1) from <https://cran.r-project.org>.
2. Download or `git clone` this repository.
3. Launch:
   - **Windows** — double‑click `run_windows.bat`
   - **macOS** — double‑click `run_mac.command` (if Gatekeeper blocks it,
     right‑click → Open, or run `chmod +x run_mac.command` once)
   The first launch installs the required R packages automatically (the
   Bioconductor package `rtracklayer`, used for tracks, can take a few minutes).
4. A browser tab opens at `http://127.0.0.1:7788`. Use the top menu
   (**Data / Region / Display / Tracks / Setting / About**) to drive the app.

See **[docs/install.md](docs/install.md)** for detailed installation and
troubleshooting, and **[docs/usage.md](docs/usage.md)** for a full walkthrough.

---

## How it works (tiled rendering)

Instead of reading a whole chromosome, HiCarta renders the map as **256 px tiles**,
the same way an online map does. Leaflet's `GridLayer` requests only the visible
tiles and evicts distant ones. For each tile, HiCarta reads just that 2‑D block
from the `.hic` at the resolution matching the current zoom (level‑of‑detail),
colours it, and serves it as a PNG on demand (`session$registerDataObj`). The
coordinate origin is **top‑left**; genomic *y* increases downward.

Colours use a single **absolute value scale** shared across all tiles so seams do
not appear; the initial `Max` is chosen from a coarse full‑map pass on Open.
Remote `.hic` files are downloaded once into `_hic_cache/` and read locally
afterwards (first open waits, later opens are fast).

---

## Repository layout

```
app.R                 Shiny entry point (UI + Leaflet + tile server)
config.txt            Startup defaults (menu / track URLs)
run_windows.bat       Windows launcher (double-click)
run_mac.command       macOS launcher (double-click)
R/
  readers.R           .hic / .rds / .matrix.gz -> region matrix (strawr) + cache
  tiles.R             tile rendering ((z,x,y) -> region -> PNG)
  draw.R              colouring (palette, value scale) + PNG raster
  juicer_menu.R       Juicer menu parser ("id = parent, label[, url]")
  tracks.R            bigWig / BED tracks (rtracklayer)
  genes.R             gene track (GFF3)
  borderstrength.R    Border Strength track (*_BS.txt)
  install_libraries.R installs required packages
scripts/              utility scripts (e.g. hic200 -> .hic conversion)
docs/                 documentation source (served via GitHub Pages / MkDocs)
sample/               small test fixtures (S. pombe)
mkdocs.yml            documentation site config
.github/workflows/    CI: builds & deploys the docs site
```

Runtime folder `_hic_cache/` (downloaded `.hic` / bigWig) is created on first use
and is not tracked by git.

---

## Data formats

| Format | Use | Reader |
|---|---|---|
| `.hic` (Juicer) | contact maps | `strawr` (random access, multi‑resolution) |
| bigWig | quantitative track | `rtracklayer` |
| BED | interval track | `rtracklayer` |
| GFF3 | gene model track | `R/genes.R` (parsed + cached) |
| `*_BS.txt` | Border Strength track | `R/borderstrength.R` |

hic200‑cpp raw maps (`.txt.gz`) are converted to `.hic` first (with
`scripts/convert_hic200_to_hic.sh`), then loaded as a local `.hic`. See
**[docs/data-formats.md](docs/data-formats.md)**.

---

## Configuration

Copy **`config.example.txt`** to **`config.txt`** (same folder as `app.R`) and set
your own URLs. `config.txt` is **git‑ignored**, so your data URLs stay local and
are never committed. The app also runs **without** `config.txt` — the input fields
simply start empty and you paste a URL or load a local `.hic` by hand.

```
menu_url       = <URL or local path to a Juicer menu>   # default .hic menu (Data panel)
track_list_url = <URL to an IGV XML or an index file>   # default track list (Tracks panel)
language       = en                                     # interface language (en = English [default], ja = Japanese)
```

`language` is read once at startup. It defaults to English (`en`); setting
`language = ja` in `config.txt` switches the whole interface to Japanese. Extra
languages can be added in `R/i18n.R`.

`track_list_url` may be a single IGV XML or an index file listing several IGV XML
URLs (one per line). A public *S. pombe* test menu is noted in
[sample/README.md](sample/README.md).

---

## Documentation

- **Online docs: <https://rafysta.github.io/HiCarta/>**
- [日本語 README](README_ja.md)
- [docs/install.md](docs/install.md) — installation & troubleshooting
- [docs/usage.md](docs/usage.md) — full usage walkthrough
- [docs/data-formats.md](docs/data-formats.md) — supported formats & conversion

---

## Author & license

Created by **Hideki Tanizawa** (<rafysta@gmail.com>).
Released under the [MIT License](LICENSE).

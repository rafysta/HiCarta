# HiCarta
**Interactive Hi-C contact map viewer** built with R + Shiny + Leaflet.

📖 **Documentation site: <https://rafysta.github.io/HiCarta/>**

![](https://rafysta.github.io/HiCarta/images/overview.png)

HiCarta lets you explore Hi-C contact maps like a web map: **drag to pan, scroll to
zoom**. It streams only the tiles you are looking at, so it stays fast even on
high‑resolution maps and large genomes. It reads `.hic` files directly (a pure-R
reader streams remote files over HTTP range requests) and overlays 1‑D tracks
(bigWig, BED, gene models, Border Strength). All data is organised in an
**Excel data catalog** — one spreadsheet row per sample — that the app turns
into a filterable sample browser.

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
   (**Data / Navigate / Display / Print / Setting / About**) to drive the app.
5. Click **Data**, load a data catalog (`.xlsx`; a template ships as
   `HiCarta_catalog_template.xlsx`), and click a sample to open it.

See **[docs/install.md](docs/en/install.md)** for detailed installation and
troubleshooting, and **[docs/usage.md](docs/en/usage.md)** for a full walkthrough.

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
Remote `.hic` and bigWig files are **streamed over HTTP range requests** by
default — only the bytes in view are fetched. Setting `hic_engine = download`
in `config.txt` instead fetches each file once into `_hic_cache/`.

---

## Repository layout

```
app.R                 Shiny entry point (UI + Leaflet + tile server)
config.txt            Startup defaults (catalog URL, language, engine)
run_windows.bat       Windows launcher (double-click)
run_mac.command       macOS launcher (double-click)
HiCarta_catalog_template.xlsx  ready-to-copy data catalog template
R/
  catalog.R           Excel data catalog (.xlsx): reading, validation, filters
  bookmarks.R         bookmark <-> .xlsx exchange
  hic_reader.R        pure-R .hic reader (HTTP range streaming)
  bigwig_reader.R     pure-R bigWig reader (HTTP range streaming)
  readers.R           engine selection + region matrix + cache
  tiles.R             tile rendering ((z,x,y) -> region -> PNG)
  draw.R              colouring (palette, value scale) + PNG raster
  tracks.R            track drawing; legacy IGV XML parser
  genes.R             gene track (GFF3)
  borderstrength.R    Border Strength track (*_BS.txt)
  chrominfo.R         chromosome names/lengths from a track file (no-map mode)
  juicer_menu.R       legacy Juicer menu parser (for conversion scripts)
  i18n.R              interface strings (English / Japanese)
  install_libraries.R installs required packages
scripts/              converters (catalog <-> legacy formats, hic200 -> .hic)
docs/                 documentation source (served via GitHub Pages / MkDocs)
sample/               small test fixtures (S. pombe)
mkdocs.yml            documentation site config
.github/workflows/    CI: builds & deploys the docs site
```

Runtime folder `_hic_cache/` (downloaded `.hic` / bigWig) is created on first use
and is not tracked by git.

---

## Data formats

Everything is opened from the **data catalog** (`.xlsx`, one row per sample) —
see the [Data catalog docs](https://rafysta.github.io/HiCarta/data-catalog/).

| Format | Use | Reader |
|---|---|---|
| `.hic` (Juicer) | contact maps | `R/hic_reader.R` (random access, multi‑resolution, HTTP streaming) |
| bigWig | quantitative track | `R/bigwig_reader.R` (HTTP streaming) |
| BED | interval track | `rtracklayer` |
| GFF3 | gene model track | `R/genes.R` (parsed + cached) |
| `*_BS.txt` | Border Strength track | `R/borderstrength.R` |

hic200‑cpp raw maps (`.txt.gz`) are converted to `.hic` first (with
`scripts/convert_hic200_to_hic.sh`), then opened via the catalog. See
**[docs/data-formats.md](docs/en/data-formats.md)**.

---

## Configuration

Copy **`config.example.txt`** to **`config.txt`** (same folder as `app.R`) and set
your own values. `config.txt` is **git‑ignored**, so your data URLs stay local and
are never committed. The app also runs **without** `config.txt` — you just load a
catalog by hand in the Data browser. Everything below is also editable in-app via
**Setting → Edit config file…**.

```
catalog_url = <URL or local path of the data catalog .xlsx>  # default catalog (Data browser)
language    = en          # interface language (en = English [default], ja = Japanese)
hic_engine  = native      # remote files: native = HTTP streaming, download = fetch whole file
igv_genome  =             # genome id sent with "Open in IGV" (e.g. hg38; empty = don't send)
```

`language` is read once at startup. It defaults to English (`en`); setting
`language = ja` in `config.txt` switches the whole interface to Japanese. Extra
languages can be added in `R/i18n.R`.

Old Juicer-style menus and IGV track-list XMLs convert to and from the catalog
with the scripts in `scripts/` (see
[scripts/README.md](scripts/README.md)).

---

## Documentation

- **Online docs: <https://rafysta.github.io/HiCarta/>**
- [日本語 README](README_ja.md)
- [docs/install.md](docs/en/install.md) — installation & troubleshooting
- [docs/usage.md](docs/en/usage.md) — full usage walkthrough
- [docs/data-catalog.md](docs/en/data-catalog.md) — the Excel data catalog
- [docs/data-formats.md](docs/en/data-formats.md) — supported formats & conversion

---

## Author & license

Created by **Hideki Tanizawa** (<rafysta@gmail.com>).
Released under the [MIT License](LICENSE).

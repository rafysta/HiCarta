# Setup details & troubleshooting

This page collects the extra details and troubleshooting for when the 3 steps in **[Installation](install.md)** weren't enough. If it already starts fine, you don't need to read this.

## Get it with Git (instead of the ZIP)

Instead of downloading the ZIP, if you have Git installed you can also get it with the following command. This makes it easier to pull in updates.

```
git clone https://github.com/rafysta/HiCarta.git
```

## Start it on a Mac

It works on a Mac too.

1. Install R (4.1 or later) from <https://cran.r-project.org> (the CRAN `.pkg`, or `brew install --cask r`).
2. Download and unzip HiCarta.

    ![](../images/download.png){ width="400" }

3. Double-click **`run_mac.command`** in the folder.

If it won't open and shows "cannot be opened because the developer cannot be verified", **right-click `run_mac.command` → "Open"** to start it. Or run the following once in the terminal:

```
chmod +x run_mac.command
```

To stop the app, press `Ctrl+C` in the terminal window or close the window.

## Required R packages

On first launch, the launcher checks for missing packages and, if needed, runs `R/install_libraries.R` to install them automatically. The breakdown is:

| Package | Source | Purpose |
|---|---|---|
| shiny, leaflet, htmlwidgets, base64enc | CRAN | The app + tile map |
| data.table | CRAN | Fast text reading |
| RColorBrewer | CRAN | Color palettes |
| jsonlite | CRAN | Saving/restoring sessions |
| shinyFiles | CRAN | The "Browse…" dialog for local files |
| curl | CRAN | HTTP range reads for remote `.hic` and bigWig |
| strawr | CRAN | *Optional.* Fallback `.hic` reader; not needed normally |
| rtracklayer | Bioconductor | BED tracks (bigWig is read by the built-in reader) |

!!! note "rtracklayer takes time"
    `rtracklayer` comes from Bioconductor, so the first install can take a few minutes. This is normal.

Only if you want to install the packages manually all at once, start R and run:

```r
source("R/install_libraries.R")
```

## How starting and stopping works

The app opens a browser tab at `http://127.0.0.1:7788`. To stop it, on Windows close the launcher window (Command Prompt), and on macOS press `Ctrl+C` in the terminal or close the window. If port 7788 is already in use, the launcher automatically terminates the previous instance before starting.

---

## Troubleshooting

### "Could not find Rscript" appears

R is not installed, or it is not on your `PATH`. Install R and start again. On Windows the launcher also searches `C:\Program Files\R\`.

### `rtracklayer` fails to install

Make sure you're connected to the internet on first launch. If it still doesn't work, start R and install it directly:

```r
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
BiocManager::install("rtracklayer")
```

### Nothing shows / the map is blank

Check that a dataset is loaded in **Data**, that a region is set in **Navigate**, then click **Open map**.

### A remote `.hic` or track feels slow

Remote `.hic` files are **streamed**: only the part of the map you are looking at is fetched, over HTTP range requests on a single kept-alive connection, and nothing is written to disk. Panning and zooming within a region you have already visited is served from memory and costs no network traffic at all.

If your connection is slow or unreliable, downloading the whole file once can end up smoother. Switch with **Setting → Edit config file… → Remote file reading**, or set it by hand in `config.txt`:

```
hic_engine = download     # fetch the whole file into _hic_cache/ first
hic_engine = native       # stream (default)
```

This setting covers **bigWig tracks too**. rtracklayer cannot open a remote bigWig at all (`Couldn't open ... UCSC library operation failed`), so HiCarta reads them with its own streaming reader. BED, GFF3 and Border Strength tracks are parsed whole and are always downloaded, whatever this is set to.

Under `download`, files accumulate in `_hic_cache/`; you can delete that folder at any time to free space (it will be re-fetched when needed).

There is a third value, `strawr`, which uses the legacy [strawr](https://cran.r-project.org/package=strawr) reader. It exists for diagnostics only and is very slow for URLs — `strawr::readHicNormTypes()` has no HTTP code path, so it spins for ~30 s per call and returns an incomplete normalization list.

### Change the startup defaults (config.txt)

Defaults such as the menu URL, track list and interface language are saved in `config.txt` in the same folder as the app. You can edit them from **Setting → Edit config file…** inside the app (see **[Screens & controls](interface.md)** for details). To edit it manually, copy `config.example.txt` to `config.txt` and edit it.

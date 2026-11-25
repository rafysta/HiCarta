# Setup details & troubleshooting

This page provides detailed setup instructions and troubleshooting guidance if the steps in **[Installation](install.md)** do not work for you.

## Get it with Git (instead of the ZIP)

If Git is installed, you can clone the repository instead of downloading the ZIP file. This makes it easier to retrieve future updates.

```
git clone https://github.com/rafysta/HiCarta.git
```

## Start it on macOS

Follow these steps to start HiCarta on macOS.

1. Install R (4.1 or later) from <https://cran.r-project.org> (the CRAN `.pkg`, or `brew install --cask r`).
2. Download and unzip HiCarta.

    ![](../images/download.png){ width="400" }

3. Double-click **`run_mac.command`** in the folder.

If macOS blocks the launcher with a message such as "cannot be opened because the developer cannot be verified", try **right-click `run_mac.command` → "Open"**. If the file lacks execute permission, run the following command once in the terminal from the HiCarta directory:

```
chmod +x run_mac.command
```

To stop the app, press `Ctrl+C` in the terminal window or close the window.

## Required R packages

On first launch, the launcher checks for missing packages and, if needed, runs `R/install_libraries.R` to install them automatically. The packages and their purposes are listed below:

| Package | Source | Purpose |
|---|---|---|
| shiny, leaflet, htmlwidgets, base64enc | CRAN | Application interface and tile-based map display |
| data.table | CRAN | Fast text-file parsing |
| RColorBrewer | CRAN | Color palettes |
| jsonlite | CRAN | Saving/restoring sessions |
| shinyFiles | CRAN | The "Browse…" dialog for local files |
| curl | CRAN | HTTP range requests for remote `.hic` and bigWig |
| strawr | CRAN | *Optional.* Fallback `.hic` reader; not normally required |
| rtracklayer | Bioconductor | BED tracks (bigWig is read by the built-in reader) |

!!! note "Installing rtracklayer"
    `rtracklayer` comes from Bioconductor, so the initial installation can take a few minutes. This is normal.

To install the required packages manually, start R with the HiCarta folder as the working directory and run:

```r
source("R/install_libraries.R")
```

## How starting and stopping works

HiCarta starts a local web server and opens a browser tab at `http://127.0.0.1:7788`. To stop it, on Windows close the launcher window (Command Prompt), and on macOS press `Ctrl+C` in the terminal or close the window. If port 7788 is already in use, the launcher automatically terminates the previous instance before starting.

---

## Troubleshooting

### "Could not find Rscript" appears

R may not be installed, or `Rscript` may not be available on your `PATH`. Install R if necessary and relaunch HiCarta. On Windows the launcher also searches `C:\Program Files\R\`.

### `rtracklayer` fails to install

Ensure that you have an internet connection on first launch. If installation still fails, start R and install it directly:

```r
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
BiocManager::install("rtracklayer")
```

### Nothing shows / the map is blank

Check that a dataset is loaded in **Data** and that a valid region is selected in **Navigate**, then click **Open map**.

### A remote `.hic` or track feels slow

By default, remote `.hic` files are **streamed**: HiCarta retrieves only the required data via HTTP range requests and reuses the connection. The `.hic` file is not saved to disk as a whole. Cached data are retrieved from memory rather than fetched again.

If your connection is slow or unreliable, downloading the entire file first may improve subsequent navigation. Change the mode via **Setting → Edit config file… → Remote file reading**, or configure it manually in `config.txt`:

```
hic_engine = download     # fetch the whole file into _hic_cache/ first
hic_engine = native       # stream (default)
```

This setting also applies to **bigWig tracks**. rtracklayer may fail to open a remote bigWig (`Couldn't open ... UCSC library operation failed`), so HiCarta reads them with its own streaming reader. Remote BED, GFF3, and Border Strength files are downloaded and parsed in full, regardless of this setting.

In `download` mode, files are saved in `_hic_cache/`. To free space, quit the app and delete that folder (files are fetched again when needed).

There is a third value, `strawr`, which uses the legacy [strawr](https://cran.r-project.org/package=strawr) reader. It is intended for diagnostic use only and can be very slow for remote URLs — `strawr::readHicNormTypes()` has no HTTP code path, so each call takes a long time and may not return the full list of normalizations.

### Change the startup defaults (config.txt)

Defaults such as the catalog URL, remote-file reading mode, IGV genome ID, interface language and the AWS profile for private S3 data are saved in `config.txt` in the same folder as the app. You can edit them from **Setting → Edit config file…** in HiCarta (see **[Screens & controls](interface.md)** for details). To edit it manually, copy `config.example.txt` to `config.txt` and edit it.

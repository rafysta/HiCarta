# Plugins: create custom tracks in R

A **plugin** is an R script that adds a custom track type to HiCarta. Typically, you define two functions: one to read data for the visible genomic region and one to render those data. HiCarta integrates the plugin with the data catalog, the "Add as track" button, the Tracks panel and settings dialog, session files, and print preview and export. The track uses the same X-axis range as the contact map.

Typical applications include custom scores (e.g., insulation scores, eigenvectors, or other per-bin values), plots your lab already generates in R, and visualizations derived directly from `.hic` files, such as the included **Virtual 4C** plugin.

!!! note "Plugin directory"
    Every `*.R` file in the **`plugins/`** folder next to `app.R` is loaded when HiCarta starts and whenever the page is reloaded. After editing a plugin, simply reload the browser tab. To use another directory, set
    `plugin_dir` in `config.txt` (**Setting → Edit config file…**). The
    **About** panel lists the loaded plugins and reports errors for files that failed to load.

## Quick start

Two example plugins are included in the `plugins/` directory:

| id (`file_type`) | File | What it draws |
|---|---|---|
| `table` | `table_signal.R` | a table with **chr / start / end / value** columns (CSV, TSV, bedGraph), with negative values below a zero line |
| `v4c` | `virtual4c.R` | a **virtual 4C** profile: contact frequencies between an anchor position and each visible bin, retrieved from the `.hic` file at a resolution appropriate for the view |

To use one from the catalog, enter the plugin ID in the **`file_type`** column and the file path in `path`, then select the row and click **Add as track**:

| id | name | path | file_type | set_anchor |
|---|---|---|---|---|
| 11 | insulation (Growing) | `s3://bucket/P/insulation_G.csv` | `table` | |
| 12 | IL6 promoter contacts | `s3://bucket/P/IMR90_G.hic` | `v4c` | `22766000` |

Columns named **`set_<parameter>`** specify plugin parameters (in this example, the anchor). A plugin can also register file extensions (`table` registers `.csv` and `.tsv`), allowing `file_type` to be left empty for those extensions.

To open a file without a catalog, go to **Data → Direct file**, select the plugin under **Type**, and add the file. Parameters are then set from the track's settings (click the
track's name in the **Tracks** panel).

## Writing a plugin

A plugin script calls `hicarta_plugin()` once:

```r
hicarta_plugin(
  id       = "csv",                       # file_type in the catalog (lowercase)
  label    = "CSV signal",                # shown in menus and on the track
  defaults = list(column = "value"),      # parameters and their defaults

  # data for [start, end] on chr (the part of the view inside the chromosome)
  read = function(path, chr, start, end, p) {
    d <- read.csv(path)
    d[d$chr == chr & d$end >= start & d$start <= end, ]
  },

  # draw it; the view is [vstart, vend] (may run past the chromosome ends)
  draw = function(d, chr, vstart, vend, style) {
    hc_canvas(vstart, vend, ylim = c(0, max(d[[style$params$column]], 1)))
    rect(d$start, 0, d$end, d[[style$params$column]], col = style$color, border = NA)
    hc_label(style$name)
  })
```

### `hicarta_plugin()` arguments

| Argument | Meaning |
|---|---|
| `id` | the track type's name: 1–32 lowercase letters, digits or `_`, starting with a letter. Use this identifier in the catalog’s `file_type` column. Must not be a built-in type (`hic`, `bigwig`, `bed`, `gff3`, `bs`, `arc`). |
| `label` | human-readable name (menus, the track chip, the settings dialog) |
| `draw` | **required.** `function(d, chr, vstart, vend, style)` — see below |
| `read` | `function(path, chr, start, end, p)` returning data in a form accepted by `draw`; `NULL` if the plugin needs no data |
| `defaults` | named list of parameters with their default values. Their **types** determine how values entered in the catalog or dialog are converted (number, TRUE/FALSE, text) |
| `accepts` | the kind of file the plugin reads: `"hic"`, `"bigwig"`, `"bed"`, `"gff3"`, `"bs"`, `"arc"` or `"any"` (default). Used to find chromosome lengths when the track is added before any contact map |
| `extensions` | file extensions registered by the plugin (e.g. `c("csv", "tsv")`), so `file_type` can be left empty for them |
| `chroms` | optional `function(path)` returning a named numeric vector of chromosome lengths (track-only mode) |
| `height`, `color` | defaults for a newly added track (px; any R color) |
| `description` | one line shown in the settings dialog |

### The `read()` function

`read(path, chr, start, end, p)` is called with the portion of the view within the chromosome boundaries and the merged parameters `p` (defaults, overridden by
the catalog's `set_` columns / the dialog / the session). The result is cached by region and parameter set, reducing repeated calls for cached views. It may return any suitable R object, such as a data frame, a matrix, or a list.

### The `draw()` function

`draw(d, chr, vstart, vend, style)` receives the data `d` returned by `read()` (or `NULL`)
and must draw into the current panel with base graphics. To keep the track aligned with the map, **the X-axis range must be exactly `[vstart, vend]`**. Use `hc_canvas()` to set this range; do not call `par(mar=)`.

`style` is a list:

| Field | Meaning |
|---|---|
| `name`, `color`, `height` | the track's label, color and height, as set by the user |
| `params` | the merged parameters (same as `p` in `read()`) |
| `ymin`, `ymax` | the Min / Max typed in the settings dialog, or `NA` for automatic |
| `print` | `TRUE` when drawing the print preview / export (a conventional left-hand Y axis is useful for exported figures) |
| `chrlen`, `dstart`, `dend` | chromosome length and the data range constrained to the chromosome boundaries |
| `path`, `id` | the file and the plugin id |

### Helpers

Drawing:

| Helper | What it does |
|---|---|
| `hc_canvas(vstart, vend, ylim = c(0, 1), headroom = 0.05)` | initializes the panel with the correct X-axis range (5% headroom above `ylim`, room below zero when `ylim[1] < 0`) |
| `hc_label(name)` | the track name at the top-left, like the built-in tracks |
| `hc_guide(y)` | a thin guideline with its value at the right (the "inline" scale of the built-in tracks) |
| `hc_yaxis()` | a conventional left-hand Y axis for print and export |
| `hc_message(text)` | a message inside the panel ("nothing in view", an error…) |

Data retrieval through HiCarta’s built-in readers (supports local files, HTTP(S) URLs, and private `s3://` objects; by default, supported remote files are read without downloading them in full):

| Helper | What it returns |
|---|---|
| `hc_hic_region(path, chr, start, end, resolution, norm, chr2, start2, end2)` | contact matrix of `[start,end]` on `chr` (rows) against `[start2,end2]` on `chr2` (columns); `chr2` defaults to `chr`, the second range to the first |
| `hc_bin_starts(m, 1)` / `hc_bin_starts(m, 2)` | bin start coordinates (bp) of the rows / columns of such a matrix |
| `hc_hic_pick_resolution(path, chr, start, end, target_bins = 500, norm)` | the resolution in the file closest to `target_bins` bins across the view |
| `hc_hic_chroms(path)`, `hc_hic_resolutions(path)`, `hc_hic_norms(path)` | available chromosomes, resolutions, and normalizations in the `.hic` file |
| `hc_bigwig_bins(path, chr, start, end, nbins, type = "mean")` | a bigWig as one value per bin (`type` = `"mean"` or `"max"`) |
| `hc_bigwig_intervals(path, chr, start, end)` | the raw bigWig intervals as `data.frame(start, end, value)` |

For reading and processing data, you can use any R functions and your own R
packages. Use base R graphics for rendering (e.g., `rect()`, `lines()`, and `polygon()`). Support for `ggplot2` and
other grid-based graphics in plugins is planned. Keep `read()` efficient: it runs when the requested region and parameter set are not cached.

## Parameters: catalog, dialog, session

- **Catalog**: a column `set_<name>` per parameter (`set_anchor`, `set_norm`…).
  Empty = the default. The usual `set_color` / `set_height` work as well.
- **Settings dialog**: one text box per parameter. Empty = the default.
- **Session file**: parameters are saved with the track and restored with it.
- **Min / Max** in the dialog arrive as `style$ymin` / `style$ymax`; it is up to
  the plugin to honor them (both included plugins do).

## Troubleshooting

- A plugin that fails to load is reported once when HiCarta starts and in
  the **About** panel, along with the error message. Other plugins can still load.
- A rendering error is displayed **inside the track's panel** (and in the R
  console); the rest of the app is unaffected.
- The track is empty: check that `read()` filters on the chromosome name the
  contact map uses (`chr1` vs `1`), and that the file's coordinates are in bp.
- Edited the plugin and nothing changed? Reload the browser page.

!!! warning "Plugins are code"
    A plugin is ordinary R code and runs with the same rights as HiCarta
    itself. Only place trusted scripts in the plugin directory.

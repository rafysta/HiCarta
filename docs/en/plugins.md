# Plugins: your own track types in R

A **plugin** is a small R file that teaches HiCarta a new kind of track. You
write two functions — one that reads the data for the region on screen, one
that draws it — and HiCarta takes care of everything else: the data catalog,
the "Add as track" button, the Tracks panel and its settings dialog, the
session file, and the print preview / export, where your track is drawn with
exactly the same x range as the contact map above it.

Typical uses: a score you computed yourself (insulation, eigenvector, any
per-bin value), a plot your lab already makes in R, or a view derived from the
`.hic` itself — the shipped **Virtual 4C** plugin is one of those.

!!! note "Where plugins live"
    Every `*.R` file in the **`plugins/`** folder next to `app.R` is read when
    HiCarta starts, and again on every page reload — so after editing a
    plugin you only reload the browser tab. Another folder can be named with
    `plugin_dir` in `config.txt` (**Setting → Edit config file…**). The
    **About** panel lists what was loaded, and says why when a file failed.

## Quick start

Two plugins ship with HiCarta, in `plugins/`:

| id (`file_type`) | File | What it draws |
|---|---|---|
| `table` | `table_signal.R` | any **chr / start / end / value** table (CSV, TSV, bedGraph), with negative values below a zero line |
| `v4c` | `virtual4c.R` | a **virtual 4C** profile: how often each bin in view touches one anchor position, read from the `.hic` at the resolution that fits the view |

To use one from the catalog, put the plugin's id in the **`file_type`** column
and the file in `path`, then open the row and click **Add as track**:

| id | name | path | file_type | set_anchor |
|---|---|---|---|---|
| 11 | insulation (Growing) | `s3://bucket/P/insulation_G.csv` | `table` | |
| 12 | IL6 promoter contacts | `s3://bucket/P/IMR90_G.hic` | `v4c` | `22766000` |

Columns named **`set_<parameter>`** fill the plugin's parameters (here the
anchor). A plugin can also claim file extensions (`table` claims `.csv` and
`.tsv`), in which case `file_type` may be left empty.

Without a catalog: **Data → Direct file**, choose the plugin in **Type**, and
add the file. Parameters are then set from the track's settings (click the
track's name in the **Tracks** panel).

## Writing a plugin

A plugin file calls `hicarta_plugin()` once:

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
| `id` | the track type's name: 1–32 lowercase letters, digits or `_`, starting with a letter. This is what goes in the catalog's `file_type`. Must not be a built-in type (`hic`, `bigwig`, `bed`, `gff3`, `bs`, `arc`). |
| `label` | human-readable name (menus, the track chip, the settings dialog) |
| `draw` | **required.** `function(d, chr, vstart, vend, style)` — see below |
| `read` | `function(path, chr, start, end, p)` returning anything `draw` understands; `NULL` if the plugin needs no data |
| `defaults` | named list of parameters with their default values. Their **types** matter: a value typed in the catalog or the dialog is converted to the default's type (number, TRUE/FALSE, text) |
| `accepts` | the kind of file the plugin reads: `"hic"`, `"bigwig"`, `"bed"`, `"gff3"`, `"bs"`, `"arc"` or `"any"` (default). Used to find chromosome lengths when the track is added before any contact map |
| `extensions` | file extensions the plugin claims (e.g. `c("csv", "tsv")`), so `file_type` can be left empty for them |
| `chroms` | optional `function(path)` returning a named numeric vector of chromosome lengths (track-only mode) |
| `height`, `color` | defaults for a newly added track (px; any R colour) |
| `description` | one line shown in the settings dialog |

### The `read()` function

`read(path, chr, start, end, p)` is called with the part of the view that lies
inside the chromosome, and the merged parameters `p` (defaults, overridden by
the catalog's `set_` columns / the dialog / the session). Its result is cached
per region and parameter set, so it is only called again when the view or a
parameter changes. It may return anything: a data frame, a matrix, a list.

### The `draw()` function

`draw(d, chr, vstart, vend, style)` gets the data `d` from `read()` (or `NULL`)
and must draw into the current panel with base graphics. The one rule:
**the x axis must be exactly `[vstart, vend]`** so the track lines up with the
map — `hc_canvas()` does that; do not call `par(mar=)`.

`style` is a list:

| Field | Meaning |
|---|---|
| `name`, `color`, `height` | the track's label, colour and height, as set by the user |
| `params` | the merged parameters (same as `p` in `read()`) |
| `ymin`, `ymax` | the Min / Max typed in the settings dialog, or `NA` for automatic |
| `print` | `TRUE` when drawing the print preview / export (a real left axis looks better there) |
| `chrlen`, `dstart`, `dend` | chromosome length and the clamped data range |
| `path`, `id` | the file and the plugin id |

### Helpers

Drawing:

| Helper | What it does |
|---|---|
| `hc_canvas(vstart, vend, ylim = c(0, 1), headroom = 0.05)` | opens the panel with the right x range (5 % headroom above `ylim`, room below zero when `ylim[1] < 0`) |
| `hc_label(name)` | the track name at the top-left, like the built-in tracks |
| `hc_guide(y)` | a thin guide line with its value at the right (the "inline" scale of the built-in tracks) |
| `hc_yaxis()` | a real left axis for print / export |
| `hc_message(text)` | a message inside the panel ("nothing in view", an error…) |

Reading, through HiCarta's own streaming readers (local files, http(s) URLs and
private `s3://` objects all work, and nothing is downloaded whole):

| Helper | What it returns |
|---|---|
| `hc_hic_region(path, chr, start, end, resolution, norm, chr2, start2, end2)` | contact matrix of `[start,end]` on `chr` (rows) against `[start2,end2]` on `chr2` (columns); `chr2` defaults to `chr`, the second range to the first |
| `hc_bin_starts(m, 1)` / `hc_bin_starts(m, 2)` | bin start coordinates (bp) of the rows / columns of such a matrix |
| `hc_hic_pick_resolution(path, chr, start, end, target_bins = 500, norm)` | the resolution in the file closest to `target_bins` bins across the view |
| `hc_hic_chroms(path)`, `hc_hic_resolutions(path)`, `hc_hic_norms(path)` | what the `.hic` offers |
| `hc_bigwig_bins(path, chr, start, end, nbins, type = "mean")` | a bigWig as one value per bin (`type` = `"mean"` or `"max"`) |
| `hc_bigwig_intervals(path, chr, start, end)` | the raw bigWig intervals as `data.frame(start, end, value)` |

Anything else in R is allowed too: `ggplot2` works (`print()` the plot inside
`draw()`), and so do your own packages. Keep `read()` reasonably fast: it runs
every time the view changes to a region that is not in the cache.

## Parameters: catalog, dialog, session

- **Catalog**: a column `set_<name>` per parameter (`set_anchor`, `set_norm`…).
  Empty = the default. The usual `set_color` / `set_height` work as well.
- **Settings dialog**: one text box per parameter. Empty = the default.
- **Session file**: parameters are saved with the track and restored with it.
- **Min / Max** in the dialog arrive as `style$ymin` / `style$ymax`; it is up to
  the plugin to honour them (both shipped plugins do).

## Troubleshooting

- A plugin that fails to load is reported once when HiCarta starts and in
  the **About** panel, with the error. The other plugins still load.
- An error while drawing is printed **inside the track's panel** (and in the R
  console); the rest of the app is unaffected.
- The track is empty: check that `read()` filters on the chromosome name the
  contact map uses (`chr1` vs `1`), and that the file's coordinates are in bp.
- Edited the plugin and nothing changed? Reload the browser page.

!!! warning "Plugins are code"
    A plugin is ordinary R code and runs with the same rights as HiCarta
    itself. Only put files you trust in the plugin folder.

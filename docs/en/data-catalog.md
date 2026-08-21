# Data catalog (.xlsx)

All data in HiCarta — contact maps and tracks alike — is opened from a **data
catalog**: an ordinary Excel file (`.xlsx`) in which **one row = one sample**.
The catalog is loaded in the **Data browser** (the **Data** button at the top of
the screen), which shows it as a filterable, searchable sample list; clicking a
row shows every detail and offers the actions that fit its file type (open as
contact map, open as comparison, add as track, open in IGV).

A ready-to-copy template ships with the repository:
[`HiCarta_catalog_template.xlsx`](https://github.com/rafysta/HiCarta/blob/main/HiCarta_catalog_template.xlsx).

The catalog can live anywhere: a local path, a network drive, or a URL (e.g. an
`.xlsx` shared over HTTP). It is re-read every time you press **Load**, so a
collaborator editing the shared file is always seen at the next load. Google
Sheets is not supported — export/share as `.xlsx`.

---

## Columns

### Required

| Column | Meaning |
|---|---|
| `id` | A **number, unique** within the catalog. Used to refer to the sample (e.g. from bookmarks). |
| `name` | Sample name shown in the list. |
| `path` | File path or URL. Can hold **several `;`-separated entries** (see below). |

### Recommended (recognised by HiCarta)

| Column | Meaning |
|---|---|
| `file_type` | `hic` / `bigwig` / `bed` / `gff3` / `bs`. When empty, guessed from the file extension. |
| `experiment_type` | e.g. HiC, ChIP-seq, RNA-seq… becomes a filter. |
| `project` | Project name; becomes a filter. |
| `sample_sheet` | Your sample-sheet / batch identifier; becomes a filter. |
| `date` | `YYYY-MM-DD` (recommended). Also accepted: `YYYY/MM/DD`, `YYYY.MM.DD`, `YYYYMMDD`, native Excel dates. Filterable as a range. |
| `genome` | Genome/assembly name. |
| `label` | Display label per `;`-entry of `path` (same number of `;`-parts as `path`, or one shared value). |
| `comment` | Free text; found by the all-column search. |

### Settings columns (`set_` prefix)

Columns whose name starts with `set_` are **per-sample defaults applied when the
sample is opened**. They never appear in the list or the filters.

| Column | Effect when the sample is opened |
|---|---|
| `set_norm` | Normalization to select (e.g. `ICE`, `KR`, `NONE`). When absent, HiCarta picks automatically: **ICE → KR → Raw**, whichever the file offers first. |
| `set_vmax` | Initial color-scale maximum. |
| `set_resolution` | Pin the displayed resolution (bp) instead of zoom-adaptive choice. |
| `set_color` | Default track color (track types). |
| `set_height` | Default track height in px (track types). |

### Your own columns

Any other column is kept and shown in the detail view. A column with **at most
20 distinct values** automatically becomes a dropdown filter in the sidebar, so
adding e.g. a `tissue` or `condition` column instantly makes it filterable.

---

## Multiple files in one row (`;`)

`path`, `label` and every `set_` column may hold several values separated by
`;` (the full-width `；` also works). Within one row each such column must hold
either **one** value (shared by all entries) or **exactly as many** as `path`.

Two uses:

- **A track set** — several bigWigs belonging to one sample; "Add as track"
  lets you pick the entry.
- **A virtual multi-resolution dataset** — several single-resolution `.hic`
  files of the same sample in one row. Opening the row with **“auto”** treats
  them as one dataset: HiCarta switches between the files as you zoom and
  equalises their brightness. This is the compatibility path for legacy
  per-resolution files; new data should be a single multi-resolution `.hic`.

!!! note
    In auto mode only the normalizations present in **every** file are offered
    in **Display → Map → Normalization**. Open a single entry to use that
    file's own normalizations.

---

## Directive rows: `#show`

A row whose `id` cell is `#show` is not data: put any mark (e.g. `1`) in the
columns that should be **visible in the list initially**. Viewers can still
toggle columns with the **Columns** button; `id` and `name` are always shown.
Rows whose `id` starts with `#` but is not a known directive are ignored with a
warning.

---

## Validation

When a catalog is loaded, broken rows — a missing/duplicated/non-numeric `id`,
an empty `path`, mismatched `;` counts — are **excluded** and listed above the
table with the sample name and the reason. Soft problems (an unparsable date,
an unknown `file_type` or `set_` column) are warnings only; the row still
loads.

---

## Bookmarks as Excel

Bookmarks (**Navigate** panel) remember not only the place but also **which
data was open** (catalog id, paths, normalization, resolution, color max), so
clicking one restores the whole picture. Two buttons exchange them with an
`.xlsx`:

- **Save to Excel** downloads the current list (one row per bookmark; columns
  `bookmark_name, catalog_id, path, entry, chr, start, end, ystart, yend,
  norm, resolution, vmax, comment`).
- **Load from Excel (append)** reads such a file and **appends** its rows to
  the current list — existing bookmarks are never touched. Broken rows are
  skipped and reported with the name and reason, like the catalog itself.

The file is ordinary Excel, so you can annotate the `comment` column, curate a
list of regions by hand, or share it with collaborators.

---

## Open in IGV

For track rows the detail view offers **Open in IGV**: the file (and the region
currently in view) is sent to a **running IGV desktop** through IGV's remote
port. HiCarta never launches IGV — start it yourself and enable the port once
in IGV: *View → Preferences → Advanced → “Enable port”* (default 60151).
Optionally set `igv_genome` in `config.txt` (or **Setting → Edit config
file…**) to also tell IGV which genome to load.

---

## Converting old files

`scripts/` ships four standalone converters between the catalog and the two
legacy formats (Juicer-style menu, IGV track-list XML):

```bash
Rscript scripts/juicer_menu_to_catalog.R  menu.txt     catalog.xlsx [--collapse]
Rscript scripts/igv_xml_to_catalog.R      tracks.xml   catalog.xlsx
Rscript scripts/catalog_to_juicer_menu.R  catalog.xlsx menu.txt
Rscript scripts/catalog_to_igv_xml.R      catalog.xlsx tracks.xml
```

`--collapse` additionally rewrites legacy per-normalization names
(`NAME_ICE.5kb.hic` → `NAME.hic`) and removes duplicates — useful after
regenerating data as single multi-resolution `.hic` files. See
[scripts/README.md](https://github.com/rafysta/HiCarta/blob/main/scripts/README.md).

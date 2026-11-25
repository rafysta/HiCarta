# Data catalog (.xlsx)

In HiCarta, contact maps and tracks can be opened from a **data catalog**: an
Excel file (`.xlsx`) with **one row per sample**. You can also open a file by
entering its path or URL directly, without a catalog. Open the **Data browser** using the **Data** button at the top of the screen and load the catalog. It appears as a searchable, filterable sample list. Clicking a row displays the sample details and the actions available for its file type (open as a contact map, open as a comparison, add as a track, or open in IGV).

A reusable template is included in the repository:
[`HiCarta_catalog_template.xlsx`](https://github.com/rafysta/HiCarta/blob/main/HiCarta_catalog_template.xlsx).

The catalog can be stored on a local drive, a network drive, or at a URL (e.g., an `.xlsx` file shared over HTTP). HiCarta reloads the catalog each time you click **Load catalog**, so updates to the shared file can be retrieved on the next load. Google Sheets is not supported directly; export the spreadsheet as an `.xlsx` file before sharing it.

---

## Columns

### Required

| Column | Meaning |
|---|---|
| `id` | A numeric identifier used in the sample list and ID search. **Unique IDs are recommended but not required.** Duplicate IDs generate a warning but do not exclude rows (HiCarta does not use IDs internally as row keys). This allows sample sets with independent numbering schemes to be combined in one catalog. |
| `name` | Sample name shown in the list. |
| `path` | File path or URL. Can hold **several `;`-separated entries** (see below). |

### Recommended (recognized by HiCarta)

| Column | Meaning |
|---|---|
| `file_type` | `hic` / `bigwig` / `bed` / `gff3` / `bs`. If empty, inferred from the file extension. |
| `experiment_type` | Experiment type (e.g., Hi-C, ChIP-seq, or RNA-seq); available as a filter. |
| `project` | Project name; becomes a filter. |
| `sample_sheet` | Sample sheet or batch identifier; becomes a filter. |
| `date` | `YYYY-MM-DD` (recommended). Also accepted: `YYYY/MM/DD`, `YYYY.MM.DD`, `YYYYMMDD`, native Excel dates. Supports date-range filtering. |
| `genome` | Genome/assembly name. |
| `label` | Display label for each `;`-separated entry in `path` (one label per entry or a single shared label). |
| `comment` | Free text; included in the search across all columns. |

### Settings columns (`set_` prefix)

Columns whose names start with `set_` are **per-sample defaults applied when the
sample is opened**. They never appear in the list or the filters.

| Column | Effect when the sample is opened |
|---|---|
| `set_norm` | Normalization to select (e.g. `ICE`, `KR`, `NONE`). If unspecified, HiCarta automatically selects the first available option in this order: **ICE → KR → Raw**. |
| `set_vmax` | Initial color-scale maximum. |
| `set_resolution` | Fix the display resolution (bp) instead of adjusting it automatically as you zoom. |
| `set_color` | Default track color (track types). |
| `set_height` | Default track height in pixels (track types). |

### Your own columns

Additional columns are retained and shown in the detail view. A column with **at most 20 distinct values** automatically becomes a dropdown filter in the sidebar. For example, add a `tissue` or `condition` column to filter by that metadata.

---

## Multiple files in one row (`;`)

`path`, `label` and every `set_` column may hold several values separated by
`;` (the full-width `；` also works). Within a row, each of these columns must contain either **one** value (shared by all entries) or **exactly as many** values as there are entries in `path`.

Two uses:

- **A track set** — several bigWigs belonging to one sample; "Add as track"
  lets you select the entry to add.
- **A virtual multi-resolution dataset** — several single-resolution `.hic`
  files of the same sample in one row. Opening the row with **“auto”** treats
  them as one dataset: HiCarta switches between the files as you zoom and
  adjusts their signal intensity for consistent display. This provides compatibility with legacy files stored separately by resolution; for new datasets, a single multi-resolution `.hic` file is recommended.

!!! note
    In auto mode only the normalizations present in **every** file are offered
    in **Display → Map → Normalization**. Open a single entry to use that
    file's own normalizations.

---

## Directive rows: `#show`

A row with `#show` in the `id` cell is a directive rather than a data row. Enter any marker (e.g., `1`) in the columns that should be **visible in the list initially**. Viewers can still
toggle columns with the **Columns** button; `id` and `name` are always shown.
Rows whose `id` starts with `#` but is not a known directive are ignored with a
warning.

---

## Validation

When a catalog is loaded, invalid rows — a missing or non-numeric `id`,
an empty `path`, mismatched `;` counts — are **excluded**. Other issues (a duplicate `id`, a **`path` that looks like neither a file nor a URL**, an
invalid date, an unknown `file_type` or `set_` column) are warnings only; the
row still loads.

A `path` is considered well-formed if it has a URL scheme (e.g., `https://`),
a path separator (`/` or `\`), or a file extension. A value with none of those
(`ICE`, `KR`, `5000`) may indicate a misaligned column, so it is flagged
— and opening such a row stops with the same explanation instead of failing
later with a message about the file.

Only the **counts** appear above the table, one per line — "Excluded
rows: 3 (click to see them)". Click a line to expand the list of sample names and the corresponding reasons; click again to collapse it. When there are many,
the list stops at the first 200 and the rest are summarized as "...and N more".

---

## Bookmarks as Excel

Bookmarks (**Navigate** panel) record **only the genomic location** — the chromosome and
the X / Y ranges. Clicking a bookmark navigates to the same region in the currently open dataset, making bookmarks useful for comparisons across samples. Two buttons allow bookmarks to be exchanged as an `.xlsx` file:

- **Save to Excel** downloads the current list (one row per bookmark; columns
  `bookmark_name, chr, start, end, chr_y, ystart, yend, comment`).
- **Load from Excel (append)** reads such a file and **appends** its rows to
  the current list — existing bookmarks are never touched. Invalid rows are
  skipped and reported with the name and reason, like the catalog itself. Files saved by older versions that contain `catalog_id` / `path` / `norm` and the
  other display columns still load — those columns are ignored.

The file is a standard Excel workbook, so you can annotate the `comment` column, curate a
list of regions by hand, or share it with collaborators.

---

## Private data on Amazon S3

In addition to public URLs, `path` can specify an Amazon S3 object using **`s3://bucket/key`** (e.g. `s3://uo-cgf/P/020/NAME/NAME.hic`). This works for every file type (`.hic`, bigWig, BED, …), and the catalog itself can also be stored on S3.

- **Public files** are read without credentials, whether specified as an `https://….amazonaws.com/…` URL or as `s3://`.
- **Files that are not public** are read with an AWS access key stored on your computer, which HiCarta uses to sign the request. Access is determined by the permissions configured in S3 (e.g., for a lab or P01 group). If you lack permission, HiCarta displays an error message.
- If a file written as an `https://` S3 URL is later made private, the same URL keeps working for anyone who has the required access permission.

Store the credentials in the same file used by the AWS CLI:

```ini
# Windows: %USERPROFILE%\.aws\credentials   Mac: ~/.aws/credentials
[hicarta]
aws_access_key_id     = AKIA...
aws_secret_access_key = ...
```

Enter `hicarta` as the **AWS profile** under **Setting → Edit config file…** and save (empty = `[default]`). The dialog indicates whether credentials were found. The access key itself is not stored in `config.txt`. The region is detected automatically.

## Open in IGV

For track rows, the detail view offers **Open in IGV**: the file (and the region
currently in view) is sent to a **running instance of IGV Desktop** through IGV's remote
port. HiCarta does not launch IGV automatically. Start IGV and enable its remote port: *View → Preferences → Advanced → “Enable port”* (default 60151).
Optionally set `igv_genome` in `config.txt` (or **Setting → Edit config
file…**) to also tell IGV which genome to load.

---

## Converting old files

The `scripts/` directory contains four standalone converters between the catalog and two legacy formats (Juicer-style menu, IGV track-list XML):

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

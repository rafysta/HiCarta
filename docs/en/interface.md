# Screens & controls

This page describes HiCarta’s menus, controls, and settings. For a task-oriented introduction, see **[Usage](usage.md)** instead.

The top of the screen has these menus: **Data · Navigate · Display · Print · Setting · About**. The **Data** button opens the data loading dialog; the other menus switch the control panel on the left. The **Display** panel has three tabs — **Map · Compare · Tracks**.

The typical flow is: load the catalog → click a sample → open it → pan/zoom → add tracks.

---

## Data (loader) {#data}

Click the **Data** button at the top to open the data loading dialog. It has three tabs: **Data browser** / **Direct file** / **Session**.

### Data browser tab

The **[data catalog](data-catalog.md)** is an Excel file with one row per sample, from which you can open contact maps and tracks. To open a file without a catalog, use the **Direct file** tab.

**Load the catalog** — The path/URL field is prefilled with `catalog_url` from `config.txt`; use **Browse…** to select a local file (the location list starts with your **favorite folders** (★), then **Desktop / Documents / Downloads / Home** and the drives; on Windows the dialog also recognizes a Desktop folder redirected to OneDrive). Click **Load catalog** to load or reload the catalog. Invalid rows are excluded and reported with the sample name and the reason.

**Filter and search** — The left sidebar has a search-as-you-type field for sample names, a search across all columns (including comments), dropdown filters generated from the catalog columns, and a date-range filter. Filters are combined using AND logic; each dropdown lists only values consistent with the other active filters.

**The sample list** — Use **Columns** to select the displayed columns and the adjacent control to set the number of rows per page. Click a row to open the **detail view**, which shows all sample metadata and actions available for its file type:

- **Open as contact map** — `hic` rows. A row holding several `;`-separated `.hic` entries can be opened as one **virtual multi-resolution dataset** (“auto”) or as a single entry.
- **Open as comparison (B)** — load a second map to compare (Display → Compare).
- **Add as track** — track rows (`bigwig` / `bed` / `gff3` / `bs`). A dialog allows you to set the label, color (visual palette), and height before adding the track. The catalog’s `set_*` columns supply the initial values.
- **Open in IGV** — track rows; sends the file and the current region to a running instance of IGV Desktop ([details](data-catalog.md#open-in-igv)).

`set_norm`, `set_vmax`, `set_resolution` from the catalog are applied when a map is opened; if `set_norm` is unspecified, HiCarta selects the first available normalization in the order ICE → KR → Raw.

### Direct file tab

Open a file without a catalog by entering its path or URL. Catalog `set_*` defaults (normalization, scale maximum, resolution, color, height) do not apply here — set them afterward in **Display**.

**Contact map (.hic)** — Type a path or URL (use **Browse…** to select a local file), optionally choose a normalization and a display name, then click **Open as contact map** or **Open as comparison (B)**. Several single-resolution files can be opened together as one virtual multi-resolution dataset by separating their paths with `;` (comparison B always uses one file — the first path).

**Track** — Type a path or URL, pick the **Type** (**Auto** detects `bigWig` / `BED` / `gene (GFF3)` / `Border Strength` from the extension), set label, color and height, then click **Add track**.

Data opened this way can also be saved to a session. As with data opened from the catalog, a bookmark records only the genomic position.

### Session tab

Save the current view to a file and restore it later.

**Save current view** — Downloads the view state — data source, region, color scale and all tracks — as a `.json` file (named `HiCarta_session_<datetime>.json`).

**Restore from file (.json)** — Type the path or URL of a saved `.json` (use **Browse…** to select a local file) and click **Load** to restore the saved view.

---

## Navigate {#navigate}

Specify the chromosome and region to display, and move around the map.

**Chromosome (X axis)** — Choose the chromosome to display. Chromosome names correspond to those stored in the `.hic` file (e.g. `I / II / III` for *S. pombe*). Choosing a different chromosome reopens the map automatically. Both chromosome lists are populated from the file each time a map is opened.

**X-axis start / X-axis end (bp)** — Specify the range to display, in bp.

**All chromosomes (whole genome)** — Select the first entry in the X-axis chromosome list. Both axes display all chromosomes end to end, allowing all chromosome pairs to be viewed at once. Cis contacts occupy the diagonal blocks, and trans contacts occupy the off-diagonal blocks. Both rulers display chromosome names, with thin lines marking chromosome boundaries. The cursor readout identifies the chromosome and the position within it. Panning, zooming, the color scale, bookmarks, comparison and export all work as usual. Tracks are hidden while this view is open, because tracks follow the coordinates of a single chromosome. They reappear when you select a single chromosome.

**Chromosome (Y axis)** — With **same as X (normal map)** selected, the map displays intra-chromosomal contacts. Choosing a *different* chromosome draws the **inter-chromosome (trans) map** between the two: the horizontal axis represents the X chromosome and the vertical axis represents the selected Y chromosome, so the map may be rectangular rather than square. A badge in the top-left corner names each axis. Tracks always follow the horizontal axis, so they remain aligned with the X-axis coordinates.

**Y-axis start / Y-axis end (bp)** — The vertical range, shown only when the two axes differ. Selecting a Y chromosome sets the range to its full length.

Two things work differently on an inter-chromosome map, because it lacks the symmetry of an intra-chromosomal map: the **Split** comparison mode is not offered (use Curtain or Difference instead), and the cursor readout omits genomic distance between the two loci.

**Go to region** — Jump to the chromosome/range you entered.

**Pan view (direction pad)** — The eight directional buttons (up/down/left/right plus diagonals) move the region in view. Up/down move along the Y axis, left/right along the X axis. The center **⌂** (home) button returns to the whole-chromosome view of that chromosome.

**Step** — Choose the amount each direction button moves, as a fraction of the range in view (**¼ · ½ · 1**).

**Bookmarks** — Save a region of interest and return to it with one click. Enter a name in the name field (optional) and save it with **★ Bookmark this view**. A bookmark records **only the genomic location** — the chromosome and the X / Y ranges — with no data reference and no display settings. Clicking one moves to that region **in the currently open dataset**, allowing the same bookmark to be reused across samples. The current normalization, resolution, and color scale remain unchanged. **Delete** removes one. Bookmarks are also saved in a session, and can be exchanged as Excel files: **Save to Excel** downloads the list, **Load from Excel (append)** takes a path or URL (use **Browse…** to select a local file) and, on **Load**, appends the rows of that file ([details](data-catalog.md#bookmarks-as-excel)).

---

## Display {#display}

The **Map** tab adjusts the open map; **Compare** contains the two-sample comparison controls, including the option to remove a comparison; **Tracks** is described [below](#tracks).

Adjust the color scale. All tiles use a **single absolute-value color scale**, ensuring consistent colors across tile boundaries.

**Normalization** — Switch the normalization of the open map (e.g. ICE / KR / Raw) without reopening it; the choices are what the `.hic` file actually contains. For a virtual multi-file dataset (“auto”), only normalizations present in every file are offered.

**Resolution** — Use the slider to fix the bin size, or select **Auto** to adjust the resolution with the zoom level. Only resolutions available for the current chromosome and normalization are offered — a `.hic` header lists the resolutions the *file* was built with, but a chromosome's matrix can carry fewer zoom levels, and a normalization vector can be missing at some of them. Zooming can therefore stop at a coarser bin size on one chromosome (or one normalization) than on another. This reflects the available data rather than a fixed resolution limit of the viewer.

**Palette** — Choose the color scheme (4 options: matlab, gentle, red, blue).

**Max value** — Dragging this slider changes the contrast and redraws all tiles. The initial value is estimated automatically by coarsely scanning the whole map when it is opened.

**linear / log10(value)** — Switch between linear and logarithmic scaling. The minimum is fixed at 0.

---

## Tracks (Display → Tracks) {#tracks}

Display 1D tracks below the contact map. Tracks remain synchronized with horizontal panning and zooming and render data for the visible genomic range. Multiple tracks can be stacked, each with its own color and height. A cursor guideline runs through the tracks.

To add a track from the catalog, click a track row in the **Data browser** and choose **Add as track**. A dialog lets you set the label, the color (visual palette) and the height before the track is added; the catalog’s `set_color` and `set_height` values are prefilled. To add a track by its path or URL, use the **Direct file** tab.

The **Display → Tracks** panel lists the added tracks as **chips**. Drag a chip to reorder the tracks (the display order updates accordingly). Click a chip to edit that track — label, color, height, maximum value, aggregation, per-track resolution — or delete it.

Tracks also work **without a contact map**: the chromosome axis is read from the first track file, a coordinate ruler is drawn on top, and you can zoom by dragging a range on the ruler.

Track types you can use:

| Type | What is drawn | Notes |
|---|---|---|
| **bigWig** | Filled area | By default, only the visible range is read (remote files are not downloaded in full) |
| **BED** | Interval boxes | The whole file is read (`rtracklayer`) |
| **gene (GFF3)** | Gene arrows, exons, names | + strand on top / − strand on bottom. Exons appear when zoomed in. Gene labels are selectively displayed to avoid overlap. Cached as `<gff3>.genes.rds` |
| **Border Strength** | Area of `BS.norm` | Positive = red, negative = blue, baseline 0. Dashed lines at boundaries |

For the details of each format, see **[Data formats](data-formats.md)**; for the catalog columns that describe tracks, see **[Data catalog](data-catalog.md)**.

---

## Print {#print}

Export a selected region of the current map and tracks as a PNG image or PDF, or send it to a printer.

Click **Open print preview** to open the preview. There you can set:

- **Destination** — Printer, or File.
- **Output folder / File name / Format** — The save location and file name for file output, and the format (**Image (PNG)** or **PDF**).
- **Paper size** — A4 portrait, A4 landscape, Square, or Custom (specify width/height in mm).
- **Output region** — Chromosome, start and end (bp) for each axis. Leaving **Chromosome (Y axis)** at *same as X* exports the usual square map; choosing a different one exports the inter-chromosome map between the two.
- **Resolution** — With *same as the map on screen* selected, the export uses the same bin size as the current view, including any fixed resolution selected in Display → Map. Choosing a resolution here overrides that; the line under the preview always names the resolution actually used.
- **Same bp scale on both axes** — On (the default), each base pair occupies the same distance on the horizontal and vertical axes, preserving the genomic aspect ratio. The map is centered in the available space. When disabled, the map is stretched to fill the available area. Tracks stay aligned with the map either way. For an inter-chromosome map, pick a paper size close to the shape of the region to avoid a large blank margin.
- **Include coordinate ticks / Include legend / No margins** — Toggle the elements included in the output.
- **Also export tracks** — Export the tracks in view together.

After configuring the output, click **Run**.

---

## Setting {#setting}

Adjust the layout and the app's defaults.

**Contact map height (px)** — Specify the map height. Apply it with **Apply**.

**Fit to window** — Set the map height to "window height − total track height".

**Track resolution (view divisions)** / **Auto adjust** — Adjust the drawing resolution and height of tracks.

**Aggregation (whole-chromosome view)** — Choose the aggregation for the whole-map view: **Mean (IGV default)** or **Max (keep peaks)**.

### Edit config file…

Click **Edit config file…** to view and edit the application’s startup defaults (`config.txt`).

- **Interface language** — Switch between Japanese and English.
- **Default catalog (.xlsx) URL / path** — The data catalog loaded by default in the Data browser.
- **Remote file reading** — Stream supported remote files (default) or download them in full before loading.
- **IGV genome id** — Sent along with "Open in IGV" (e.g. `hg38`; empty = don't send).
- **Favourite folders** — Listed first, marked ★, in every **Browse…** dialog. One per line, `name = path` (or just the path). **Add folder…** picks one for you. Folders that do not exist are skipped.

Clicking **Apply & save** reloads the page and applies the settings (any map or tracks currently loaded are closed at that point).

---

## About {#about}

Shows the version and author information (Hideki Tanizawa, rafysta@gmail.com).

---

## Operating on the map

Once a map is open, you can operate directly on it.

- **Drag** to pan
- **Scroll** to zoom (the resolution switches automatically)
- **Middle-click drag** to zoom to a selected range (rubber band)

The header shows the current coordinates and resolution, and a ruler with ticks appears along the edge. Hover over the map to display the coordinates, contact value, and, where applicable, genomic distance. The origin is at the top-left, and genomic coordinates on the Y axis increase downward.

---

## Notes and current scope

- HiCarta shows both **cis** (intra-chromosomal) and **trans** (inter-chromosomal) contacts. To see an inter-chromosome map, choose a different chromosome for the Y axis in the **Navigate** panel, or choose **All chromosomes (whole genome)** ([Navigate](#navigate)).
- Track chromosome names (e.g. `chrII`) are mapped to the `.hic` names (`II`) where possible.

# Screens & controls

This page is a reference to what each HiCarta menu and item does. If you want to know "what to do first", see **[Usage](usage.md)** instead.

The top of the screen has these menus: **Data · Navigate · Display · Print · Setting · About**. The **Data** button opens the loader; the other menus switch the operation panel on the left. The **Display** panel has three tabs — **Map · Compare · Tracks**.

The typical flow is: load the catalog → click a sample → open it → pan/zoom → add tracks.

---

## Data (loader) {#data}

Click the **Data** button at the top to open the loader. It has two tabs: **Data browser** / **Session**.

### Data browser tab

All data — contact maps and tracks — is opened from the **[data catalog](data-catalog.md)**, an Excel file in which one row = one sample.

**Load the catalog** — The path/URL field starts with `catalog_url` from `config.txt`; **Browse…** picks a local file. Click **Load** to (re)read it. Broken rows are excluded and listed with the sample name and the reason.

**Filter and search** — The left sidebar has an incremental sample-name search, an all-columns search (comments included), dropdown filters generated from the catalog's own columns, and a date-range filter. All conditions combine; each dropdown only offers values that still match the other conditions.

**The sample list** — Choose visible columns with **Columns**, page length next to it; click a row to open the **detail view** with every column of that sample and the actions that fit its file type:

- **Open as contact map** — `hic` rows. A row holding several `;`-separated `.hic` entries can be opened as one **virtual multi-resolution dataset** (“auto”) or as a single entry.
- **Open as comparison (B)** — load a second map to compare (Display → Compare).
- **Add as track** — track rows (`bigwig` / `bed` / `gff3` / `bs`). A second dialog lets you set label, color (visual palette) and height first; `set_*` catalog columns pre-fill it.
- **Open in IGV** — track rows; sends the file and the current region to a running IGV desktop ([details](data-catalog.md#open-in-igv)).

`set_norm`, `set_vmax`, `set_resolution` from the catalog are applied when a map is opened; without `set_norm` HiCarta picks ICE → KR → Raw automatically from what the file offers.

### Session tab

Save and restore the whole view to and from a file.

**Save current view** — Downloads the view state — data source, region, color scale and all tracks — as a `.json` file (named `HiCarta_session_<datetime>.json`).

**Restore from file (.json)** — Choose a saved `.json` to reproduce that entire view.

---

## Navigate {#navigate}

Specify the chromosome and region to display, and move around the map.

**Chromosome** — Choose the chromosome to display. Chromosome names follow the internal names in the `.hic` (e.g. `I / II / III` for *S. pombe*). Choosing a different chromosome reopens the map automatically.

**Y-axis start / Y-axis end (bp)** — Specify the range to display, in bp.

**Go to region** — Jump to the chromosome/range you entered.

**Pan view (direction pad)** — The 8-direction buttons (up/down/left/right plus diagonals) move the region in view. Up/down move along the Y axis, left/right along the X axis. The center **⌂** (home) button returns to the whole-chromosome view of that chromosome.

**Step** — Choose the amount each direction button moves, as a fraction of the range in view (**¼ · ½ · 1**).

**Bookmarks** — Save the current view and return to it later. Enter a name in the name field (optional) and register it with **★ Bookmark this view**. A bookmark remembers not only the place but also **which data was open** (catalog id, paths, normalization, resolution, color max), so clicking one restores the whole picture. **Delete** removes one. Bookmarks are also saved in a session, and can be exchanged as Excel: **Save to Excel** downloads the list, **Load from Excel (append)** appends rows from such a file ([details](data-catalog.md#bookmarks-as-excel)).

---

## Display {#display}

The **Map** tab adjusts the open map; **Compare** holds the two-sample comparison controls (including releasing a comparison); **Tracks** is described [below](#tracks).

Adjust the color scale. The color uses a **single absolute-value scale** shared across all tiles, so there are no seams between tiles.

**Normalization** — Switch the normalization of the open map (e.g. ICE / KR / Raw) without reopening it; the choices are what the `.hic` file actually contains. For a virtual multi-file dataset (“auto”), only normalizations present in every file are offered.

**Resolution** — The slider pins the map to one bin size; **Auto** follows the zoom instead. It offers only the resolutions this chromosome actually holds under the current normalization — a `.hic` header lists the resolutions the *file* was built with, but a chromosome's matrix can carry fewer zoom levels, and a normalization vector can be missing at some of them. Zooming can therefore stop at a coarser bin size on one chromosome (or one normalization) than on another; that is the data, not a limit of the viewer.

**Palette** — Choose the color scheme (4 options: matlab, gentle, red, blue).

**Max value** — Dragging this slider changes the contrast and redraws all tiles. The initial value is estimated automatically by coarsely scanning the whole map when it is opened.

**linear / log10(value)** — Switch how the value scale is taken. The minimum is fixed at 0.

---

## Tracks (Display → Tracks) {#tracks}

Overlay 1-D tracks below the contact map. Tracks follow the map's horizontal pan/zoom and load only the range in view. Multiple tracks can be stacked, each with its own color and height. A cursor guide line runs through the tracks.

Tracks are added from the catalog: click a track row in the **Data browser** and choose **Add as track**. A dialog lets you set the label, the color (visual palette) and the height before the track is added; `set_color` / `set_height` in the catalog pre-fill it.

The **Display → Tracks** panel lists the added tracks as **chips**. Drag a chip to reorder the tracks (the drawing order follows). Click a chip to edit that track — label, color, height, maximum value, aggregation, per-track resolution — or delete it.

Tracks also work **without a contact map**: the chromosome axis is read from the first track file, a coordinate ruler is drawn on top, and you can zoom by dragging a range on the ruler.

Track types you can use:

| Type | What is drawn | Notes |
|---|---|---|
| **bigWig** | Filled area | Read via `rtracklayer` |
| **BED** | Interval boxes | Read via `rtracklayer` |
| **gene (GFF3)** | Gene arrows, exons, names | + strand on top / − strand on bottom. Exons appear when zoomed in. Names are thinned to avoid overlap. Cached as `<gff3>.genes.rds` |
| **Border Strength** | Area of `BS.norm` | Positive = red, negative = blue, baseline 0. Dashed lines at boundaries |

For the details of each format, see **[Data formats](data-formats.md)**; for the catalog columns that describe tracks, see **[Data catalog](data-catalog.md)**.

---

## Print {#print}

Export a chosen region of the currently open map as an image or PDF, or print it.

Click **Open print preview** to open the preview. There you can set:

- **Destination** — Printer, or File.
- **Output folder / File name / Format** — The save location and file name for file output, and the format (**Image (PNG)** or **PDF**).
- **Paper size** — A4 portrait, A4 landscape, Square, or Custom (specify width/height in mm).
- **Output region** — Chromosome, start and end (bp). For Hi-C, X and Y use the same range.
- **Include coordinate ticks / Include legend / No margins** — Toggle the elements included in the output.
- **Also export tracks** — Export the tracks in view together.

Once set, click **Run**.

---

## Setting {#setting}

Adjust the layout and the app's defaults.

**Contact map height (px)** — Specify the map height. Apply it with **Apply**.

**Fit to window** — Set the map height to "window height − total track height".

**Track resolution (view divisions)** / **Auto adjust** — Adjust the drawing resolution and height of tracks.

**Aggregation (whole-chromosome view)** — Choose the aggregation for the whole-map view: **Mean (IGV default)** or **Max (keep peaks)**.

### Edit config file…

Click **Edit config file…** to view and edit the app's startup defaults (`config.txt`).

- **Interface language** — Switch between Japanese and English.
- **Default catalog (.xlsx) URL / path** — The data catalog loaded by default in the Data browser.
- **Remote file reading** — Stream over the network (default) or download whole files first.
- **IGV genome id** — Sent along with "Open in IGV" (e.g. `hg38`; empty = don't send).

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

The header shows the current coordinates and resolution, and a ruler with ticks appears along the edge. Hover to show the coordinate, score and distance at that position. The origin is at the top-left, and genomic *y* increases downward.

---

## Notes and current scope

- HiCarta currently targets **cis** (intra-chromosomal) contacts.
- Track chromosome names (e.g. `chrII`) are mapped to the `.hic` names (`II`) where possible.

# Screens & controls

This page is a reference to what each HiCarta menu and item does. If you want to know "what to do first", see **[Usage](usage.md)** instead.

The top of the screen has these menus: **Data · Navigate · Display · Tracks · Print · Setting · About**. The **Data** button opens the loader; the other menus switch the operation panel on the left.

The typical flow is: choose data → set a region → **Open map** → pan/zoom → add tracks.

---

## Data (loader) {#data}

Click the **Data** button at the top to open the loader. It has three tabs: **Hi-C** / **Tracks** / **Session**.

### Hi-C tab

Choose the contact map to display. There are two ways.

**Choose from a menu** — Click **Load menu** to fetch the Juicer menu specified by `menu_url` in `config.txt`, then choose a **Sample** and **Dataset**. The dropdowns support partial-match search, so you can type part of a name to narrow it down. You can also choose the **Normalization**.

**Specify a local `.hic` file** — Paste the path of a `.hic` on your computer into **.hic file path**, or pick it via **Browse…**. A specified local file takes priority over the menu selection.

Once chosen, click **Open map** to load and display it.

!!! note
    Each `.hic` in the sample menu may be a single-resolution file. HiCarta adjusts the requested resolution/normalization to what the file actually has.

### Tracks tab

→ See [the "Tracks" section below](#tracks) (the loader's Tracks tab and the left-hand Tracks menu handle the same settings).

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

**Bookmarks** — Save the current view and return to it later. Enter a name in the name field (optional) and register it with **★ Bookmark this view**. Registered views appear in a list; click one to jump to that place, or **Delete** to remove it. Bookmarks are also saved in a session.

---

## Display {#display}

Adjust the color scale. The color uses a **single absolute-value scale** shared across all tiles, so there are no seams between tiles.

**Palette** — Choose the color scheme (4 options: matlab, gentle, red, blue).

**Max value** — Dragging this slider changes the contrast and redraws all tiles. The initial value is estimated automatically by coarsely scanning the whole map when it is opened.

**linear / log10(value)** — Switch how the value scale is taken. The minimum is fixed at 0.

---

## Tracks {#tracks}

Overlay 1-D tracks below the contact map. Tracks follow the map's horizontal pan/zoom and load only the range in view. Multiple tracks can be stacked, each with its own color and height. A cursor guide line runs through the tracks.

Tracks are added from the **Tracks** tab of the loader (the **Data** button).

**Specify a file directly** — Enter a path or URL in **bigWig/BED file/URL** (**Browse…** also works), choose the **Type**, optionally set **Label** / **Color** / **Height (px)**, and click **Add track**. **Clear all** removes every track.

**Choose from an IGV XML / track list** — Load a track list or IGV XML with **Load**, then choose in the order **XML file → Category → Track** to add it.

Track types you can use:

| Type | What is drawn | Notes |
|---|---|---|
| **bigWig** | Filled area | Read via `rtracklayer` |
| **BED** | Interval boxes | Read via `rtracklayer` |
| **gene (GFF3)** | Gene arrows, exons, names | + strand on top / − strand on bottom. Exons appear when zoomed in. Names are thinned to avoid overlap. Cached as `<gff3>.genes.rds` |
| **Border Strength** | Area of `BS.norm` | Positive = red, negative = blue, baseline 0. Dashed lines at boundaries |

`track_list_url` in `config.txt` can point to a single IGV XML, or to an index file listing multiple IGV XML URLs one per line. For the details of each format, see **[Data formats](data-formats.md)**.

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
- **Default Juicer menu URL** — The menu loaded at startup.
- **Default track list / IGV XML URL** — The default track list.

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

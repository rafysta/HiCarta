# Usage

A shortest-path operation guide you can browse by "what you want to do". For what the finer options mean, see **[Screens & controls](interface.md)**, linked from each item.

To start with, the overall flow is all you need to remember: **load data → open the map → move around to view it**. That's it.

---

## Loading data

All data is loaded from the **[data catalog](data-catalog.md)** — an Excel file listing your samples, one row each — in the loader that opens when you click the **Data** button at the top of the screen (two tabs: "Data browser" and "Session").

### Load a Hi-C map {#load-hic}

1. Click the **Data** button at the top.
2. On the **Data browser** tab, load your catalog (**Load**; the field is pre-filled from `config.txt`, and **Browse…** picks a local `.xlsx`).
3. Narrow the list with the sidebar filters or search, and click the sample's row.
4. In the detail view, click **Open as contact map**.

→ Details: [Screens & controls - Data](interface.md#data), [Data catalog](data-catalog.md)

### Load a bigWig {#load-bigwig}

1. In the **Data browser**, click the row of a bigWig sample.
2. Click **Add as track**, adjust label / color / height in the dialog, and confirm.

If a Hi-C map is already open, the track is drawn on the map's coordinates.

→ Details: [Screens & controls - Tracks](interface.md#tracks)

### Tracks without a contact map {#tracks-only}

You can add tracks with no Hi-C map loaded. HiCarta then **reads the chromosome
names and lengths from the first track file you add** and shows the whole of its
first chromosome; the contact map stays hidden.

- Lengths come from the bigWig header, or from the largest coordinate found in a
  BED / GFF3 / `*_BS.txt` file.
- Navigate from the **Navigate** panel: pick a chromosome to jump to all of it,
  type Start/End and press **Go to region**, pan with the left/right buttons, and
  zoom with **+ / −**.
- If the file carries no usable chromosome information, a message says so — open
  a Hi-C map first in that case.
- Open a Hi-C map later and the contact map appears, synced to the tracks as usual.
- **Print** works for tracks alone (a coordinate axis plus the tracks).

### Load Border Strength / genes / BED {#load-bs}

Like any other track: give the file a catalog row (with `file_type` = `bs`, `gff3` or `bed`, or just let the extension decide), click the row in the **Data browser**, and choose **Add as track**.

Border Strength (`*_BS.txt`): positive values are drawn in red, negative values in blue, and boundaries are marked with dashed lines. For the file formats, see **[Data formats](data-formats.md)**.

→ Details: [Screens & controls - Tracks](interface.md#tracks)

---

## Moving around the region shown

Navigation controls are gathered in the **Navigate** menu on the left of the screen.

### Move to any location {#goto}

1. Choose **Navigate** in the top menu.
2. Choose a **Chromosome**, and enter the range you want in **Y-axis start** and **Y-axis end** (bp).
3. Click **Go to region**.

→ Details: [Screens & controls - Navigate](interface.md#navigate)

### Move with buttons {#pan}

Use the direction pad in the **Navigate** menu (up/down/left/right plus diagonals) to move the map. The step per click is set with **Step** (¼ · ½ · 1 screen). You can also drag directly on the map, or scroll to zoom.

![](../images/navigation.png)

→ Details: [Screens & controls - Navigate](interface.md#navigate)

### Show the whole chromosome {#whole}

Click the button in the center of the direction pad (⌂) in the **Navigate** menu to return to the whole-chromosome view.

→ Details: [Screens & controls - Navigate](interface.md#navigate)

### Bookmark a region of interest {#bookmark}

1. Display the region you want to bookmark.
2. If you like, enter a name in the name field at the bottom of the **Navigate** menu (optional).
3. Click **★ Bookmark this view**.

Saved bookmarks appear in a list; click one to return to that view at any time — the bookmark also remembers which data was open (and its normalization, resolution and color max), so the whole picture is restored. Remove one you no longer need with **Delete**. **Save to Excel** / **Load from Excel (append)** exchange the list as an `.xlsx` you can annotate and share ([details](data-catalog.md#bookmarks-as-excel)).

![](../images/bookmark.png)

→ Details: [Screens & controls - Navigate](interface.md#navigate)

---

## Adjusting the appearance

### Change the contrast (color intensity) {#contrast}

Choose **Display** in the top menu and drag the **Max value** slider to change the contrast. Switching between **linear / log10** and choosing a **Palette** are also done here.

![](../images/map_max_value.png)

→ Details: [Screens & controls - Display](interface.md#display)

### Adjust map height and layout {#layout}

In **Setting** in the top menu, you can set the **Contact map height**, spread it full-screen with **Fit to window**, and adjust track heights and resolution.

→ Details: [Screens & controls - Setting](interface.md#setting)

---

## Saving and exporting

### Save the view and reproduce it later (session) {#session}

**To save:**

1. Open the **Data** button → **Session** tab.
2. Click **Save current view** to download a `.json` file.

**To restore:**

1. Open the **Data** button → **Session** tab.
2. In **Restore from file (.json)**, choose the `.json` you saved.

The data source, region, color scale and all tracks are restored together.

→ Details: [Screens & controls - Data (Session)](interface.md#data)

### Export as an image / print {#print}

1. Open the map you want to export.
2. Choose **Print** in the top menu and click **Open print preview**.
3. In the preview, set the destination (Printer / File), format (PNG / PDF), paper size, output region, whether to include coordinate ticks, the legend and margins, and whether to include tracks.
4. Click **Run**.

![](../images/print_preview.png)

→ Details: [Screens & controls - Print](interface.md#print)

---

## Other

### Switch the display language {#language}

Open **Setting → Edit config file…** in the top menu, choose the **Interface language**, and click **Apply & save**. The page reloads and the language switches. Because any open map and tracks are closed when this happens, use the [session save feature](#session) if you want to return to the same state.

→ Details: [Screens & controls - Setting](interface.md#setting)

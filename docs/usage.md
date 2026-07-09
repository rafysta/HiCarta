# Usage

The top menu has six panels: **Data · Region · Display · Tracks · Setting ·
About**. A typical session: pick data → set a region → **Open map** → pan/zoom →
add tracks.

## 1. Data

Choose the contact map to view. Two ways:

- **Menu** — click **Load** to fetch the Juicer menu defined by `menu_url` in
  `config.txt`, then pick a **Sample** and **Dataset**. The dropdowns support
  partial‑text search: type part of a name to filter.
- **Local `.hic` file** — paste the path to a `.hic` on your machine. A local
  file takes priority over the menu selection.

Each `.hic` in the sample menu is a single‑resolution file; HiCarta snaps the
requested resolution/normalization to what the file actually contains.

## 2. Region

Set the **chromosome** and the **Y‑axis range** to view. Use **Go to region** to
jump; selecting a different chromosome reopens the map automatically. Chromosome
names follow the `.hic` (e.g. `I / II / III` for *S. pombe*).

## 3. Open map

Click **Open map** to load and display.

- **Drag** to pan
- **Scroll** to zoom (resolution switches automatically — level of detail)
- **Middle‑click drag** to rubber‑band zoom to a box

The header shows the current coordinates and resolution; rulers with sub‑ticks
run along the edges. The origin is top‑left and genomic *y* increases downward.

## 4. Display

Controls the colour scale. Colours use one **absolute value scale** shared by all
tiles (so there are no seams). Adjust **Max** to change contrast; all tiles
redraw. The initial `Max` is estimated from a coarse whole‑map pass on Open.

## 5. Tracks

Add 1‑D tracks below the contact map. Tracks follow the map's horizontal
pan/zoom, only the visible window is read, and multiple tracks can be stacked
with individual colour and height. A cursor guide line runs through the tracks.

| Type | Shows | Notes |
|---|---|---|
| **bigWig** | filled area | read with `rtracklayer` |
| **BED** | interval boxes | read with `rtracklayer` |
| **gene (GFF3)** | gene arrows, exons, names | + strand upper / − strand lower; exons appear when zoomed in; names thinned to avoid overlap; caches `<gff3>.genes.rds` |
| **Border Strength** | `BS.norm` area | positive = red, negative = blue, baseline 0; dashed lines at boundaries |

`track_list_url` in `config.txt` can point to a single IGV XML or an index file
listing several IGV XML URLs (one per line). With an index, choose
**XML file → Category → Track**.

## 6. Setting

Layout controls: **map height**, **Fit to window** (map = window minus the sum of
track heights), auto‑adjust, and track resolution.

## About

Version and author information (Hideki Tanizawa, rafysta@gmail.com).

---

## Notes & current scope

- HiCarta currently targets **cis** contacts (within a single chromosome).
- Track chromosome names like `chrII` are matched to the `.hic` names (`II`)
  where possible.

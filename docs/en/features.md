# What HiCarta can do

A list of what you can do with HiCarta. Each item links to the corresponding step-by-step instructions in **[Usage](usage.md)**.

## Loading data

### View a Hi-C contact map like a map

You can explore a Hi-C contact map with the same feel as a map app. Drag to pan and scroll to zoom; because only the tiles in view are loaded, it stays responsive even on high-resolution maps and large genomes. The resolution switches automatically as you zoom.

→ [Load a Hi-C map](usage.md#load-hic)

### Read `.hic` files directly

You can read Juicer-format `.hic` files directly. Pick a sample, dataset, normalization and resolution from a prepared menu, or point to a local `.hic` file on your computer.

→ [Load a Hi-C map](usage.md#load-hic)

### Overlay 1-D tracks

Below the contact map you can overlay bigWig (quantitative signal), BED (intervals), gene models (GFF3 format) and Border Strength (the strength of domain boundaries such as TADs). Tracks follow the map's horizontal pan/zoom and can be stacked.

→ [Load a bigWig](usage.md#load-bigwig) · [Load Border Strength](usage.md#load-bs) · [Load genes / BED](usage.md#load-other)

### Save a session

You can save the "whole view" — data source, region, color scale and all tracks — to a single file (`.json`). Load it later to reproduce exactly the same view. This is handy for saving analysis results or sharing them with others. Bookmarks are saved too, which makes resuming an analysis easy.

→ [Save the view and reproduce it later](usage.md#session)

## Navigation

### Jump to any location

Enter a chromosome name and a Y-axis range to jump straight to the region you want to see.

→ [Move to any location](usage.md#goto)

### Move with buttons

Use the 8-direction buttons (up/down/left/right plus diagonals) to move the map one screen at a time (step size selectable from ¼ · ½ · 1). The center button returns to the whole-chromosome view.

→ [Move with buttons](usage.md#pan)

### Bookmarks

Give the current view (region) a name and save it, then return to the same place later with one click. Useful for registering regions you revisit often.

→ [Bookmark a region of interest](usage.md#bookmark)

## Adjusting the appearance

### Adjust the contact map's color scale

The color of the Hi-C contact map can use any of 4 color palettes (matlab, gentle, red, blue). Change the map's maximum value interactively to see how the appearance changes on the spot. Adjust the maximum with the linear or log10 slider, or by typing a value directly.

![](../images/color_pallete.png)

→ [Change the contrast (color intensity)](usage.md#contrast)

### Adjust a track's color, height and name

Tracks such as bigWig, genes, BED and Border Strength can each be given a name of your choice, and their height and color can be adjusted. The Y-axis maximum can be set to either auto mode or a fixed value. You can also adjust a track's drawing resolution interactively, so you can, for example, view ChIP-seq peaks at a resolution matched to the Hi-C contact map.

→ [Track settings in detail (Screens & controls)](interface.md#tracks)

### Export or print as a publication-quality image

Export a chosen region of the currently open map as a PNG image or PDF. Choose the output region while checking it in the preview, and export them one after another. You can also choose whether to include coordinate ticks, the legend and tracks in the output. For publications, use the no-margins option to export just the contact map and edit it yourself. You can also print directly to a printer.

![](../images/print_preview.png)

→ [Export as an image / print](usage.md#print)

### Adjust the height of the output panels

The height of the Hi-C contact map can be set to a specific number, or adjusted automatically to fit the display area on screen. Each track's height can also be adjusted independently.

→ [Adjust map height and layout](usage.md#layout)

## Fast loading

Remote `.hic` and bigWig files are downloaded and cached locally once on first open. From then on they are read from that cache, so the app runs very fast.

→ [Load a Hi-C map](usage.md#load-hic)

## Switch the interface language

You can switch the interface between Japanese and English.

→ [Switch the display language](usage.md#language)

---

Where each feature is operated on screen, and what the finer options mean, is documented in **[Screens & controls](interface.md)**.

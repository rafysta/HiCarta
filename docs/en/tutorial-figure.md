# Tutorial: make a publication figure

This tutorial explains how to export the displayed Hi-C map and tracks as a PDF figure for publication and refine the figure in Illustrator, Inkscape, or similar tools.

In the PDF, the Hi-C map is saved as a raster image, and the coordinate ticks, labels, legend, and tracks as editable vector graphics. Rasterizing the map helps keep file sizes manageable, even at high resolution, while allowing text and lines to be edited afterward.

## 1. Set up the figure on screen

The figure is generated from the current view. Configure the displayed data first to minimize adjustments in the print preview.

- **Region** — navigate to the genomic region you want to export. Exact coordinates can also be entered in the preview.
- **Colors** — choose the palette and the maximum value under **Display → Map**.
- **Tracks** — add the tracks you need, and configure their order, names, colors, heights, and maximum values under **Display → Tracks**. Track names become the labels in the figure.
- **Comparison** — for a figure comparing two conditions, switch to a comparison view first (**[Compare two conditions](tutorial-compare.md)**).

## 2. Open the print preview

Open **Print** at the top of the screen and click **Open print preview**. The preview updates when you change a setting.

![](../images/print_preview.png)

| Setting | What it does |
|---|---|
| **Destination** | **File** or **Printer** |
| **Output folder / File name / Format** | The format is **PDF** or **Image (PNG)**. PDF is recommended for editable publication figures. |
| **Paper size** | A4 portrait, A4 landscape, square or custom (width and height in mm) |
| **Output region** | Chromosome, start and end (bp) on each axis. Choosing a different chromosome for the Y axis exports an inter-chromosome map. |
| **Resolution** | Select "same as the map on screen" to use the resolution of the current view. The resolution actually used is shown below the preview. |
| **Same bp scale on both axes** | Uses the same scale per base pair along both axes (enabled by default), preserving the genomic aspect ratio. |
| **Include coordinate ticks / Include legend** | Whether to include the coordinate ticks and the color-scale legend |
| **No margins** | Exports only the map, without margins. Use this option if you plan to recreate the axes and labels manually. |
| **Sample info under the map** | Includes the sample name, genomic region, and resolution below the figure. For split-view comparisons, information for sample A (upper right) and sample B (lower left) is also included. |
| **Also export tracks** | Exports the visible tracks together with the map, aligned horizontally with it. |

## 3. Export

After configuring the output, click **Run**. A message displays the saved file location. The preview stays open, so you can change the region or settings and export again.

## 4. Finish in Illustrator or Inkscape

Open the exported PDF in Illustrator or Inkscape, and select and edit individual coordinate ticks, labels, legends, and track lines and fills.

- Change fonts, font sizes, line widths and colors to meet the journal's requirements.
- The Hi-C map is a raster image. Scale the map and the tracks together to keep their positions aligned.
- When arranging figures from multiple genomic regions or conditions side by side, export them with the same settings (paper size, resolution, maximum value) to keep their sizes and color scales consistent.

!!! tip "For slides and posters"
    Set the format to **Image (PNG)** to export an image that can be inserted directly into a slide or poster.

## 5. Recreate the same figure later

If you save a **session**, you can restore the view later, including the data sources, region, color scale and tracks. This is useful when you need to recreate or revise a figure during peer review. → [Save the view and reproduce it later (session)](usage.md#session)

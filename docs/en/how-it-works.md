# How HiCarta works

This page explains how HiCarta maintains responsive navigation with large Hi-C datasets and how it retrieves data. For the basic operations, see **[Usage](usage.md)**.

## The roles of R and the browser

HiCarta is built using Shiny for R. On launch, R starts a local web server on your computer (`http://127.0.0.1:7788`), and your browser displays the user interface.

- **R** — reads files, retrieves contact matrices, maps values to colors, renders tracks, and generates PDF files.
- **Web browser** — displays the interface and handles interactions such as dragging and scrolling (the map is displayed with Leaflet).

Both components run on the same computer, so you do not need a separate server. Data processing takes place locally; the retrieved data are not sent to a separate server for processing.

## Tile-based rendering

Like a web map, HiCarta draws the map in **tiles of 256 × 256 pixels**.

1. HiCarta requests only tiles in the visible area, prioritizing those near the center of the screen.
2. For each tile, only the matching two-dimensional region is read from the `.hic` file. The resolution is chosen automatically from the zoom level (level of detail, LOD).
3. Contact values are mapped to colors, and the resulting tile image is sent to the browser. Tiles far from the visible area are discarded.

All tiles share one color scale, so the colors are consistent across tiles. When a map is opened, HiCarta scans the whole map at low resolution to set the initial maximum value.

## Partial retrieval of remote files

HiCarta has its own readers for `.hic` and bigWig files, written in R. The readers use the internal file indexes to retrieve only the required byte ranges via HTTP range requests.

- By default, `.hic` and bigWig files on web servers, Dropbox shared links, and Amazon S3 can be displayed **without downloading the whole file**.
- Connections are reused, and previously retrieved data are cached in memory to speed up revisits to cached regions.
- On a slow or unstable connection, setting `hic_engine = download` in `config.txt` saves the entire file to the `_hic_cache/` folder first and reads it from there. The first view takes longer, but later operations may be more stable.
- BED, GFF3, and Border Strength files are read in full when loaded. For GFF3, the parsed gene annotations are cached as `*.genes.rds` to accelerate subsequent loads.

## Reading private files

For private Amazon S3 objects, whether specified as `s3://bucket/key` or as S3 HTTPS URLs, HiCarta signs requests using the AWS credentials stored on your computer (`~/.aws/credentials`). Access is determined by the permissions configured in S3. Combining object tags with per-user permissions lets you control sharing by lab or group. → [Private data on Amazon S3](data-catalog.md#private-data-on-amazon-s3)

## Coordinates

The map origin is at the upper-left corner. Genomic coordinates increase to the right (X axis) and downward (Y axis). Tracks are drawn along the X-axis coordinates.

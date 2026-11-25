# Comparison with other tools

Each Hi-C visualization tool has its own strengths. HiCarta focuses on browsing and comparing your lab’s data locally and exporting the results as figures for publication. Other tools may be better suited to exploring public datasets or building large collaborative data portals.

## Feature comparison

Symbols: ✓ = supported, △ = partially supported or conditional, – = not supported

| | **HiCarta** | Juicebox | HiGlass | WashU | UCSC | JBrowse 2 | pyGenomeTracks | plotgardener |
|---|---|---|---|---|---|---|---|---|
| Type | Desktop (R, browser-based interface) | Desktop (Java) / Web | Web + server | Web | Web | Web / Desktop | Command line | R package |
| No separate server required | ✓ | ✓ | – (needs a server) | △ (files must be web-accessible) | △ (files must be web-accessible) | ✓ (Desktop) | ✓ | ✓ |
| Reads `.hic` directly | ✓ | ✓ | – (conversion needed) | ✓ | ✓ | ✓ | – (conversion needed) | ✓ |
| Interactive zoom | ✓ | ✓ | ✓ | ✓ | △ (page redraw) | ✓ | – | – |
| 1D tracks (bigWig, BED, gene annotations) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Loops drawn as arcs | ✓ | △ (2D boxes) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Compare two Hi-C maps | ✓ (split, curtain, difference) | ✓ (Observed vs Control, ratio) | ✓ (side by side, synchronized) | △ | – | ✓ (Compare with) | △ (side by side) | △ (side by side) |
| Custom visualization extensions | ✓ (R) | – | ✓ (JavaScript) | – | – | ✓ (JavaScript) | ✓ (Python) | ✓ (R code) |
| Editable figures for publication | ✓ (PDF) | ✓ (PDF / SVG) | ✓ (SVG) | ✓ (SVG) | ✓ (PDF) | ✓ (SVG) | ✓ | ✓ |
| Sample management in Excel | ✓ | – | – | – | – | – | – | – |
| Sharing unpublished data | ✓ (access control by S3 tags) | – | △ (depends on the server setup) | △ | △ | △ | – | – |
| Wide range of public data | – | △ | ✓ | ✓ | ✓ | △ | – | – |
| Cross-genome comparison (synteny) | – | – | △ | △ | – | ✓ | – | – |

This comparison reflects the tools’ documentation as of November 2026. If you notice an error or outdated information, please let us know through [GitHub Issues](https://github.com/rafysta/HiCarta/issues).

## What HiCarta is good for

- Viewing your lab's Hi-C data on your own computer, without setting up a server.
- Quickly comparing Hi-C maps from two conditions at the same genomic region.
- Exporting the current view as an editable figure for publication.
- Visualizing custom analysis results in R alongside the Hi-C map.
- Managing hundreds of samples in Excel and sharing a common data catalog with collaborators.
- Sharing unpublished data only with collaborators who have been granted access.

## What other tools are good for

- **Browsing a wide range of public data** — 3D Genome Browser, WashU Epigenome Browser, UCSC Genome Browser and HiGlass (higlass.io) host many public datasets.
- **Sharing a view via a URL** — Juicebox Web and HiGlass can share the current view as a URL.
- **Comparing two genomes side by side** — use the linear synteny view of JBrowse 2.
- **Generating multiple figures with a consistent layout using scripts** — pyGenomeTracks and plotgardener are well suited to this task.

## References

- Juicebox: [Comparing Maps (Desktop)](https://aidenlab.gitbook.io/juicebox/comparing-maps), [Juicebox Web](https://igvteam.github.io/juicebox-web)
- HiGlass: [tutorial](https://docs.higlass.io/tutorial.html), [higlass-server](https://github.com/higlass/higlass-server)
- WashU Epigenome Browser: [usage](https://epigenome.readthedocs.io/en/stable/usage.html), [track types](https://epgg.github.io/datahub/track_properties)
- UCSC Genome Browser: [Hi-C tracks](https://genome.ucsc.edu/goldenPath/help/hic.html)
- JBrowse 2: [Hi-C track](https://jbrowse.org/jb2/docs/user_guides/hic_track/), [features](https://jbrowse.org/features)
- pyGenomeTracks: [hic_matrix](https://pygenometracks.readthedocs.io/en/latest/content/tracks/hic_matrix.html)
- plotgardener: [paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC8963281)

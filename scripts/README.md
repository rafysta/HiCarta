# scripts/

Utility scripts for preparing data for HiCarta. These are **not** needed to run
the app — only to convert or preprocess input data.

| Script | Purpose |
|---|---|
| `juicer_menu_to_catalog.R` | Convert a legacy Juicer‑style menu file into a data catalog (`.xlsx`). One row per sample; a sample's datasets are `;`‑joined. `--collapse` also rewrites legacy per‑normalization names (`NAME_ICE.5kb.hic` → `NAME.hic`) and drops duplicates. |
| `igv_xml_to_catalog.R` | Convert a legacy IGV track‑list XML into a data catalog (`.xlsx`). One row per `<Resource>`; the `<Category>` becomes the `project` column. |
| `catalog_to_juicer_menu.R` | Export the Hi‑C rows of a catalog back to a Juicer‑style menu file. |
| `catalog_to_igv_xml.R` | Export the track rows of a catalog back to an IGV track‑list XML (grouped into categories by `project`). |
| `convert_hic200_to_hic.sh` | Convert hic200‑cpp raw maps (`.txt.gz`) to Juicer `.hic` so they load through HiCarta's fast `.hic` path. Requires Java + `juicer_tools.jar`. See [../docs/en/data-formats.md](../docs/en/data-formats.md). |
| `test_hic_reader.R` / `test_bigwig_reader.R` | Developer test suites for the pure‑R readers. |
| `test_hic_resolutions.R` | Developer test for the chromosome‑aware resolution probe (a `.hic` header lists resolutions globally; one chromosome can carry fewer zoom levels, and a normalization vector can be missing at some of them). Needs network access. |

## Catalog converters

Run from the HiCarta folder (they source files in `R/`). The two `*_to_catalog`
scripts need the `writexl` package.

```bash
Rscript scripts/juicer_menu_to_catalog.R  menu.txt     catalog.xlsx [--collapse]
Rscript scripts/igv_xml_to_catalog.R      tracks.xml   catalog.xlsx
Rscript scripts/catalog_to_juicer_menu.R  catalog.xlsx menu.txt
Rscript scripts/catalog_to_igv_xml.R      catalog.xlsx tracks.xml
```

For the catalog column spec see the
[Data catalog docs](https://rafysta.github.io/HiCarta/data-catalog/).

## convert_hic200_to_hic.sh

```bash
JUICER=/path/to/juicer_tools.jar \
  bash scripts/convert_hic200_to_hic.sh sample/bin_def_200bp.txt file1.txt.gz [file2.txt.gz ...]
```

Produces `file1.hic` next to each input. Environment variables:

- `JUICER` — path to `juicer_tools.jar` (default `juicer_tools.jar`)
- `RES` — comma‑separated resolutions (default `200,1000,2000,5000,10000,20000,50000,100000`)
- `JMEM` — Java heap (default `6g`)

The script derives `chrom.sizes` from the bin definition, maps each 200 bp bin
index to its midpoint, writes Juicer "short with score" records, and runs
`juicer_tools pre -n`.

# Data formats

HiCarta supports several genomic data formats. Contact maps use `.hic` files; signals, genomic intervals, gene annotations, loops, and other data are displayed as tracks.

## Contact maps: `.hic` (Juicer)

This is the primary contact map format. HiCarta supports random access to genomic regions at multiple resolutions. By default, remote `.hic` files are streamed using HTTP range requests. `.hic`
files are opened from the **[data catalog](data-catalog.md)** or by entering the
path directly (**Data → Direct file**).

- Chromosome names must match those in the `.hic` file (e.g. `I / II / III` for
  *S. pombe*).
- A `.hic` file may contain only one resolution. HiCarta adjusts the requested resolution and normalization to those available in the file. Several single‑resolution
  files for the same sample can be registered in one catalog row and be opened together as a
  virtual multi‑resolution dataset.

## Tracks

| Format | Panel type | Notes |
|---|---|---|
| **bigWig** | bigWig | quantitative signal, drawn as a filled area |
| **BED** | BED | intervals, drawn as boxes |
| **GFF3** | gene (GFF3) | gene models; parsed once and cached as `<gff3>.genes.rds` |
| **`*_BS.txt`** | Border Strength | TAD boundary strength; see below |

### Border Strength (`*_BS.txt`)

This format is produced by [BorderStrength](https://github.com/rafysta/BorderStrength). Columns:
`chr, start, end, BS, BS.norm, boundary, TADid, TAD` (200 bp bins). HiCarta plots
`BS.norm` as an area (positive red, negative blue, baseline 0) with dashed lines at positions where `boundary != 0`.

A header containing these column names is expected. Files without a header are interpreted by column position (`chr, start, end, BS, BS.norm, ...`). Bin sizes are not restricted to 200 bp; other sizes, such as 40 kb, are also supported.

---

## hic200‑cpp raw maps (`.txt.gz`) → `.hic`

hic200‑cpp outputs a gzip-compressed text representation of a contact matrix (`bin1 bin2 score`, upper triangle,
200 bp global bin indices). Rather than reading the large text file directly, convert it **once** to a compressed, indexed, multi-resolution `.hic` file and load it locally. The resulting file is typically comparable in size to the `.txt.gz` file but supports much faster regional access.

### Requirements

- Java (to run Juicer Tools)
- `juicer_tools.jar` — <https://github.com/aidenlab/juicer/wiki/Download>
- the matching **bin definition** file (e.g. `sample/bin_def_200bp.txt`), which
  maps each global bin index to `(chromosome, start)`

### Conversion outline

The repository includes a wrapper script that automates the conversion:

```bash
JUICER=/path/to/juicer_tools.jar \
  bash scripts/convert_hic200_to_hic.sh sample/bin_def_200bp.txt file1.txt.gz [file2.txt.gz ...]
```

The script generates a corresponding `.hic` file (e.g., `file1.hic`) alongside each input file. Configure the conversion using the following environment variables: `RES` (resolutions), `JMEM` (Java heap), `JUICER` (path to the jar).

Internally, the script (1) derives `chrom.sizes` from the bin definition, (2) maps each
200 bp bin index to its **midpoint**, (3) writes Juicer "short with score" records
(`<str1> <chr1> <pos1> <frag1> <str2> <chr2> <pos2> <frag2> <score>`), and
(4) runs `juicer_tools pre -n` (no normalization) to build the multi‑resolution
`.hic`.

After conversion, register the new `.hic` in your data catalog and open it from
the **Data browser**. See also
[scripts/README.md](https://github.com/rafysta/HiCarta/blob/main/scripts/README.md).

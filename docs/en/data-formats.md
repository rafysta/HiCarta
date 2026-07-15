# Data formats

HiCarta reads several formats. Contact maps come from `.hic`; everything else is
a 1‑D track.

## Contact maps: `.hic` (Juicer)

The primary format. HiCarta reads regions directly with `strawr` (random access,
multi‑resolution). Load either from the menu (`menu_url`) or as a **local `.hic`
file** in the Data panel.

- Chromosome names must match those inside the `.hic` (e.g. `I / II / III` for
  *S. pombe*).
- Each menu `.hic` may be single‑resolution; HiCarta snaps the requested
  resolution/normalization to what the file contains.

## Tracks

| Format | Panel type | Notes |
|---|---|---|
| **bigWig** | bigWig | quantitative signal, drawn as a filled area |
| **BED** | BED | intervals, drawn as boxes |
| **GFF3** | gene (GFF3) | gene models; parsed once and cached as `<gff3>.genes.rds` |
| **`*_BS.txt`** | Border Strength | TAD boundary strength; see below |

### Border Strength (`*_BS.txt`)

Produced by [BorderStrength](https://github.com/rafysta/BorderStrength). Columns:
`chr, start, end, BS, BS.norm, boundary, TADid, TAD` (200 bp bins). HiCarta plots
`BS.norm` as an area (positive red, negative blue, baseline 0) with dashed lines
where `boundary != 0`.

---

## hic200‑cpp raw maps (`.txt.gz`) → `.hic`

hic200‑cpp output is a gzipped text matrix (`bin1 bin2 score`, upper triangle,
200 bp global bin indices). Rather than reading this huge text directly, convert
it **once** to a compressed, indexed, multi‑resolution `.hic`, then load it as a
local `.hic`. The `.hic` is roughly the size of the `.txt.gz` but far faster.

### Requirements

- Java (to run Juicer Tools)
- `juicer_tools.jar` — <https://github.com/aidenlab/juicer/wiki/Download>
- the matching **bin definition** file (e.g. `sample/bin_def_200bp.txt`), which
  maps each global bin index to `(chromosome, start)`

### Conversion outline

The repository ships a wrapper script that automates the whole conversion:

```bash
JUICER=/path/to/juicer_tools.jar \
  bash scripts/convert_hic200_to_hic.sh sample/bin_def_200bp.txt file1.txt.gz [file2.txt.gz ...]
```

It produces `file1.hic` next to each input. Tune the output with environment
variables: `RES` (resolutions), `JMEM` (Java heap), `JUICER` (path to the jar).

Under the hood it (1) derives `chrom.sizes` from the bin definition, (2) maps each
200 bp bin index to its **midpoint**, (3) writes Juicer "short with score" records
(`<str1> <chr1> <pos1> <frag1> <str2> <chr2> <pos2> <frag2> <score>`), and
(4) runs `juicer_tools pre -n` (no normalization) to build the multi‑resolution
`.hic`.

After conversion, open `output.hic` via **Data → local `.hic` file**. See also
[scripts/README.md](https://github.com/rafysta/HiCarta/blob/main/scripts/README.md).

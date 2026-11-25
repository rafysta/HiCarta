# Sample data

## Demo catalog (start here)

`HiCarta_demo_catalog.xlsx` lists public Hi-C maps and tracks that HiCarta reads
straight from the web — nothing has to be downloaded first. Load it in
**Data → Data browser** (Browse… for this file, or paste the online copy):

```
https://uo-cgf.s3.us-west-2.amazonaws.com/HiCarta/demo/HiCarta_demo_catalog.xlsx
```

| Data | Source |
|---|---|
| IMR90 Hi-C, Growing and OIS (built only from the GEO samples) | GEO GSE118494 — Iwasaki *et al.*, *Nat Commun* 2019 |
| IMR90 CTCF / SMC1 / Pol II ChIP-seq (bigWig, Growing and OIS) | GEO GSE118494 (same files, served from S3) |
| IMR90 deep Hi-C and HiCCUPS loops | GEO GSE63525 — Rao *et al.*, *Cell* 2014 |
| Fission yeast Hi-C, G2 (cdc25, 20 min) and mitosis (50 min) | GEO GSE93198 — Tanizawa *et al.*, *Nat Struct Mol Biol* 2017 |
| Genes | GENCODE v19 (human), PomBase (fission yeast) |

The `notes` sheet in the catalog repeats these sources.

## Files in this folder

| File | Used by | Description |
|---|---|---|
| `HiCarta_catalog_template.xlsx` | your own data | Empty catalog to copy: one row per file, with notes on every column. |
| `HiCarta_demo_catalog.xlsx` | demo | The demo catalog described above (all paths are public URLs). |
| `HiCarta_demo_bookmarks_hg19.xlsx` | demo | Bookmarks (Navigate → Load from Excel): two demo loci on chr5 and 14 senescence-associated (SASP) genes, hg19. |
| `IMR90_loops_Rao2014_HiCCUPS_hg19.bedpe` | arc track | IMR90 HiCCUPS loop list from GSE63525 with `chr` added to the chromosome names (8,040 loops; strength = observed contacts `o`). |
| `Schizosaccharomyces_pombe_all_chromosomes.gff3` | gene (GFF3) track | PomBase gene models. Parsed on first use and cached as `*.genes.rds` (git‑ignored). |
| `bin_def_200bp.txt` | hic200 → `.hic` conversion | Maps 200 bp global bin indices to `(chromosome, start)`. Needed to convert hic200‑cpp `.txt.gz` maps. See [../docs/en/data-formats.md](../docs/en/data-formats.md). |
| `example_border_strength_BS.txt` | Border Strength track | Format example (`chr, start, end, BS, BS.norm, boundary, TADid, TAD`). |
| `juicer_sample.txt` | legacy Juicer menu | Example of the old menu format (see [../scripts/README.md](../scripts/README.md)). |

# Sample data

Small *Schizosaccharomyces pombe* (fission yeast, chromosomes `I / II / III`)
fixtures for trying HiCarta and its tracks. These are **not** full datasets — the
example `.hic` contact maps are fetched from the public menu (`menu_url` in
`config.txt`), not stored here.

| File | Used by | Description |
|---|---|---|
| `Schizosaccharomyces_pombe_all_chromosomes.gff3` | gene (GFF3) track | PomBase gene models. Parsed on first use and cached as `*.genes.rds` (git‑ignored). |
| `bin_def_200bp.txt` | hic200 → `.hic` conversion | Maps 200 bp global bin indices to `(chromosome, start)`. Needed to convert hic200‑cpp `.txt.gz` maps. See [../docs/data-formats.md](../docs/data-formats.md). |
| `cdc25-20min_HiC_Double-MHM_Bio2_BS.txt` | Border Strength track | Border Strength at 200 bp (`chr, start, end, BS, BS.norm, boundary, TADid, TAD`). |
| `wt_HiC_Double_MHM_bio2_10kb_BS.txt` | Border Strength track | Border Strength at 10 kb. |
| `juicer_sample.txt` | Data menu | Example Juicer menu (`id = parent, label[, url]`). |

Public test contact maps and menu:
<https://uo-cgf.s3.us-west-2.amazonaws.com/P/020/juicer_020.txt>
(Juicer v8, *S. pombe* I/II/III).

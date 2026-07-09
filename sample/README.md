# Sample data

Small *Schizosaccharomyces pombe* (fission yeast, chromosomes `I / II / III`)
fixtures for trying HiCarta and its tracks. These are **not** full datasets — the
example `.hic` contact maps are fetched from the public menu (`menu_url` in
`config.txt`), not stored here.

| File | Used by | Description |
|---|---|---|
| `Schizosaccharomyces_pombe_all_chromosomes.gff3` | gene (GFF3) track | PomBase gene models. Parsed on first use and cached as `*.genes.rds` (git‑ignored). |
| `bin_def_200bp.txt` | hic200 → `.hic` conversion | Maps 200 bp global bin indices to `(chromosome, start)`. Needed to convert hic200‑cpp `.txt.gz` maps. See [../docs/data-formats.md](../docs/data-formats.md). |
| `example_border_strength_BS.txt` | Border Strength track | Border Strength (`chr, start, end, BS, BS.norm, boundary, TADid, TAD`). |

Public test contact maps and menu (set this as `menu_url` in your `config.txt`
to try the app quickly):
<https://uo-cgf.s3.us-west-2.amazonaws.com/P/020/juicer_020.txt>
(Juicer v8, *S. pombe* I/II/III).

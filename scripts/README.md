# scripts/

Utility scripts for preparing data for HiCarta. These are **not** needed to run
the app — only to convert or preprocess input data.

| Script | Purpose |
|---|---|
| `convert_hic200_to_hic.sh` | Convert hic200‑cpp raw maps (`.txt.gz`) to Juicer `.hic` so they load through HiCarta's fast `.hic` path. Requires Java + `juicer_tools.jar`. See [../docs/data-formats.md](../docs/data-formats.md). |

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

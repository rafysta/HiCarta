# Demo data

To help you get started, we provide a **demo catalog** containing only publicly available data. All listed files are available online. By default, HiCarta retrieves only the required portions of `.hic` and bigWig files; other formats are read in full when needed.

## Opening the demo catalog

In **Data → Data browser**, paste the following URL into the catalog field and click **Load catalog**.

```
https://uo-cgf.s3.us-west-2.amazonaws.com/HiCarta/demo/HiCarta_demo_catalog.xlsx
```

The same catalog is included in the repository at `sample/HiCarta_demo_catalog.xlsx` (select it with **Browse…**). See **[First 5 minutes](first-5-minutes.md)** for step-by-step instructions.

## Contents of the catalog

| id | Name | Type | Genome |
|---|---|---|---|
| 1 | IMR90 Hi-C, deep (Rao 2014) | Hi-C (`.hic`, KR) | hg19 |
| 2 | IMR90 Growing Hi-C | Hi-C (`.hic`, KR) | hg19 |
| 3 | IMR90 OIS Hi-C | Hi-C (`.hic`, KR) | hg19 |
| 11, 12 | CTCF ChIP-seq Growing / OIS | bigWig | hg19 |
| 13, 14 | SMC1 ChIP-seq Growing / OIS | bigWig | hg19 |
| 15, 16 | Pol II ChIP-seq Growing / OIS | bigWig | hg19 |
| 21 | IMR90 loops (Rao 2014, HiCCUPS) | Loops (arcs) | hg19 |
| 31 | Genes (GENCODE v19, protein-coding) | Genes (GFF3) | hg19 |
| 41 | Virtual 4C from chr5:149,215,000 (Rao 2014) | Plugin (Virtual 4C) | hg19 |
| 51 | S. pombe Hi-C G2 (cdc25, 20 min) | Hi-C (`.hic`, KR) | ASM294v2 |
| 52 | S. pombe Hi-C mitosis (cdc25, 50 min) | Hi-C (`.hic`, KR) | ASM294v2 |
| 61 | S. pombe genes (PomBase) | Genes (GFF3) | ASM294v2 |

The track with ID 41 is rendered by the plugin `plugins/virtual4c.R`, which is included with HiCarta. The `notes` sheet of the catalog also lists the data sources.

## Data sources and processing

### Proliferating and senescent IMR90 cells (id 2, 3, 11–16)

Iwasaki O, Tanizawa H, Kim KD *et al.* Involvement of condensin in cellular senescence through gene regulation and compartmental reorganization. *Nat Commun* **10**, 5688 (2019). [GEO GSE118494](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE118494)

- **Hi-C (id 2, 3)** — Generated exclusively from samples deposited in GEO. The proliferating-cell (Growing) map combines two samples (GSM3330966, GSM3330967), and the oncogene-induced senescent-cell (OIS, H-RasV12) map combines three samples (GSM3330968–GSM3330970). Resolutions range from 5 kb to 1 Mb, with KR-normalized and unnormalized (NONE) data available.
- **ChIP-seq (id 11–16)** — identical to the supplementary bigWig files in GEO. Copies of the same files are hosted on Amazon S3 to facilitate reliable partial reads in HiCarta.

### High-depth Hi-C and chromatin loops in IMR90 cells (id 1, 21, 41)

Rao SSP, Huntley MH, Durand NC *et al.* A 3D map of the human genome at kilobase resolution reveals principles of chromatin looping. *Cell* **159**, 1665–1680 (2014). [GEO GSE63525](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE63525)

- **Hi-C (id 1)** — A `.hic` file combining in situ Hi-C data from IMR90 cells (seven libraries). Resolutions range from 5 kb to 500 kb, with KR normalization. These data are suitable for detailed visualization of kilobase-scale regions and loops.
- **Loops (id 21)** — `GSE63525_IMR90_HiCCUPS_looplist.txt.gz` from GEO (8,040 loops detected by HiCCUPS), with `chr` added to the chromosome names. The observed contact count (column `o`) is used as the loop strength. The processed file is available at `sample/IMR90_loops_Rao2014_HiCCUPS_hg19.bedpe`.

### Fission yeast in G2 and mitosis (id 51, 52)

Tanizawa H, Kim KD, Iwasaki O, Noma K. Architectural alterations of the fission yeast genome during the cell cycle. *Nat Struct Mol Biol* **24**, 965–976 (2017). [GEO GSE93198](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE93198)

Hi-C data were collected from synchronized *cdc25-22* cells 20 minutes (G2) and 50 minutes (mitosis) after release from the block.

### Gene annotation (id 31, 61)

- **Human** — protein-coding genes of GENCODE v19 (hg19), with one representative transcript per gene.
- **Fission yeast** — PomBase gene models (`sample/Schizosaccharomyces_pombe_all_chromosomes.gff3`).

## Bookmarks

`sample/HiCarta_demo_bookmarks_hg19.xlsx` contains bookmarks (hg19) for the two demo regions (chr5) and for 14 senescence-associated secretory phenotype (SASP) genes. Load it with **Load from Excel (append)** in the bookmark section of the **Navigate** panel.

## Using the data

If you use the demo data in a paper or elsewhere, please cite the original publication for each dataset. To cite HiCarta itself, see the citation instructions in the README.

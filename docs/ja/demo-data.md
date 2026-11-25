# デモデータ

HiCarta をすぐに試せるように、公開データだけを集めた**デモカタログ**を用意しています。カタログに記載したファイルはすべてインターネット上にあります。`.hic` や bigWig は必要な部分だけを読み込み、その他の形式は必要に応じてファイル全体を読み込みます。

## デモカタログの開き方

**データ → データブラウザ** で、カタログの欄に次の URL を貼り付けて **カタログを読み込む** をクリックします。

```
https://uo-cgf.s3.us-west-2.amazonaws.com/HiCarta/demo/HiCarta_demo_catalog.xlsx
```

同じカタログは、リポジトリの `sample/HiCarta_demo_catalog.xlsx` にもあります（**参照…** から選べます）。手順は **[はじめての 5 分](first-5-minutes.md)** を参照してください。

## カタログの内容

| id | 名前 | 種類 | ゲノム |
|---|---|---|---|
| 1 | IMR90 Hi-C, deep (Rao 2014) | Hi-C（`.hic`、KR） | hg19 |
| 2 | IMR90 Growing Hi-C | Hi-C（`.hic`、KR） | hg19 |
| 3 | IMR90 OIS Hi-C | Hi-C（`.hic`、KR） | hg19 |
| 11、12 | CTCF ChIP-seq Growing／OIS | bigWig | hg19 |
| 13、14 | SMC1 ChIP-seq Growing／OIS | bigWig | hg19 |
| 15、16 | Pol II ChIP-seq Growing／OIS | bigWig | hg19 |
| 21 | IMR90 loops (Rao 2014, HiCCUPS) | ループ（弧） | hg19 |
| 31 | Genes (GENCODE v19, protein-coding) | 遺伝子（GFF3） | hg19 |
| 41 | Virtual 4C from chr5:149,215,000 (Rao 2014) | プラグイン（Virtual 4C） | hg19 |
| 51 | S. pombe Hi-C G2 (cdc25, 20 min) | Hi-C（`.hic`、KR） | ASM294v2 |
| 52 | S. pombe Hi-C mitosis (cdc25, 50 min) | Hi-C（`.hic`、KR） | ASM294v2 |
| 61 | S. pombe genes (PomBase) | 遺伝子（GFF3） | ASM294v2 |

ID 41 のデータは、HiCarta に同梱しているプラグイン `plugins/virtual4c.R` で描画します。カタログの `notes` シートにも、データの出典を記載しています。

## データの出典と加工方法

### 増殖期および老化状態の IMR90 細胞（id 2、3、11〜16）

Iwasaki O, Tanizawa H, Kim KD *et al.* Involvement of condensin in cellular senescence through gene regulation and compartmental reorganization. *Nat Commun* **10**, 5688 (2019). [GEO GSE118494](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE118494)

- **Hi-C（id 2、3）** — GEO に登録されたサンプルだけを用いて作成しています。増殖細胞（Growing）は 2 サンプル（GSM3330966、GSM3330967）、がん遺伝子誘導性老化細胞（OIS、H-RasV12）は 3 サンプル（GSM3330968〜GSM3330970）をまとめています。解像度は 5 kb〜1 Mb、KR 正規化と正規化なし（NONE）に対応しています。
- **ChIP-seq（id 11〜16）** — GEO の補足ファイル（bigWig）と同一のファイルです。HiCarta からの部分読み込みを安定させるため、同じファイルを Amazon S3 に保存して配信しています。

### IMR90 細胞の高深度 Hi-C とループ（id 1、21、41）

Rao SSP, Huntley MH, Durand NC *et al.* A 3D map of the human genome at kilobase resolution reveals principles of chromatin looping. *Cell* **159**, 1665–1680 (2014). [GEO GSE63525](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE63525)

- **Hi-C（id 1）** — IMR90 細胞の in situ Hi-C（7 ライブラリ）をまとめた `.hic` です。解像度は 5 kb〜500 kb、正規化は KR です。kb スケールの領域やループの詳細な確認に適しています。
- **ループ（id 21）** — GEO の `GSE63525_IMR90_HiCCUPS_looplist.txt.gz`（HiCCUPS で検出された 8,040 個のループ）の染色体名に `chr` を付けたものです。ループの強さには、観測コンタクト数（`o` カラム）を使います。同じファイルが `sample/IMR90_loops_Rao2014_HiCCUPS_hg19.bedpe` にあります。

### 分裂酵母の G2 期と分裂期（id 51、52）

Tanizawa H, Kim KD, Iwasaki O, Noma K. Architectural alterations of the fission yeast genome during the cell cycle. *Nat Struct Mol Biol* **24**, 965–976 (2017). [GEO GSE93198](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE93198)

*cdc25-22* 変異株を同調させ、同調解除から 20 分後（G2 期）と 50 分後（分裂期）に取得した Hi-C データです。

### 遺伝子アノテーション（id 31、61）

- **ヒト** — GENCODE v19（hg19）のタンパク質をコードする遺伝子。遺伝子ごとに代表的な転写産物を 1 つ選んでいます。
- **分裂酵母** — PomBase の遺伝子モデル（`sample/Schizosaccharomyces_pombe_all_chromosomes.gff3`）。

## ブックマーク

`sample/HiCarta_demo_bookmarks_hg19.xlsx` には、デモ用の 2 つの領域（chr5）と、老化に関わる 14 個の遺伝子（SASP 遺伝子）のブックマーク（hg19）を収録しています。**移動** パネルのブックマーク欄にある **Excel から読み込み（追加）** で読み込めます。

## データの利用について

デモデータを論文などで使う場合は、各データの原著論文を引用してください。HiCarta を使ったことについては、README に記載された引用方法を参照してください。

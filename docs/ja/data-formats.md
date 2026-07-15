# データ形式

HiCarta はいくつかの形式を読み込みます。コンタクトマップは `.hic` から取得し、それ以外はすべて1次元トラックです。

## コンタクトマップ: `.hic`（Juicer）

主要な形式です。HiCarta は `strawr` で領域を直接読み込みます（ランダムアクセス、マルチ解像度）。メニュー（`menu_url`）から、または Data パネルの**ローカル `.hic` ファイル**として読み込みます。

- 染色体名は `.hic` 内部の名前と一致している必要があります（例: *S. pombe* では `I / II / III`）。
- メニューの各 `.hic` は単一解像度の場合があります。HiCarta は要求された解像度／正規化を、ファイルが持つものに合わせて調整します。

## トラック

| 形式 | パネルの種類 | 備考 |
|---|---|---|
| **bigWig** | bigWig | 定量シグナル。塗りつぶし面として描画 |
| **BED** | BED | 区間。ボックスとして描画 |
| **GFF3** | gene（GFF3） | 遺伝子モデル。一度解析して `<gff3>.genes.rds` としてキャッシュ |
| **`*_BS.txt`** | Border Strength | TAD 境界の強度。下記参照 |

### Border Strength（`*_BS.txt`）

[BorderStrength](https://github.com/rafysta/BorderStrength) が出力します。列: `chr, start, end, BS, BS.norm, boundary, TADid, TAD`（200 bp ビン）。HiCarta は `BS.norm` を面として描画し（正は赤、負は青、基準線 0）、`boundary != 0` の位置に破線を引きます。

---

## hic200‑cpp の生マップ（`.txt.gz`）→ `.hic`

hic200‑cpp の出力は gzip 圧縮されたテキスト行列です（`bin1 bin2 score`、上三角、200 bp のグローバルビンインデックス）。この巨大なテキストを直接読むのではなく、**一度だけ**圧縮・インデックス付き・マルチ解像度の `.hic` に変換し、ローカル `.hic` として読み込みます。`.hic` のサイズは `.txt.gz` とほぼ同程度ですが、はるかに高速です。

### 必要なもの

- Java（Juicer Tools の実行用）
- `juicer_tools.jar` — <https://github.com/aidenlab/juicer/wiki/Download>
- 対応する**ビン定義**ファイル（例: `sample/bin_def_200bp.txt`）。各グローバルビンインデックスを `(染色体, start)` に対応付けます

### 変換の概要

リポジトリには、変換全体を自動化するラッパースクリプトが同梱されています。

```bash
JUICER=/path/to/juicer_tools.jar \
  bash scripts/convert_hic200_to_hic.sh sample/bin_def_200bp.txt file1.txt.gz [file2.txt.gz ...]
```

各入力の隣に `file1.hic` を生成します。出力は環境変数で調整できます: `RES`（解像度）、`JMEM`（Java ヒープ）、`JUICER`（jar のパス）。

内部では、(1) ビン定義から `chrom.sizes` を導出し、(2) 各 200 bp ビンインデックスをその**中点**に対応付け、(3) Juicer の「short with score」レコード（`<str1> <chr1> <pos1> <frag1> <str2> <chr2> <pos2> <frag2> <score>`）を書き出し、(4) `juicer_tools pre -n`（正規化なし）を実行してマルチ解像度の `.hic` を構築します。

変換後、**Data → ローカル `.hic` ファイル**から `output.hic` を開きます。[scripts/README.md](https://github.com/rafysta/HiCarta/blob/main/scripts/README.md) も参照してください。

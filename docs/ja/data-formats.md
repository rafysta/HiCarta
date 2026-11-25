# データ形式

HiCarta は複数のゲノムデータ形式に対応しています。コンタクトマップには `.hic` を使用し、シグナル、ゲノム区間、遺伝子、ループなどはトラックとして表示できます。

## コンタクトマップ: `.hic`（Juicer）

HiCarta のコンタクトマップ用の形式です。ランダムアクセスと複数解像度に対応し、指定領域のデータを直接読み込みます。リモートファイルには HTTP レンジリクエストを利用します。`.hic` は **[データカタログ](data-catalog.md)** またはファイル指定から開けます。

- 染色体名は `.hic` 内部の名前と一致している必要があります（例：*S. pombe* では `I / II / III`）。
- `.hic` は単一解像度の場合があります。HiCarta は指定された解像度や正規化方法を、ファイル内で利用可能なものに合わせて調整します。同じサンプルの単一解像度ファイルを 1 つのカタログ行にまとめると、仮想マルチ解像度データセットとしてまとめて開けます。

## トラック

| 形式 | パネルの種類 | 備考 |
|---|---|---|
| **bigWig** | bigWig | 定量シグナル。塗りつぶしたグラフとして描画 |
| **BED** | BED | ゲノム区間。矩形として描画 |
| **GFF3** | gene（GFF3） | 遺伝子モデル。初回の読み込み時に解析し、 `<gff3>.genes.rds` としてキャッシュ |
| **`*_BS.txt`** | Border Strength | TAD 境界の強度。下記を参照 |

### Border Strength（`*_BS.txt`）

[BorderStrength](https://github.com/rafysta/BorderStrength) の出力形式です。カラムは次のとおりです： `chr, start, end, BS, BS.norm, boundary, TADid, TAD`（200 bp ビン）。HiCarta は `BS.norm` を塗りつぶしたグラフとして描画し（正の値は赤、負の値は青、基準線は 0）、`boundary != 0` の位置に破線を引きます。

列名のヘッダー行があることを想定していますが、ヘッダーのないファイルはカラムの順序（`chr, start, end, BS, BS.norm, …`）で読み込みます。ビンサイズは 200 bp に限らず、40 kb などでも構いません。

---

## hic200‑cpp の生マップ（`.txt.gz`）→ `.hic`

hic200‑cpp の出力は gzip 圧縮されたテキスト行列です（`bin1 bin2 score`、上三角、200 bp のグローバルビンインデックス）。この大容量のテキストファイルを直接読み込むのではなく、**一度だけ**圧縮・インデックス化されたマルチ解像度の `.hic` に変換し、ローカル `.hic` として読み込みます。`.hic` のサイズは `.txt.gz` とほぼ同程度ですが、より高速に読み込めます。

### 必要なもの

- Java（Juicer Tools の実行用）
- `juicer_tools.jar` — <https://github.com/aidenlab/juicer/wiki/Download>
- 対応する**ビン定義**ファイル（例：`sample/bin_def_200bp.txt`）。各グローバルビンインデックスを `(染色体, start)` に対応付けます

### 変換の概要

リポジトリには、変換全体を自動化するラッパースクリプトが同梱されています。

```bash
JUICER=/path/to/juicer_tools.jar \
  bash scripts/convert_hic200_to_hic.sh sample/bin_def_200bp.txt file1.txt.gz [file2.txt.gz ...]
```

各入力ファイルと同じフォルダに `file1.hic` を生成します。変換条件は次の環境変数で指定できます： `RES`（解像度）、`JMEM`（Java ヒープ）、`JUICER`（jar のパス）。

内部では、(1) ビン定義から `chrom.sizes` を導出し、(2) 各 200 bp ビンインデックスをその**中点**に対応付け、(3) Juicer の「short with score」レコード（`<str1> <chr1> <pos1> <frag1> <str2> <chr2> <pos2> <frag2> <score>`）を書き出し、(4) `juicer_tools pre -n`（正規化なし）を実行してマルチ解像度の `.hic` を構築します。

変換後、生成された `.hic` ファイルをデータカタログに登録し、**データブラウザ** から開きます。[scripts/README.md](https://github.com/rafysta/HiCarta/blob/main/scripts/README.md) も参照してください。

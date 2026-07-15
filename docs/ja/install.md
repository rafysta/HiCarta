# インストール

HiCarta はローカルの Shiny アプリとして、あなたのマシン上で動作します。サーバーやアカウントは不要です。

## 1. R をインストールする

<https://cran.r-project.org> から R（4.1 以上）をインストールします。

- **Windows** — インストーラーが R を `C:\Program Files\R\R-x.y.z` に配置します。ランチャーが自動的に見つけます。
- **macOS** — CRAN の `.pkg`、または `brew install --cask r`。

RStudio は**不要**ですが、あっても問題ありません。

## 2. HiCarta を入手する

```
git clone https://github.com/rafysta/HiCarta.git
```

または GitHub から ZIP をダウンロードして展開します。

## 3. 初回起動（R パッケージのインストール）

- **Windows** — `run_windows.bat` をダブルクリック
- **macOS** — `run_mac.command` をダブルクリック

初回起動時、ランチャーは必要なパッケージを確認し、不足があれば `R/install_libraries.R` を実行します。必要なパッケージ:

| パッケージ | 入手元 | 用途 |
|---|---|---|
| shiny, leaflet, htmlwidgets, base64enc | CRAN | アプリ + タイルマップ |
| data.table | CRAN | 高速なテキスト読み込み |
| RColorBrewer | CRAN | カラーパレット |
| strawr | CRAN | `.hic` へのランダムアクセス |
| rtracklayer | Bioconductor | bigWig / BED トラック |

> `rtracklayer` は Bioconductor 由来で、初回のインストールに数分かかることがあります。これは正常です。

すべて手動でインストールする場合:

```r
source("R/install_libraries.R")
```

## 4. 実行する

アプリはブラウザのタブを `http://127.0.0.1:7788` で開きます。停止するには、ランチャーのウィンドウを閉じる（Windows）か、`Ctrl+C` を押す／ターミナルのウィンドウを閉じます（macOS）。ポート 7788 が使用中の場合、ランチャーが以前のインスタンスを自動的に終了します。

---

## トラブルシューティング

**「Could not find Rscript」** — R がインストールされていない、または `PATH` に無い状態です。R をインストールしてから起動し直してください。Windows ではランチャーが `C:\Program Files\R\` も検索します。

**`rtracklayer` のインストールに失敗する** — 初回起動時にインターネット接続があることを確認してください。直接インストールすることもできます:

```r
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
BiocManager::install("rtracklayer")
```

**何も表示されない／マップが真っ白** — **Data** パネルでデータセットが読み込まれ、**Region** で領域が設定されていることを確認し、**Open map** をクリックしてください。

**リモート `.hic` の初回オープンが遅い** — ファイルは一度だけ `_hic_cache/` にダウンロードされます。次回以降はそのキャッシュから読み込むため高速です。ディスク容量を空けたい場合は `_hic_cache/` を削除してください（必要に応じて再ダウンロードされます）。

**macOS で「開発元を検証できないため開けません」** — `run_mac.command` を右クリック →「開く」を選ぶか、一度 `chmod +x run_mac.command` を実行してください。

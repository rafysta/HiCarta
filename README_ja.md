# HiCarta（旧 HiD contact viewer）

> English: see [README.md](README.md)。詳細ガイド（オンライン）: <https://rafysta.github.io/HiCarta/>

R + Shiny + Leaflet で実装した、対話的な Hi-C contact map ビューアです。地図アプリのようにドラッグで移動・スクロールでズームでき、高解像度・大きなゲノムにも対応します。旧 Java 版(テキスト全読み込みで破綻)の作り直しで、`.hic` を中心に複数形式を扱えます。

## 動作の考え方（タイル方式）

染色体を丸ごと読むのではなく、地図タイルと同じ方式で表示します。Leaflet の `GridLayer` が**見えているタイルだけ**を要求し、遠いタイルは自動で破棄します。各タイル（256px）は、現在のズームに合った `.hic` 解像度でその 2 次元ブロックだけを strawr で読み、R が PNG にして配信します（`session$registerDataObj` によるオンデマンド配信）。ズームに応じて解像度が自動で切り替わります（LOD）。座標系は**左上が原点**（y は下方向に増加）。

色は継ぎ目が出ないよう、全タイル共通の**絶対値スケール（Value の Max）**を使います。初期値は Open 時に粗い解像度で全体を一度読み、その分布から決めます。Display の Max を変えると全タイルが再描画されます。

速度対策として、リモート `.hic` は Open 時に一度 `_hic_cache/` へダウンロードし、以降はローカルから読みます（初回のみ待ち、2 回目以降は高速）。容量が気になる場合は `_hic_cache/` を削除すれば再取得します。

## ファイル構成

```
app.R                  本体（Shiny UI + Leaflet + タイル配信）
R/readers.R            .hic / .rds / .matrix.gz を領域行列に（strawr ほか）＋ローカルキャッシュ
R/tiles.R              タイル描画（(z,x,y)→領域→PNG）
R/draw.R               カラー化（パレット・値スケール）と PNG ラスタ生成
R/juicer_menu.R        juicer メニュー（ID = 親, ラベル[, URL]）のパーサ
R/tracks.R             bigWig / BED トラック（rtracklayer）
R/genes.R              遺伝子トラック（GFF3）
R/borderstrength.R     Border Strength トラック（*_BS.txt）
R/install_libraries.R  必要パッケージのインストール
config.txt             起動時の既定値
run_windows.bat / run_mac.command  ランチャー
scripts/               ユーティリティ（hic200→.hic 変換など）
docs/                  ドキュメント原稿（GitHub Pages / MkDocs で公開）
mkdocs.yml             ドキュメントサイト設定
.github/workflows/     サイトの自動ビルド・公開
sample/                動作確認用データ
```

## 設定ファイル（config.txt）

`config.example.txt` を **`config.txt`** にコピーし（app.R と同じフォルダ）、自分の URL を記入して再起動します。`config.txt` は **git 管理外**なので、データURLがコミットされることはありません。`config.txt` が無くてもアプリは動作します（入力欄が空で始まるだけで、URL を貼るかローカル `.hic` を指定すれば使えます）。

```
menu_url        = <Juicer メニューの URL かローカルパス>   # Data パネルの .hic メニュー既定
track_list_url  = <IGV XML か索引ファイルの URL>          # Tracks パネルの既定
```

公開の *S. pombe* テスト用メニューは [sample/README.md](sample/README.md) に記載。

`track_list_url` は、単一の IGV XML でも、複数の IGV XML の URL を1行ずつ並べた索引ファイルでも構いません。索引の場合、Tracks で「XML file」→「Category」→「Track」の順に選べます。

## 使い方

1. R をインストール（https://cran.r-project.org ）。
2. `run_windows.bat`（Windows）または `run_mac.command`（macOS）を実行。初回のみ必要パッケージを自動導入します（bigWig 用の rtracklayer は数分）。
3. 上部メニュー（Data / Region / Display / Tracks / Setting / About）で設定を切替。
4. **Data**: メニューを Load → Sample / Dataset を選ぶ、または「local .hic file」にローカル `.hic` のパスを入れる。
5. **Region**: 染色体と Y 軸範囲を指定（Go to region で移動、別染色体は自動で開き直し）。
6. **Open map**: 読み込み・表示。ドラッグで移動、スクロールでズーム、中クリックのドラッグで矩形ズーム。上部に座標・現在解像度、端にルーラーを表示します。

## トラック

Tracks パネルで各種 1D トラックを contact map の下に追加できます（マップの横方向のパン/ズームに連動、複数可、色・高さ調整可、カーソルの縦線がトラックまで貫通）。

- **bigWig / BED**: bigWig は塗りつぶしエリア、BED は区間ボックス。表示範囲だけを rtracklayer で読み込み（rtracklayer は Bioconductor、初回自動導入）。
- **gene (GFF3)**: 遺伝子を位置・向き（矢印）・名前で表示。+鎖=上段／−鎖=下段。ズームインで exon（CDS 太・UTR 細）。名前は重ならないよう解像度に応じて間引き。初回に `<gff3>.genes.rds` をキャッシュ。
- **Border Strength**: BorderStrength（github.com/rafysta/BorderStrength）の `*_BS.txt` の BS.norm を面グラフ（正=赤・負=青、基準線0）で描き、boundary に点線。

## hic200-cpp の生マップ → .hic に変換

hic200-cpp の `.txt.gz` は、あらかじめ **`.hic` に変換**してから「local .hic file」で読み込みます（`.hic` は圧縮＋インデックス＋多解像度で軽い）。付属の `scripts/convert_hic200_to_hic.sh` で変換できます（Java と juicer_tools.jar、`sample/bin_def_200bp.txt` などの bin 定義が必要）。詳細は [docs/data-formats.md](docs/data-formats.md) を参照。

## 備考

現状は cis（同一染色体内）を対象にした実装です。染色体名は `.hic` と同じ `I/II/III` を想定し、トラック側の `chrII` 等は自動吸収を試みます。作者: Hideki Tanizawa (rafysta@gmail.com)。

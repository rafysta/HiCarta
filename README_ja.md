# HiCarta（旧 HiD contact viewer）

> English: see [README.md](README.md)。詳細ガイド（オンライン）: <https://rafysta.github.io/HiCarta/>

R + Shiny + Leaflet で実装した、対話的な Hi-C contact map ビューアです。地図アプリのようにドラッグで移動・スクロールでズームでき、高解像度・大きなゲノムにも対応します。旧 Java 版(テキスト全読み込みで破綻)の作り直しで、`.hic` を中心に複数形式を扱えます。データは **Excel のデータカタログ**（1 行 = 1 サンプル）で管理し、アプリ内では絞り込み・検索のできるサンプルブラウザとして表示されます。

## 動作の考え方（タイル方式）

染色体を丸ごと読むのではなく、地図タイルと同じ方式で表示します。Leaflet の `GridLayer` が**見えているタイルだけ**を要求し、遠いタイルは自動で破棄します。各タイル（256px）は、現在のズームに合った `.hic` 解像度でその 2 次元ブロックだけを読み、R が PNG にして配信します（`session$registerDataObj` によるオンデマンド配信）。ズームに応じて解像度が自動で切り替わります（LOD）。座標系は**左上が原点**（y は下方向に増加）。

色は継ぎ目が出ないよう、全タイル共通の**絶対値スケール（Value の Max）**を使います。初期値は Open 時に粗い解像度で全体を一度読み、その分布から決めます。Display の Max を変えると全タイルが再描画されます。

リモートの `.hic` や bigWig は、既定では **HTTP レンジリクエストでストリーミング**され、見えている部分のバイトだけを取得します。`config.txt` で `hic_engine = download` にすると、ファイル全体を一度 `_hic_cache/` にダウンロードしてから読みます。

## ファイル構成

```
app.R                  本体（Shiny UI + Leaflet + タイル配信）
HiCarta_catalog_template.xlsx  データカタログのテンプレート
R/catalog.R            Excel データカタログ（.xlsx）：読み込み・検証・フィルタ
R/bookmarks.R          ブックマークの .xlsx 入出力
R/hic_reader.R         純 R の .hic リーダー（HTTP レンジストリーミング）
R/bigwig_reader.R      純 R の bigWig リーダー（HTTP レンジストリーミング）
R/readers.R            エンジン選択＋領域行列＋キャッシュ
R/tiles.R              タイル描画（(z,x,y)→領域→PNG）
R/draw.R               カラー化（パレット・値スケール）と PNG ラスタ生成
R/tracks.R             トラック描画。旧 IGV XML パーサ
R/genes.R              遺伝子トラック（GFF3）
R/borderstrength.R     Border Strength トラック（*_BS.txt）
R/chrominfo.R          トラックファイルから染色体名・長さを取得（マップなし表示用）
R/juicer_menu.R        旧 Juicer メニューのパーサ（変換スクリプト用）
R/i18n.R               画面の文言（英語・日本語）
R/install_libraries.R  必要パッケージのインストール
config.txt             起動時の既定値
run_windows.bat / run_mac.command  ランチャー
scripts/               変換スクリプト（カタログ⇔旧形式、hic200→.hic など）
docs/                  ドキュメント原稿（GitHub Pages / MkDocs で公開）
mkdocs.yml             ドキュメントサイト設定
.github/workflows/     サイトの自動ビルド・公開
sample/                動作確認用データ
```

## 設定ファイル（config.txt）

`config.example.txt` を **`config.txt`** にコピーし（app.R と同じフォルダ）、自分の値を記入して再起動します。`config.txt` は **git 管理外**なので、データURLがコミットされることはありません。`config.txt` が無くてもアプリは動作します（Data browser でカタログを手で読み込むだけです）。以下はすべてアプリ内の **設定 → 設定ファイルを編集…** からも変更できます。

```
catalog_url = <データカタログ .xlsx の URL かローカルパス>  # Data browser の既定カタログ
language    = ja      # 画面の言語（en=英語[既定] / ja=日本語）
hic_engine  = native  # リモートファイル: native=ストリーミング / download=全体を先に取得
igv_genome  =         # 「IGV で開く」で送るゲノム ID（例: hg38。空欄なら送らない）
```

`language` は起動時に一度だけ読まれます。既定は英語（`en`）で、`config.txt` に `language = ja` を書くとインターフェース全体が日本語になります。言語の追加は `R/i18n.R` に定義を足すだけです。

旧形式（Juicer 形式メニュー、IGV トラックリスト XML）は `scripts/` のスクリプトでカタログと相互変換できます（[scripts/README.md](scripts/README.md) 参照）。

## 使い方

1. R をインストール（https://cran.r-project.org ）。
2. `run_windows.bat`（Windows）または `run_mac.command`（macOS）を実行。初回のみ必要パッケージを自動導入します（bigWig 用の rtracklayer は数分）。
3. 上部メニュー（データ / 移動 / 表示 / 印刷 / 設定 / 情報）で操作パネルを切替。
4. **データ**: カタログ（`.xlsx`。テンプレートは `HiCarta_catalog_template.xlsx`）を読み込み、サンプルの行をクリック → 「コンタクトマップとして開く」。
5. **移動**: 染色体と範囲の指定・方向パッドでの移動・ブックマーク。
6. マップ上ではドラッグで移動、スクロールでズーム、中クリックのドラッグで矩形ズーム。上部に座標・現在解像度、端にルーラーを表示します。

## トラック

カタログのトラック行（bigWig / BED / GFF3 / `*_BS.txt`）から「トラックとして追加」で、各種 1D トラックを contact map の下に追加できます（マップの横方向のパン/ズームに連動、複数可、色・高さ調整可、カーソルの縦線がトラックまで貫通）。並び替えや設定変更は「表示 → トラック」のチップから行います。

Hi-C マップを開かずに**トラックだけ**表示することもできます。その場合は最初に追加したトラックのファイルから染色体名・長さを読み取り（bigWig はヘッダ、BED / GFF3 / `*_BS.txt` はデータ中の最大座標）、最初の染色体の全長を表示します。移動は「移動」パネル（染色体選択・領域指定・左右パン・拡大/縮小ボタン）や、トラック上部の座標ルーラーの範囲ドラッグで行います。

- **bigWig / BED**: bigWig は塗りつぶしエリア、BED は区間ボックス。表示範囲だけを rtracklayer で読み込み（rtracklayer は Bioconductor、初回自動導入）。
- **gene (GFF3)**: 遺伝子を位置・向き（矢印）・名前で表示。+鎖=上段／−鎖=下段。ズームインで exon（CDS 太・UTR 細）。名前は重ならないよう解像度に応じて間引き。初回に `<gff3>.genes.rds` をキャッシュ。
- **Border Strength**: BorderStrength（github.com/rafysta/BorderStrength）の `*_BS.txt` の BS.norm を面グラフ（正=赤・負=青、基準線0）で描き、boundary に点線。

## hic200-cpp の生マップ → .hic に変換

hic200-cpp の `.txt.gz` は、あらかじめ **`.hic` に変換**してからカタログの行として読み込みます（`.hic` は圧縮＋インデックス＋多解像度で軽い）。付属の `scripts/convert_hic200_to_hic.sh` で変換できます（Java と juicer_tools.jar、`sample/bin_def_200bp.txt` などの bin 定義が必要）。詳細は [docs/data-formats.md](docs/data-formats.md) を参照。

## 備考

現状は cis（同一染色体内）を対象にした実装です。染色体名は `.hic` と同じ `I/II/III` を想定し、トラック側の `chrII` 等は自動吸収を試みます。作者: Hideki Tanizawa (rafysta@gmail.com)。

# プラグイン：R で作成する独自のトラック

**プラグイン** は、HiCarta に新しい種類のトラックを追加するための R スクリプトです。基本的には、表示領域のデータを読み込む `read()` と、そのデータを描画する `draw()` を記述します。データカタログからの読み込み、トラックの追加・設定、セッションの保存・復元、印刷プレビューや図の出力は HiCarta が処理します。トラックの X 軸はコンタクトマップの表示範囲に合わせられます。

用途としては、独自に計算したスコア（insulation score、固有ベクトル、ビンごとの任意の値）、R で作成した図、`.hic` から算出したデータの可視化などが挙げられます。同梱の **Virtual 4C** プラグインは、その一例です。

!!! note "プラグインの置き場所"
    `app.R` と同じ階層にある **`plugins/`** フォルダにある `*.R` ファイルは、HiCarta の起動時と、ページを再読み込みするたびに読み込まれます。プラグインを編集したら、ブラウザのタブを再読み込みするだけです。別のフォルダを使うには `config.txt` の `plugin_dir`（**設定 → 設定ファイルを編集…**）で指定します。**情報** パネルに読み込まれたプラグインの一覧が表示されます。読み込めなかったファイルは、その理由も表示されます。

## クイックスタート

`plugins/` フォルダには、次の 2 つのプラグインが同梱されています。

| id（`file_type`） | ファイル | 描くもの |
|---|---|---|
| `table` | `table_signal.R` | **chr / start / end / value** の表（CSV、TSV、bedGraph）。負の値は基準線（0）より下に描画 |
| `v4c` | `virtual4c.R` | **Virtual 4C** プロファイル: 表示中の各ビンとアンカー位置とのコンタクトの強さ。表示範囲に応じた解像度で `.hic` から読み込む |

カタログから使うには、**`file_type`** 列にプラグインの id、`path` にファイルのパスまたは URL を記載し、行を開いて **トラックとして追加** を押します。

| id | name | path | file_type | set_anchor |
|---|---|---|---|---|
| 11 | insulation (Growing) | `s3://bucket/P/insulation_G.csv` | `table` | |
| 12 | IL6 promoter contacts | `s3://bucket/P/IMR90_G.hic` | `v4c` | `22766000` |

**`set_<パラメータ名>`** という列でプラグインのパラメータ（この例ではアンカー座標）を指定できます。プラグインが拡張子を宣言していれば（`table` は `.csv` と `.tsv`）、`file_type` は空欄でも構いません。

カタログを使わない場合は **データ → ファイル指定** で「種類」にプラグインを選んで追加します。パラメータはトラックの設定（**トラック**パネルで名前をクリック）で設定します。

## プラグインの書き方

プラグインファイルは `hicarta_plugin()` を 1 回呼びます。

```r
hicarta_plugin(
  id       = "csv",                       # カタログの file_type（小文字）
  label    = "CSV signal",                # メニューとトラックに表示される名前
  defaults = list(column = "value"),      # パラメータと既定値

  # chr 上の [start, end]（表示範囲のうち染色体の内側）のデータを返す
  read = function(path, chr, start, end, p) {
    d <- read.csv(path)
    d[d$chr == chr & d$end >= start & d$start <= end, ]
  },

  # 描く。表示範囲は [vstart, vend]（染色体の端を越えることがある）
  draw = function(d, chr, vstart, vend, style) {
    hc_canvas(vstart, vend, ylim = c(0, max(d[[style$params$column]], 1)))
    rect(d$start, 0, d$end, d[[style$params$column]], col = style$color, border = NA)
    hc_label(style$name)
  })
```

### `hicarta_plugin()` の引数

| 引数 | 意味 |
|---|---|
| `id` | トラック種別の識別子。英小文字で始まる 1〜32 文字の英小文字・数字・`_`。カタログの `file_type` に書く値。組み込みの種別（`hic`, `bigwig`, `bed`, `gff3`, `bs`, `arc`）は使えない |
| `label` | 画面に表示する名称（メニュー、トラックのチップ、設定ダイアログ） |
| `draw` | **必須。** `function(d, chr, vstart, vend, style)`（後述） |
| `read` | `function(path, chr, start, end, p)`。`draw` が受け取るものなら何を返してもよい。データの読み込みが不要な場合は `NULL` |
| `defaults` | パラメータと既定値の名前付きリスト。**既定値の型**が重要で、カタログやダイアログに入力された値はその型（数値、TRUE/FALSE、文字列）に変換される |
| `accepts` | 読むファイルの種類: `"hic"`, `"bigwig"`, `"bed"`, `"gff3"`, `"bs"`, `"arc"`, または `"any"`（既定）。コンタクトマップを開く前にトラックを追加したとき、染色体長の取得に使用 |
| `extensions` | プラグインが対応する拡張子（例 `c("csv", "tsv")`）。これらは `file_type` を空欄にできる |
| `chroms` | 省略可。`function(path)` で染色体長の名前付き数値ベクトルを返す（トラックのみのモード用） |
| `height`, `color` | 追加直後のトラックの既定値（px、R の色） |
| `description` | 設定ダイアログに出る 1 行の説明 |

### `read()` 関数

`read(path, chr, start, end, p)` は、表示範囲のうち染色体の内側の部分と、統合済みのパラメータ `p`（既定値に、カタログの `set_` 列／ダイアログ／セッションの値を上書きしたもの）で呼ばれます。結果は領域とパラメータの組ごとにキャッシュされるので、表示範囲またはパラメータの変更時に、必要に応じて再実行されます。戻り値はデータフレームでも行列でもリストでも構いません。

### `draw()` 関数

`draw(d, chr, vstart, vend, style)` は `read()` の結果 `d`（または `NULL`）を受け取り、R の base graphics を用いて現在のパネルに描画します。コンタクトマップとの座標を一致させるため、**X 軸の範囲を正確に `[vstart, vend]` に設定してください。** `hc_canvas()` を利用すると、この設定を行えます。`par(mar=)` は変更しないでください。

`style` はリストです。

| 要素 | 意味 |
|---|---|
| `name`, `color`, `height` | ユーザーが設定したトラックの名前・色・高さ |
| `params` | 統合済みパラメータ（`read()` の `p` と同じ） |
| `ymin`, `ymax` | 設定ダイアログの Min / Max。自動なら `NA` |
| `print` | 印刷プレビュー／エクスポートの描画なら `TRUE`（左側に目盛付きの軸を描画することを推奨） |
| `chrlen`, `dstart`, `dend` | 染色体長と、染色体内に切り詰めたデータ範囲 |
| `path`, `id` | ファイルとプラグイン id |

### ヘルパー関数

描画:

| 関数 | 働き |
|---|---|
| `hc_canvas(vstart, vend, ylim = c(0, 1), headroom = 0.05)` | 指定した X 軸の範囲で描画領域を設定（`ylim` の上に 5 % の余白、`ylim[1] < 0` ならゼロの下にも余白） |
| `hc_label(name)` | 組み込みトラックと同じ位置（左上）にトラック名 |
| `hc_guide(y)` | 右端に数値付きの細いガイド線（組み込みトラックの「インライン」スケール） |
| `hc_yaxis()` | 印刷／出力用の左側の座標軸 |
| `hc_message(text)` | パネル内にメッセージ（「表示範囲にデータなし」、エラーなど） |

読み込み（HiCarta 自身のストリーミングリーダー経由。ローカルファイル・http(s) URL・非公開の `s3://` のどれでも動き、ファイル全体はダウンロードしない）:

| 関数 | 戻り値 |
|---|---|
| `hc_hic_region(path, chr, start, end, resolution, norm, chr2, start2, end2)` | `chr` の `[start,end]`（行）× `chr2` の `[start2,end2]`（列）のコンタクト行列。`chr2` の既定は `chr`、第 2 範囲の既定は第 1 範囲 |
| `hc_bin_starts(m, 1)` / `hc_bin_starts(m, 2)` | その行列の行／列のビン開始座標（bp） |
| `hc_hic_pick_resolution(path, chr, start, end, target_bins = 500, norm)` | 表示幅が `target_bins` ビン程度になる、ファイル中の解像度 |
| `hc_hic_chroms(path)`, `hc_hic_resolutions(path)`, `hc_hic_norms(path)` | `.hic` が持つ染色体・解像度・正規化 |
| `hc_bigwig_bins(path, chr, start, end, nbins, type = "mean")` | bigWig をビンごとの値に（`type` は `"mean"` か `"max"`） |
| `hc_bigwig_intervals(path, chr, start, end)` | bigWig に記録された区間 `data.frame(start, end, value)` |

読み込みやデータ処理には、R の関数や独自の R パッケージも利用できます。描画は base graphics（`rect()`、`lines()`、`polygon()` など）で行ってください。`ggplot2` などの grid 系の図をプラグインで使えるようにする機能は、今後の対応を予定しています。`read()` はキャッシュにない領域に移動するたびに走るので、処理時間が長くなりすぎないように実装してください。

## パラメータ: カタログ・ダイアログ・セッション

- **カタログ**: パラメータごとに `set_<名前>` 列（`set_anchor`、`set_norm` …）。空欄 = 既定値。標準の `set_color` / `set_height` も使えます。
- **設定ダイアログ**: パラメータごとに 1 つのテキスト欄。空欄 = 既定値。
- **セッションファイル**: パラメータはトラックと一緒に保存・復元されます。
- ダイアログの **Min / Max** は `style$ymin` / `style$ymax` として渡されます。反映するかどうかはプラグイン次第です（同梱の 2 つは反映します）。

## トラブルシューティング

- 読み込めなかったプラグインは起動時と **情報** パネルでエラー内容が表示されます。他のプラグインは通常どおり読み込まれます。
- 描画中のエラーは**そのトラックのパネル内**（と R のコンソール）に表示され、アプリの他の部分には影響しません。
- トラックが表示されない場合： `read()` がコンタクトマップと同じ染色体名（`chr1` と `1` の違い）で絞っているか、ファイルの座標が bp 単位かを確認してください。
- 編集内容が反映されない場合： ブラウザのページを再読み込みしてください。

!!! warning "プラグインはプログラムです"
    プラグインはR のプログラムで、HiCarta 自身と同じ権限で動きます。プラグインフォルダには信頼できるファイルだけを置いてください。

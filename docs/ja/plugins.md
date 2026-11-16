# プラグイン: R で書く独自トラック

**プラグイン**は、HiCarta に新しい種類のトラックを教える小さな R ファイルです。書くのは関数 2 つ ── 画面に表示中の領域のデータを読む関数と、それを描く関数 ── だけで、あとは HiCarta が引き受けます。データカタログ、「トラックとして追加」ボタン、トラックパネルと設定ダイアログ、セッションファイル、そして印刷プレビュー／エクスポート（上のコンタクトマップとまったく同じ x 範囲で描かれます）。

想定している用途: 自分で計算したスコア（insulation、eigenvector、ビンごとの任意の値）、研究室で R で描いている図、`.hic` 自体から導く表示 ── 同梱の **Virtual 4C** プラグインがその例です。

!!! note "プラグインの置き場所"
    `app.R` と同じ場所の **`plugins/`** フォルダにある `*.R` ファイルは、HiCarta の起動時と、ページを再読み込みするたびに読み込まれます。プラグインを編集したら、ブラウザのタブを再読み込みするだけです。別のフォルダを使うには `config.txt` の `plugin_dir`（**Setting → Edit config file…**）で指定します。**About** パネルに読み込まれたプラグインの一覧が出ます。読み込めなかったファイルは、その理由も表示されます。

## クイックスタート

HiCarta には `plugins/` にプラグインが 2 つ同梱されています。

| id（`file_type`） | ファイル | 描くもの |
|---|---|---|
| `table` | `table_signal.R` | **chr / start / end / value** の表（CSV、TSV、bedGraph）。負の値はゼロ線の下に描く |
| `v4c` | `virtual4c.R` | **virtual 4C** プロファイル: 表示中の各ビンがアンカー位置とどれだけ接触しているか。`.hic` から表示幅に合う解像度で読む |

カタログから使うには、**`file_type`** 列にプラグインの id、`path` にファイルを書き、行を開いて **トラックとして追加** を押します。

| id | name | path | file_type | set_anchor |
|---|---|---|---|---|
| 11 | insulation (Growing) | `s3://bucket/P/insulation_G.csv` | `table` | |
| 12 | IL6 promoter contacts | `s3://bucket/P/IMR90_G.hic` | `v4c` | `22766000` |

**`set_<パラメータ名>`** という列でプラグインのパラメータ（ここではアンカー）を渡せます。プラグインが拡張子を宣言していれば（`table` は `.csv` と `.tsv`）、`file_type` は空欄でも構いません。

カタログを使わない場合は **Data → ファイル指定** で「種類」にプラグインを選んで追加します。パラメータはトラックの設定（**トラック**パネルで名前をクリック）で設定します。

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
| `id` | トラック種別の名前。英小文字で始まる 1〜32 文字の英小文字・数字・`_`。カタログの `file_type` に書く値。組み込みの種別（`hic`, `bigwig`, `bed`, `gff3`, `bs`, `arc`）は使えない |
| `label` | 人が読む名前（メニュー、トラックのチップ、設定ダイアログ） |
| `draw` | **必須。** `function(d, chr, vstart, vend, style)`（後述） |
| `read` | `function(path, chr, start, end, p)`。`draw` が受け取るものなら何を返してもよい。データが要らなければ `NULL` |
| `defaults` | パラメータと既定値の名前付きリスト。**既定値の型**が重要で、カタログやダイアログに入力された値はその型（数値、TRUE/FALSE、文字列）に変換される |
| `accepts` | 読むファイルの種類: `"hic"`, `"bigwig"`, `"bed"`, `"gff3"`, `"bs"`, `"arc"`, または `"any"`（既定）。コンタクトマップを開く前にトラックを追加したとき、染色体の長さを得るのに使う |
| `extensions` | プラグインが引き受ける拡張子（例 `c("csv", "tsv")`）。これらは `file_type` を空欄にできる |
| `chroms` | 省略可。`function(path)` で染色体長の名前付き数値ベクトルを返す（トラックのみのモード用） |
| `height`, `color` | 追加直後のトラックの既定値（px、R の色） |
| `description` | 設定ダイアログに出る 1 行の説明 |

### `read()` 関数

`read(path, chr, start, end, p)` は、表示範囲のうち染色体の内側の部分と、統合済みのパラメータ `p`（既定値に、カタログの `set_` 列／ダイアログ／セッションの値を上書きしたもの）で呼ばれます。結果は領域とパラメータの組ごとにキャッシュされるので、表示範囲かパラメータが変わったときだけ呼び直されます。戻り値はデータフレームでも行列でもリストでも構いません。

### `draw()` 関数

`draw(d, chr, vstart, vend, style)` は `read()` の結果 `d`（または `NULL`）を受け取り、base graphics で現在のパネルに描きます。守るべきことは 1 つ ── **x 軸をちょうど `[vstart, vend]` にする**こと。これでマップと揃います。`hc_canvas()` がそれをやります。`par(mar=)` は変更しないでください。

`style` はリストです。

| 要素 | 意味 |
|---|---|
| `name`, `color`, `height` | ユーザーが設定したトラックの名前・色・高さ |
| `params` | 統合済みパラメータ（`read()` の `p` と同じ） |
| `ymin`, `ymax` | 設定ダイアログの Min / Max。自動なら `NA` |
| `print` | 印刷プレビュー／エクスポートの描画なら `TRUE`（左に本物の軸を描くとよい） |
| `chrlen`, `dstart`, `dend` | 染色体長と、染色体内に切り詰めたデータ範囲 |
| `path`, `id` | ファイルとプラグイン id |

### ヘルパー関数

描画:

| 関数 | 働き |
|---|---|
| `hc_canvas(vstart, vend, ylim = c(0, 1), headroom = 0.05)` | 正しい x 範囲でパネルを開く（`ylim` の上に 5 % の余白、`ylim[1] < 0` ならゼロの下にも余白） |
| `hc_label(name)` | 組み込みトラックと同じ位置（左上）にトラック名 |
| `hc_guide(y)` | 右端に値つきの細いガイド線（組み込みトラックの「インライン」スケール） |
| `hc_yaxis()` | 印刷／エクスポート用の左軸 |
| `hc_message(text)` | パネル内にメッセージ（「表示範囲にデータなし」、エラーなど） |

読み込み（HiCarta 自身のストリーミングリーダー経由。ローカルファイル・http(s) URL・非公開の `s3://` のどれでも動き、ファイル全体はダウンロードしない）:

| 関数 | 戻り値 |
|---|---|
| `hc_hic_region(path, chr, start, end, resolution, norm, chr2, start2, end2)` | `chr` の `[start,end]`（行）× `chr2` の `[start2,end2]`（列）のコンタクト行列。`chr2` の既定は `chr`、第 2 範囲の既定は第 1 範囲 |
| `hc_bin_starts(m, 1)` / `hc_bin_starts(m, 2)` | その行列の行／列のビン開始座標（bp） |
| `hc_hic_pick_resolution(path, chr, start, end, target_bins = 500, norm)` | 表示幅が `target_bins` ビン程度になる、ファイル中の解像度 |
| `hc_hic_chroms(path)`, `hc_hic_resolutions(path)`, `hc_hic_norms(path)` | `.hic` が持つ染色体・解像度・正規化 |
| `hc_bigwig_bins(path, chr, start, end, nbins, type = "mean")` | bigWig をビンごとの値に（`type` は `"mean"` か `"max"`） |
| `hc_bigwig_intervals(path, chr, start, end)` | bigWig の生の区間 `data.frame(start, end, value)` |

それ以外の R はすべて使えます。`ggplot2` も使えます（`draw()` の中で `print()`）し、自作パッケージも使えます。`read()` はキャッシュにない領域に移動するたびに走るので、無理のない速さに保ってください。

## パラメータ: カタログ・ダイアログ・セッション

- **カタログ**: パラメータごとに `set_<名前>` 列（`set_anchor`、`set_norm` …）。空欄 = 既定値。いつもの `set_color` / `set_height` も使えます。
- **設定ダイアログ**: パラメータごとに 1 つのテキスト欄。空欄 = 既定値。
- **セッションファイル**: パラメータはトラックと一緒に保存・復元されます。
- ダイアログの **Min / Max** は `style$ymin` / `style$ymax` として渡されます。反映するかどうかはプラグイン次第です（同梱の 2 つは反映します）。

## トラブルシューティング

- 読み込めなかったプラグインは起動時に 1 回と、**About** パネルでエラー内容つきで報告されます。他のプラグインは通常どおり読み込まれます。
- 描画中のエラーは**そのトラックのパネル内**（と R のコンソール）に表示され、アプリの他の部分には影響しません。
- トラックが空のとき: `read()` がコンタクトマップと同じ染色体名（`chr1` と `1` の違い）で絞っているか、ファイルの座標が bp 単位かを確認してください。
- 編集したのに変わらない: ブラウザのページを再読み込みしてください。

!!! warning "プラグインはプログラムです"
    プラグインは普通の R コードで、HiCarta 自身と同じ権限で動きます。プラグインフォルダには信頼できるファイルだけを置いてください。

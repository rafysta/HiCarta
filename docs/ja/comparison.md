# 他のツールとの比較

Hi-C データを表示するツールには、それぞれ異なる特徴があります。HiCarta は、研究室で保有するデータを手元の PC で手軽に閲覧・比較し、その結果を論文用の図として出力することを重視しています。公開データの閲覧や、大規模な共同研究用のデータポータルの構築には、ほかのツールの方が向いている場合もあります。

## 機能の比較

記号：✓ = 対応、△ = 一部対応・条件付き、– = 非対応

| | **HiCarta** | Juicebox | HiGlass | WashU | UCSC | JBrowse 2 | pyGenomeTracks | plotgardener |
|---|---|---|---|---|---|---|---|---|
| 種類 | デスクトップ（R、ブラウザで操作） | デスクトップ（Java）／Web | Web＋サーバー | Web | Web | Web／デスクトップ | コマンドライン | R パッケージ |
| 専用サーバーの構築が不要 | ✓ | ✓ | –（サーバーが必要） | △（ファイルを Web に公開） | △（ファイルを Web に公開） | ✓（Desktop 版） | ✓ | ✓ |
| `.hic` を直接読む | ✓ | ✓ | –（変換が必要） | ✓ | ✓ | ✓ | –（変換が必要） | ✓ |
| インタラクティブなズーム | ✓ | ✓ | ✓ | ✓ | △（ページを再描画） | ✓ | – | – |
| 1 次元のトラック（bigWig、BED、遺伝子） | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| ループの弧による表示 | ✓ | △（2 次元の枠） | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 2 つの Hi-C マップの比較 | ✓（分割・カーテン・差分） | ✓（Observed vs Control、比） | ✓（並列表示・同期） | △ | – | ✓（Compare with） | △（並列表示） | △（並列表示） |
| 独自の描画機能の追加 | ✓（R） | – | ✓（JavaScript） | – | – | ✓（JavaScript） | ✓（Python） | ✓（R のコード） |
| 論文用の編集可能な図 | ✓（PDF） | ✓（PDF／SVG） | ✓（SVG） | ✓（SVG） | ✓（PDF） | ✓（SVG） | ✓ | ✓ |
| Excel によるサンプル管理 | ✓ | – | – | – | – | – | – | – |
| 非公開データの共有機能 | ✓（S3 のタグに基づくアクセス制御） | – | △（サーバーの設定による） | △ | △ | △ | – | – |
| 公開データの充実 | – | △ | ✓ | ✓ | ✓ | △ | – | – |
| ゲノム間（シンテニー）の比較 | – | – | △ | △ | – | ✓ | – | – |

2026 年 11 月時点の各ツールのドキュメントに基づく比較です。誤りや更新があれば [GitHub Issues](https://github.com/rafysta/HiCarta/issues) でお知らせください。

## HiCarta が適している用途

- 研究室の Hi-C データを、専用サーバーを構築せずに自分の PC で見たい。
- 2 つの条件の Hi-C マップを、同じ領域で素早く見比べたい。
- 画面で見たものを、そのまま論文用の図にしたい。
- 独自の解析結果を、R で描いてマップと並べたい。
- 数百のサンプルを Excel で管理し、共同研究者と同じ一覧を使いたい。
- 未発表のデータを、アクセスを許可した共同研究者だけに共有したい。

## ほかのツールが適している用途

- **公開データを幅広く閲覧したい** — 3D Genome Browser、WashU Epigenome Browser、UCSC Genome Browser、HiGlass（higlass.io）には、多くの公開データが登録されています。
- **表示状態を URL で共有したい** — Juicebox Web や HiGlass は、表示している状態をそのまま URL で共有できます。
- **2 つのゲノムを並べて比較したい** — JBrowse 2 のリニアシンテニービューが使えます。
- **スクリプトで同じ形式の図を大量に作りたい** — pyGenomeTracks や plotgardener が向いています。

## 参考にした資料

- Juicebox：[Comparing Maps (Desktop)](https://aidenlab.gitbook.io/juicebox/comparing-maps)、[Juicebox Web](https://igvteam.github.io/juicebox-web)
- HiGlass：[チュートリアル](https://docs.higlass.io/tutorial.html)、[higlass-server](https://github.com/higlass/higlass-server)
- WashU Epigenome Browser：[使い方](https://epigenome.readthedocs.io/en/stable/usage.html)、[トラックの種類](https://epgg.github.io/datahub/track_properties)
- UCSC Genome Browser：[Hi-C トラック](https://genome.ucsc.edu/goldenPath/help/hic.html)
- JBrowse 2：[Hi-C トラック](https://jbrowse.org/jb2/docs/user_guides/hic_track/)、[機能一覧](https://jbrowse.org/features)
- pyGenomeTracks：[hic_matrix](https://pygenometracks.readthedocs.io/en/latest/content/tracks/hic_matrix.html)
- plotgardener：[論文](https://pmc.ncbi.nlm.nih.gov/articles/PMC8963281)

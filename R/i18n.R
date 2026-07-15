# ============================================================================
# i18n.R  -  lightweight interface localization for HiCarta
#
# The interface language is chosen ONCE at startup from config.txt
#   language = en   (default; English)
#   language = ja   (Japanese)
# so a plain lookup table is enough — no reactivity needed.
#
# Usage:
#   set_language(cfg_or("language", "en"))   # call before building the UI
#   tr("data_open")                          # -> localized string
#   sprintf(tr("about_version"), APP_VERSION)  # templates keep %s / %d
#
# To add a language, add a named list under LANG_STRINGS with the same keys.
# Missing keys fall back to English, so a partial translation is safe.
# ============================================================================

.i18n_env <- new.env(parent = emptyenv())
.i18n_env$lang <- "en"

set_language <- function(lang) {
  lang <- tryCatch(tolower(trimws(as.character(lang))), error = function(e) "en")
  if (length(lang) != 1 || is.na(lang) || !nzchar(lang) ||
      is.null(LANG_STRINGS[[lang]])) lang <- "en"
  .i18n_env$lang <- lang
  invisible(lang)
}

current_language <- function() .i18n_env$lang

# tr(key): return the string for the current language, falling back to English,
# and finally to the key itself if it is defined nowhere (so a typo is visible
# rather than crashing the UI).
tr <- function(key) {
  s <- LANG_STRINGS[[.i18n_env$lang]][[key]]
  if (is.null(s)) s <- LANG_STRINGS[["en"]][[key]]
  if (is.null(s)) key else s
}

LANG_STRINGS <- list(

  # -------------------------------------------------------------------------
  en = list(
    # nav pills
    nav_data = "Data", nav_region = "Region", nav_display = "Display",
    nav_tracks = "Tracks", nav_print = "Print", nav_setting = "Setting",
    nav_about = "About",

    # Data panel
    data_menu_file = "Juicer menu file",
    data_menu_url  = "…or menu URL",
    data_load_menu = "Load menu",
    data_sample    = "Sample",
    data_dataset   = "Dataset",
    data_norm      = "Normalization",
    data_local_hic = "or local .hic file",
    data_hic_path  = ".hic file path",
    data_open      = "Open map",

    # Region panel
    region_chr    = "Chromosome",
    region_ystart = "Y-axis start (bp)",
    region_yend   = "Y-axis end (bp)",
    region_goto   = "Go to region",

    # Display panel
    disp_palette   = "Palette",
    disp_open_first = "Open a map first.",
    disp_maxval    = "Max value",
    disp_linear    = "linear",
    disp_log       = "log10(value)",
    disp_value     = "value",
    disp_min_fixed = "Min fixed at 0.  data max = %s",

    # Tracks panel
    trk_xml_url    = "Track list / IGV XML URL",
    trk_load       = "Load",
    trk_xmlfile    = "XML file",
    trk_category   = "Category",
    trk_from_xml   = "Track from XML",
    trk_or_path    = "…or bigWig/BED file/URL",
    trk_type       = "Type",
    trk_type_gene  = "gene (GFF3)",
    trk_type_bs    = "Border Strength",
    trk_label      = "Label",
    trk_color      = "Color",
    trk_height     = "Height (px)",
    trk_add        = "Add track",
    trk_clear      = "Clear all",
    trk_none_added = "No tracks added.",

    # Print panel + modal
    print_title        = "Image export / Print",
    print_desc         = "Export a chosen region of the currently open map as an image or PDF.",
    print_open_preview = "Open print preview",
    print_help         = paste0("You can set the destination (printer / file), paper size, ",
                                "output region, and whether to include coordinate ticks, ",
                                "legend, and margins in the preview window."),
    print_need_map     = "Open a map first (Data → Open map).",
    print_preview      = "Print preview",
    print_dest         = "Destination",
    print_dest_printer = "Printer",
    print_dest_file    = "File",
    print_out_folder   = "Output folder",
    print_browse       = "Browse",
    print_filename     = "File name",
    print_format       = "Format",
    print_fmt_png      = "Image (PNG)",
    print_paper        = "Paper size",
    print_paper_a4p    = "A4 portrait",
    print_paper_a4l    = "A4 landscape",
    print_paper_sq     = "Square",
    print_paper_custom = "Custom",
    print_width        = "Width (mm)",
    print_height       = "Height (mm)",
    print_region       = "Output region",
    print_region_note  = "(Hi-C: X and Y use the same range)",
    print_chr          = "Chromosome",
    print_start        = "Start (bp)",
    print_end          = "End (bp)",
    print_ticks        = "Include coordinate ticks",
    print_legend       = "Include legend",
    print_nomargin     = "No margins",
    print_export_trk   = "Also export tracks",
    print_run          = "Run",
    print_close        = "Close",
    print_check_region = "Check the output region.",
    print_saved        = "Saved: %s",
    print_save_err     = "Save error: %s",
    print_print_err    = "Print error: %s",
    print_read_err     = "Read error: %s",

    # Setting panel
    set_map_height   = "Contact map height (px)",
    set_fit          = "Fit to window",
    set_trk_res      = "Track resolution (view divisions)",
    set_apply        = "Apply",
    set_auto         = "Auto adjust",
    set_no_trk_size  = "No tracks to size.",
    set_height       = "Height",
    set_max_auto     = "Max (0=auto)",

    # Config-file dialog
    cfg_open         = "Edit config file…",
    cfg_title        = "Configuration",
    cfg_intro        = paste0("View and edit the app's startup settings, saved to config.txt ",
                              "in the app folder. Clicking \"Apply & save\" reloads the page and ",
                              "applies the settings; any map or tracks currently loaded will be closed."),
    cfg_language     = "Interface language",
    cfg_menu_url     = "Default Juicer menu URL",
    cfg_tracklist    = "Default track list / IGV XML URL",
    cfg_raw          = "Current contents of config.txt",
    cfg_openfile     = "Open config.txt",
    cfg_apply        = "Apply & save",
    cfg_close        = "Close",
    cfg_saved        = "Saved to config.txt.",
    cfg_openfile_err = "Could not open config.txt: %s",

    # About panel
    about_former  = "formerly HiD contact viewer",
    about_version = "Version %s",
    about_author  = "Author: Hideki Tanizawa (",
    about_desc    = paste0("A viewer for Hi-C contact maps. Reads .hic (Juicer) via strawr and ",
                           "renders a draggable, zoomable, tile-based contact map (loads only the ",
                           "visible region at a resolution matched to the zoom)."),
    about_feat1   = "Juicer-style sample menu to switch datasets / resolutions / normalizations",
    about_feat2   = "Adjustable colour scale (global Max, linear & log sliders)",
    about_feat3   = "1-D tracks (bigWig / BED) synced to the map's horizontal range",
    about_feat4   = "Local caching of remote .hic and track files for speed",
    about_built   = paste0("Built with R, Shiny, Leaflet, strawr, rtracklayer. ",
                           "Successor to the Java HiD contact viewer; part of the rfy_hic2 workflow."),

    # main-panel readouts
    coord_view      = "View  x: %s:%s-%s   y: %s:%s-%s%s",
    coord_res       = "    resolution: %s",
    hover_outside   = "Cursor outside map",
    hover_line      = "Cursor  x %s:%s   y %s:%s   score %s   distance %s bp",

    # status / progress / notification messages
    msg_start        = "Load a menu, pick a dataset, Open map.",
    msg_choose_menu  = "Choose a menu file or URL.",
    msg_menu_err     = "Menu error: %s",
    msg_loaded_samp  = "Loaded %d samples.",
    msg_pick_src     = "Pick a dataset or enter a local .hic path.",
    msg_open_err     = "Open error: %s",
    msg_ready        = "Ready: %s (%s bp). Resolutions %s.",
    msg_enter_track  = "Enter a track file path or URL.",
    msg_added_track  = "Added track: %s (%s)",
    msg_cleared_trk  = "Cleared all tracks.",
    msg_gff3_err     = "GFF3 error: %s",
    msg_bs_err       = "BS error: %s",
    msg_enter_xml    = "Enter a track list / XML URL.",
    msg_no_xml       = "No XML files found.",
    msg_loaded_list  = "Loaded list: %d XML file(s). Pick one.",
    msg_load_err     = "Load error: %s",
    msg_xml_err      = "XML error: %s",
    msg_loaded_xml   = "Loaded %s: %d tracks, %d categories.",
    prog_cache_hic   = "Caching .hic locally (first open may take a while)…",
    prog_overview    = "Reading overview…",
    prog_cache_trk   = "Caching track file…",
    prog_parse_gff3  = "Parsing GFF3 (first time)…",
    prog_read_bs     = "Reading Border Strength…",
    prog_loading     = "Loading…",
    prog_loading_xml = "Loading XML…",
    sel_choose       = "(choose)"
  ),

  # -------------------------------------------------------------------------
  ja = list(
    # nav pills
    nav_data = "データ", nav_region = "領域",
    nav_display = "表示", nav_tracks = "トラック",
    nav_print = "印刷", nav_setting = "設定",
    nav_about = "情報",

    # Data panel
    data_menu_file = "Juicer メニューファイル",
    data_menu_url  = "…またはメニュー URL",
    data_load_menu = "メニューを読み込む",
    data_sample    = "サンプル",
    data_dataset   = "データセット",
    data_norm      = "正規化",
    data_local_hic = "またはローカル .hic ファイル",
    data_hic_path  = ".hic ファイルパス",
    data_open      = "マップを開く",

    # Region panel
    region_chr    = "染色体",
    region_ystart = "Y軸 開始 (bp)",
    region_yend   = "Y軸 終了 (bp)",
    region_goto   = "領域へ移動",

    # Display panel
    disp_palette   = "カラーパレット",
    disp_open_first = "先にマップを開いてください。",
    disp_maxval    = "最大値",
    disp_linear    = "線形",
    disp_log       = "log10(値)",
    disp_value     = "値",
    disp_min_fixed = "最小値は 0 固定。 データ最大 = %s",

    # Tracks panel
    trk_xml_url    = "トラックリスト / IGV XML URL",
    trk_load       = "読み込む",
    trk_xmlfile    = "XML ファイル",
    trk_category   = "カテゴリ",
    trk_from_xml   = "XML からトラック",
    trk_or_path    = "…または bigWig/BED ファイル/URL",
    trk_type       = "種類",
    trk_type_gene  = "遺伝子 (GFF3)",
    trk_type_bs    = "境界強度",
    trk_label      = "ラベル",
    trk_color      = "色",
    trk_height     = "高さ (px)",
    trk_add        = "トラックを追加",
    trk_clear      = "すべて消去",
    trk_none_added = "トラックはありません。",

    # Print panel + modal
    print_title        = "画像出力 / 印刷",
    print_desc         = "現在開いているマップから、指定した領域を画像またはPDFとして出力します。",
    print_open_preview = "印刷プレビューを開く",
    print_help         = paste0("送信先（プリンター / ファイル）、用紙サイズ、出力領域、",
                                "座標メモリ・凡例・余白の有無をプレビュー画面で設定できます。"),
    print_need_map     = "先にマップを開いてください（データ → マップを開く）。",
    print_preview      = "印刷プレビュー",
    print_dest         = "送信先",
    print_dest_printer = "プリンター",
    print_dest_file    = "ファイル",
    print_out_folder   = "出力フォルダ",
    print_browse       = "参照",
    print_filename     = "ファイル名",
    print_format       = "フォーマット",
    print_fmt_png      = "画像 (PNG)",
    print_paper        = "用紙サイズ",
    print_paper_a4p    = "A4 縦",
    print_paper_a4l    = "A4 横",
    print_paper_sq     = "正方形",
    print_paper_custom = "カスタム",
    print_width        = "幅 (mm)",
    print_height       = "高さ (mm)",
    print_region       = "出力領域",
    print_region_note  = "（Hi-C: 縦・横は同一範囲）",
    print_chr          = "染色体",
    print_start        = "開始 (bp)",
    print_end          = "終了 (bp)",
    print_ticks        = "座標メモリを入れる",
    print_legend       = "凡例を入れる",
    print_nomargin     = "余白を空けない",
    print_export_trk   = "トラックも出力する",
    print_run          = "実行",
    print_close        = "閉じる",
    print_check_region = "出力領域を確認してください。",
    print_saved        = "保存しました: %s",
    print_save_err     = "保存エラー: %s",
    print_print_err    = "印刷エラー: %s",
    print_read_err     = "読み込みエラー: %s",

    # Setting panel
    set_map_height   = "コンタクトマップの高さ (px)",
    set_fit          = "ウィンドウに合わせる",
    set_trk_res      = "トラック解像度（表示分割数）",
    set_apply        = "適用",
    set_auto         = "自動調整",
    set_no_trk_size  = "サイズ変更するトラックがありません。",
    set_height       = "高さ",
    set_max_auto     = "最大 (0=自動)",

    # Config-file dialog
    cfg_open         = "設定ファイルを編集…",
    cfg_title        = "設定",
    cfg_intro        = paste0("アプリ起動時の設定を確認・編集できます。アプリフォルダの config.txt に保存されます。",
                              "「設定を反映」ボタンをクリックすると、ページが再読み込みされ、現在の設定が反映されます。",
                              "現在読み込んでいるマップやトラックは閉じられます。"),
    cfg_language     = "表示言語",
    cfg_menu_url     = "既定の Juicer メニュー URL",
    cfg_tracklist    = "既定のトラックリスト / IGV XML URL",
    cfg_raw          = "現在の config.txt の内容",
    cfg_openfile     = "config.txt を開く",
    cfg_apply        = "設定を反映",
    cfg_close        = "閉じる",
    cfg_saved        = "config.txt に保存しました。",
    cfg_openfile_err = "config.txt を開けませんでした: %s",

    # About panel
    about_former  = "旧 HiD contact viewer",
    about_version = "バージョン %s",
    about_author  = "作者: Hideki Tanizawa (",
    about_desc    = paste0("Hi-C コンタクトマップのビューアーです。strawr で .hic (Juicer) を読み、",
                           "ドラッグとズームが可能なタイル式のコンタクトマップを描画します",
                           "（ズームに合わせた解像度で可視領域のみ読み込み）。"),
    about_feat1   = "Juicer 形式のサンプルメニューでデータセット / 解像度 / 正規化を切替",
    about_feat2   = "調整可能なカラースケール（グローバル最大、線形・対数スライダー）",
    about_feat3   = "マップの横軸範囲に同期する 1次元トラック（bigWig / BED）",
    about_feat4   = "リモートの .hic ・トラックファイルをローカルキャッシュして高速化",
    about_built   = paste0("R, Shiny, Leaflet, strawr, rtracklayer で構築。",
                           "Java 版 HiD contact viewer の後継で、rfy_hic2 ワークフローの一部です。"),

    # main-panel readouts
    coord_view      = "表示  x: %s:%s-%s   y: %s:%s-%s%s",
    coord_res       = "    解像度: %s",
    hover_outside   = "カーソルはマップ外です",
    hover_line      = "カーソル  x %s:%s   y %s:%s   スコア %s   距離 %s bp",

    # status / progress / notification messages
    msg_start        = "メニューを読み込み、データセットを選び、マップを開いてください。",
    msg_choose_menu  = "メニューファイルまたは URL を選んでください。",
    msg_menu_err     = "メニューエラー: %s",
    msg_loaded_samp  = "%d 件のサンプルを読み込みました。",
    msg_pick_src     = "データセットを選ぶか、ローカル .hic パスを入力してください。",
    msg_open_err     = "オープンエラー: %s",
    msg_ready        = "準備完了: %s (%s bp)。解像度 %s。",
    msg_enter_track  = "トラックファイルのパスまたは URL を入力してください。",
    msg_added_track  = "トラックを追加: %s (%s)",
    msg_cleared_trk  = "すべてのトラックを消去しました。",
    msg_gff3_err     = "GFF3 エラー: %s",
    msg_bs_err       = "BS エラー: %s",
    msg_enter_xml    = "トラックリスト / XML URL を入力してください。",
    msg_no_xml       = "XML ファイルが見つかりません。",
    msg_loaded_list  = "リストを読み込み: %d 件の XML ファイル。選んでください。",
    msg_load_err     = "読み込みエラー: %s",
    msg_xml_err      = "XML エラー: %s",
    msg_loaded_xml   = "%s を読み込み: %d トラック、%d カテゴリ。",
    prog_cache_hic   = ".hic をローカルにキャッシュ中（初回は時間がかかることがあります）…",
    prog_overview    = "概要を読み込み中…",
    prog_cache_trk   = "トラックファイルをキャッシュ中…",
    prog_parse_gff3  = "GFF3 を解析中（初回）…",
    prog_read_bs     = "境界強度を読み込み中…",
    prog_loading     = "読み込み中…",
    prog_loading_xml = "XML を読み込み中…",
    sel_choose       = "（選択）"
  )
)

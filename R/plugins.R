# ============================================================================
# plugins.R  -  user-defined track types written in R ("plugins")
#
# A plugin is a small R file in the plugins/ folder next to app.R (or in the
# folder named by `plugin_dir` in config.txt). It calls hicarta_plugin() once
# to register a new TRACK TYPE: a function that reads what is needed for the
# region on screen and a function that draws it under the contact map.
# HiCarta does everything else - the catalog (file_type = <plugin id>, then
# "Add as track"), the direct-file tab, the track list, the settings dialog
# (name / colour / height / parameters), the session file, and the print
# preview / export, where the same draw() runs with the same x range as every
# built-in track.
#
# Minimal plugin (one R function = one track):
#
#   hicarta_plugin(
#     id    = "csv",                                   # file_type in the catalog
#     label = "CSV signal",
#     read  = function(path, chr, start, end, p) {      # data for [start, end]
#       d <- read.csv(path)
#       d[d$chr == chr & d$end >= start & d$start <= end, ]
#     },
#     draw  = function(d, chr, vstart, vend, style) {
#       hc_canvas(vstart, vend, ylim = c(0, max(d$value, 1)))
#       rect(d$start, 0, d$end, d$value, col = style$color, border = NA)
#       hc_label(style$name)
#     })
#
# The contract that keeps a plugin aligned with the contact map above it:
#   * draw() receives the FULL x range of the map view [vstart, vend] - which
#     can run past the chromosome ends - and must plot with xlim = c(vstart,
#     vend) and xaxs = "i". hc_canvas() does exactly that. Never touch par(mar).
#   * read() receives the part of that range inside the chromosome
#     ([1, chrlen]). Its result is cached per region and parameter set.
#   * Parameters: `defaults` names them (with their default values). The
#     catalog's set_<name> columns, the track settings dialog and the session
#     file override them; read() gets the merged list as `p`, draw() as
#     style$params.
#
# Reading data the HiCarta way (remote files are streamed, never downloaded):
#   hc_hic_region(path, chr, start, end, resolution, norm, chr2, start2, end2)
#       -> numeric matrix, rows = bins of chr, columns = bins of chr2
#   hc_bin_starts(m, 1) / hc_bin_starts(m, 2)   -> bin start coordinates (bp)
#   hc_hic_pick_resolution(path, chr, start, end, target_bins)
#   hc_hic_chroms(path), hc_hic_resolutions(path), hc_hic_norms(path)
#   hc_bigwig_bins(path, chr, start, end, nbins, type)  -> one value per bin
#   hc_bigwig_intervals(path, chr, start, end)   -> data.frame(start, end, value)
#
# Drawing helpers: hc_canvas(), hc_label(), hc_guide(), hc_yaxis(), hc_message().
#
# A plugin is ordinary R code the user chose to put in the folder, so it runs
# with the same trust as HiCarta itself. A plugin that fails to load is
# reported at start-up and skipped; one that fails while drawing prints its
# error inside its own panel and leaves the rest of the app alone.
# ============================================================================

.PLUGINS      <- new.env(parent = emptyenv())   # id -> plugin spec
.PLUGINS_META <- new.env(parent = emptyenv())   # dir, load report, flags
.PLUGIN_CACHE <- new.env(parent = emptyenv())   # read() results per region
PLUGIN_CACHE_MAX <- 32L

# file types HiCarta handles itself; a plugin may not reuse these ids
PLUGIN_BUILTIN_TYPES <- c("hic", "bigwig", "bed", "gff3", "bs", "arc")

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---------------------------------------------------------------------------
# Registration (called from the plugin file)
# ---------------------------------------------------------------------------
hicarta_plugin <- function(id, label = id, draw, read = NULL, defaults = list(),
                           accepts = "any", extensions = character(0),
                           chroms = NULL, height = 90, color = "darkblue",
                           description = "") {
  id <- tolower(trimws(as.character(id)[1]))
  if (is.na(id) || !grepl("^[a-z][a-z0-9_]{0,31}$", id))
    stop("plugin id must be 1-32 lowercase letters, digits or '_' and start ",
         "with a letter (got '", id, "')", call. = FALSE)
  if (id %in% PLUGIN_BUILTIN_TYPES)
    stop("plugin id '", id, "' is a built-in file type", call. = FALSE)
  if (missing(draw) || !is.function(draw))
    stop("plugin '", id, "': draw must be a function(d, chr, vstart, vend, style)",
         call. = FALSE)
  if (!is.null(read) && !is.function(read))
    stop("plugin '", id, "': read must be a function(path, chr, start, end, p) or NULL",
         call. = FALSE)
  if (!is.list(defaults) ||
      (length(defaults) && (is.null(names(defaults)) || any(!nzchar(names(defaults))))))
    stop("plugin '", id, "': defaults must be a named list", call. = FALSE)
  if (!is.null(chroms) && !is.function(chroms))
    stop("plugin '", id, "': chroms must be a function(path) or NULL", call. = FALSE)
  accepts <- tolower(trimws(as.character(accepts)))
  accepts <- accepts[nzchar(accepts)]
  if (!length(accepts)) accepts <- "any"
  extensions <- tolower(sub("^\\.", "", trimws(as.character(extensions))))
  extensions <- extensions[nzchar(extensions)]
  ht <- suppressWarnings(as.numeric(height))[1]
  if (!is.finite(ht) || ht < 20) ht <- 90
  spec <- list(id = id, label = as.character(label)[1] %||% id,
               draw = draw, read = read, defaults = defaults,
               accepts = accepts, extensions = extensions, chroms = chroms,
               height = ht, color = as.character(color)[1] %||% "darkblue",
               description = as.character(description)[1] %||% "",
               file = get0("current_file", envir = .PLUGINS_META,
                           ifnotfound = NA_character_))
  if (exists(id, envir = .PLUGINS, inherits = FALSE))
    warning("plugin id '", id, "' registered twice; the later one wins", call. = FALSE)
  assign(id, spec, envir = .PLUGINS)
  invisible(spec)
}

# ---------------------------------------------------------------------------
# Registry queries
# ---------------------------------------------------------------------------
plugin_ids     <- function() sort(ls(.PLUGINS))
plugin_type    <- function(id) paste0("plugin:", plugin_id_of(id))
is_plugin_type <- function(type)
  is.character(type) && length(type) == 1 && !is.na(type) && startsWith(type, "plugin:")
plugin_id_of   <- function(x) sub("^plugin:", "", as.character(x)[1])
plugin_get     <- function(x) {
  id <- plugin_id_of(x)
  if (is.na(id) || !nzchar(id) || !exists(id, envir = .PLUGINS, inherits = FALSE))
    return(NULL)
  get(id, envir = .PLUGINS, inherits = FALSE)
}
plugin_label   <- function(x) {
  p <- plugin_get(x); if (is.null(p)) plugin_id_of(x) else p$label
}
# one line "Label (id)" per plugin, for menus
plugin_choices <- function() {
  ids <- plugin_ids()
  if (!length(ids)) return(character(0))
  stats::setNames(vapply(ids, plugin_type, character(1)),
                  vapply(ids, function(i) sprintf("%s (%s)", plugin_label(i), i),
                         character(1)))
}
plugin_dir <- function() get0("dir", envir = .PLUGINS_META, ifnotfound = NA_character_)

# plugin id claiming this file by extension, else NA (used after
# cat_guess_type() found nothing)
plugin_guess <- function(path) {
  if (is.null(path) || length(path) != 1 || is.na(path)) return(NA_character_)
  b <- tolower(basename(sub("\\?.*$", "", path)))
  b <- sub("\\.gz$", "", b)
  ext <- tools::file_ext(b)
  if (!nzchar(ext)) return(NA_character_)
  for (id in plugin_ids()) {
    p <- plugin_get(id)
    if (ext %in% p$extensions) return(id)
  }
  NA_character_
}

# ---------------------------------------------------------------------------
# Loading: every *.R in the folder, each in its own environment whose parent
# is HiCarta's (so hc_*() and the readers are visible). Files are read as
# UTF-8 so comments in any language survive a Windows locale.
# ---------------------------------------------------------------------------
load_plugins <- function(dir = NULL, env = parent.frame()) {
  rm(list = ls(.PLUGINS), envir = .PLUGINS)
  rm(list = ls(.PLUGIN_CACHE), envir = .PLUGIN_CACHE)
  if (is.null(dir) || !nzchar(dir)) dir <- file.path(getwd(), "plugins")
  assign("dir", dir, envir = .PLUGINS_META)
  report <- list()
  files <- if (dir.exists(dir))
             sort(list.files(dir, pattern = "\\.[Rr]$", full.names = TRUE))
           else character(0)
  for (f in files) {
    before <- ls(.PLUGINS)
    assign("current_file", basename(f), envir = .PLUGINS_META)
    # errors stop the file; warnings are kept out of the way (a warning from a
    # library() call inside a plugin is not a reason to drop the plugin)
    err <- tryCatch({
      withCallingHandlers(
        source(f, local = new.env(parent = env), encoding = "UTF-8"),
        warning = function(w) invokeRestart("muffleWarning"))
      NULL
    }, error = function(e) conditionMessage(e))
    added <- setdiff(ls(.PLUGINS), before)
    if (is.null(err) && !length(added))
      err <- "loaded, but hicarta_plugin() was never called"
    report[[basename(f)]] <- list(file = basename(f), ok = is.null(err),
                                  error = err, ids = added)
  }
  if (exists("current_file", envir = .PLUGINS_META))
    rm("current_file", envir = .PLUGINS_META)
  assign("report", report, envir = .PLUGINS_META)
  invisible(plugin_ids())
}

plugin_report <- function() get0("report", envir = .PLUGINS_META, ifnotfound = list())

# one line per file, for the start-up notification and the About panel
plugin_report_text <- function() {
  rep <- plugin_report()
  if (!length(rep)) return(character(0))
  vapply(rep, function(r)
    if (isTRUE(r$ok)) sprintf("%s -> %s", r$file, paste(r$ids, collapse = ", "))
    else sprintf("%s: FAILED (%s)", r$file, r$error),
    character(1), USE.NAMES = FALSE)
}

# did any plugin file fail?  (shown once per session)
plugin_failures <- function() {
  rep <- plugin_report()
  Filter(function(r) !isTRUE(r$ok), rep)
}

# ---------------------------------------------------------------------------
# Parameters: defaults overridden by what the catalog / dialog / session gave
# ---------------------------------------------------------------------------
# A value typed in a dialog or a catalog cell arrives as text; make it the
# type of the default when that converts cleanly. Empty = back to the default.
.plugin_coerce <- function(v, template) {
  if (is.null(v) || length(v) == 0) return(template)
  if (is.character(v) && length(v) == 1) {
    s <- trimws(v)
    if (!nzchar(s)) return(template)
    if (is.numeric(template)) {
      n <- suppressWarnings(as.numeric(s))
      return(if (is.finite(n)) n else template)
    }
    if (is.logical(template))
      return(tolower(s) %in% c("true", "t", "yes", "y", "1", "on"))
    return(s)
  }
  v
}

plugin_params <- function(spec) {
  p <- plugin_get(spec$type)
  defs <- if (is.null(p)) list() else p$defaults
  over <- spec$params %||% list()
  out <- defs
  for (nm in names(over)) out[[nm]] <- .plugin_coerce(over[[nm]], defs[[nm]])
  out
}

# values the user may edit, as text (for the settings dialog / session file)
plugin_params_text <- function(spec) {
  pp <- plugin_params(spec)
  lapply(pp, function(x) if (is.null(x)) "" else paste(format(x), collapse = ","))
}

.plugin_params_key <- function(pp)
  paste(vapply(names(pp), function(n)
    paste0(n, "=", paste(format(pp[[n]]), collapse = ",")), character(1)),
    collapse = ";")

# ---------------------------------------------------------------------------
# Data for a region, cached. Keys include the parameters, so a changed
# parameter is a new read and an unchanged one costs nothing.
# ---------------------------------------------------------------------------
plugin_data <- function(spec, chr, start, end) {
  p <- plugin_get(spec$type)
  if (is.null(p)) stop("plugin '", plugin_id_of(spec$type), "' is not loaded")
  if (is.null(p$read)) return(NULL)
  pp  <- plugin_params(spec)
  key <- paste(p$id, spec$path, chr, start, end, .plugin_params_key(pp), sep = "|")
  hit <- get0(key, envir = .PLUGIN_CACHE, ifnotfound = NULL)
  if (!is.null(hit)) { hit$t <- Sys.time(); assign(key, hit, envir = .PLUGIN_CACHE); return(hit$d) }
  d <- p$read(spec$path, chr, start, end, pp)
  assign(key, list(t = Sys.time(), d = d), envir = .PLUGIN_CACHE)
  keys <- ls(.PLUGIN_CACHE)
  if (length(keys) > PLUGIN_CACHE_MAX) {
    ts <- vapply(keys, function(k) as.numeric(get(k, envir = .PLUGIN_CACHE)$t), numeric(1))
    rm(list = keys[order(ts)][seq_len(length(keys) - PLUGIN_CACHE_MAX)],
       envir = .PLUGIN_CACHE)
  }
  d
}

plugin_forget <- function() rm(list = ls(.PLUGIN_CACHE), envir = .PLUGIN_CACHE)

# ---------------------------------------------------------------------------
# Drawing: the one entry point app.R calls, for the screen and for export.
# Same signature family as plot_track(): mar / frame / yscale are the export
# layout's business, the plugin never sees them.
# ---------------------------------------------------------------------------
plugin_draw <- function(spec, chr, vstart, vend, chrlen = Inf,
                        mar = c(0.3, 0, 0.3, 0), frame = TRUE, yscale = "inline") {
  op <- par(mar = mar); on.exit(par(op))
  assign("canvas_called", FALSE, envir = .PLUGINS_META)
  p <- plugin_get(spec$type)
  if (is.null(p)) {
    hc_canvas(vstart, vend)
    hc_message(sprintf("plugin '%s' is not loaded (folder: %s)",
                       plugin_id_of(spec$type), plugin_dir()))
    if (isTRUE(frame)) box(col = "grey85")
    return(invisible(NULL))
  }
  if (!is.finite(chrlen)) chrlen <- Inf
  dstart <- max(1, floor(vstart)); dend <- min(chrlen, ceiling(vend))
  style <- list(name = spec$name %||% p$label,
                color = spec$color %||% p$color,
                height = spec$height %||% p$height,
                ymin = if (is.null(spec$ymin) || !is.finite(spec$ymin)) NA_real_ else spec$ymin,
                ymax = if (is.null(spec$ymax) || !is.finite(spec$ymax) || spec$ymax <= 0) NA_real_ else spec$ymax,
                params = plugin_params(spec),
                print = identical(yscale, "axis"), yscale = yscale,
                chrlen = chrlen, dstart = dstart, dend = dend,
                path = spec$path, id = p$id)
  err <- tryCatch({
    d <- if (dend > dstart) plugin_data(spec, chr, dstart, dend) else NULL
    p$draw(d, chr, vstart, vend, style)
    NULL
  }, error = function(e) conditionMessage(e))
  if (!is.null(err)) {
    if (!isTRUE(get0("canvas_called", envir = .PLUGINS_META, ifnotfound = FALSE)))
      hc_canvas(vstart, vend)
    hc_message(sprintf("%s: %s", p$label, err))
    message("[plugin ", p$id, "] ", err)
  }
  if (isTRUE(frame)) box(col = "grey85")
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Helpers for plugin authors: drawing
# ---------------------------------------------------------------------------
# The canvas every plugin should start with: x spans exactly the map view, so
# the panel lines up with the contact map and the other tracks.
hc_canvas <- function(vstart, vend, ylim = c(0, 1), headroom = 0.05, bg = NA) {
  ylim <- suppressWarnings(as.numeric(ylim))
  if (length(ylim) != 2 || !all(is.finite(ylim))) ylim <- c(0, 1)
  if (ylim[2] <= ylim[1]) ylim[2] <- ylim[1] + max(abs(ylim[1]) * 0.05, 1)
  span <- ylim[2] - ylim[1]
  ytop <- ylim[2] + span * headroom
  ybot <- if (ylim[1] < 0) ylim[1] - span * headroom else ylim[1]
  plot(NA, xlim = c(vstart, vend), ylim = c(ybot, ytop),
       xaxs = "i", yaxs = "i", axes = FALSE, ann = FALSE)
  if (!is.na(bg)) rect(vstart, ybot, vend, ytop, col = bg, border = NA)
  assign("canvas_called", TRUE, envir = .PLUGINS_META)
  invisible(c(ybot, ytop))
}

# track name at the top-left, exactly where the built-in tracks put theirs
hc_label <- function(name, cex = 1.15, col = "grey20") {
  u <- par("usr")
  text(u[1] + 0.005 * (u[2] - u[1]), u[4], name, adj = c(0, 1), cex = cex, col = col)
  invisible(NULL)
}

# a horizontal guide line with its value at the right-hand side (inline
# scale, like the built-in signal tracks)
hc_guide <- function(y, fmt = "%.3g ", col = "grey45", cex = 1.0) {
  u <- par("usr")
  if (!is.finite(y) || y > u[4] || y < u[3]) return(invisible(NULL))
  Wpx <- tryCatch(grDevices::dev.size("px")[1], error = function(e) 800)
  gutfrac <- (66 + 8) / Wpx
  lx <- u[1] + (1 - gutfrac) * (u[2] - u[1])
  segments(lx, y, u[1] + (1 - 4 / Wpx) * (u[2] - u[1]), y, col = col)
  text(lx, y, sprintf(fmt, y), adj = c(1, 0.5), cex = cex, col = "grey20")
  invisible(NULL)
}

# a real left axis (publication style); style$print says when to use it
hc_yaxis <- function(at = NULL, n = 3, cex = 0.8) {
  u <- par("usr")
  if (is.null(at)) at <- pretty(c(u[3], u[4]), n)
  at <- at[at >= u[3] & at <= u[4]]
  axis(2, at = at, labels = formatC(at, format = "g", digits = 3), las = 1,
       tcl = -0.4, mgp = c(3, 0.5, 0), cex.axis = cex, col = "grey40",
       col.axis = "grey20")
  invisible(at)
}

# a message inside the panel (used for errors and "nothing here")
hc_message <- function(msg, col = "firebrick", cex = 0.95) {
  u <- par("usr")
  text(u[1] + 0.01 * (u[2] - u[1]), (u[3] + u[4]) / 2, msg,
       adj = c(0, 0.5), cex = cex, col = col)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Helpers for plugin authors: reading through HiCarta's own readers
# ---------------------------------------------------------------------------
# Contact matrix of [start,end] on chr (rows) against [start2,end2] on chr2
# (columns), at `resolution` bp with normalization `norm`, read with the
# native .hic reader (local file, http(s) URL or s3://). Row / column names
# are "chr:start:end" labels; hc_bin_starts() turns them into coordinates.
hc_hic_region <- function(path, chr, start, end, resolution = 10000, norm = "KR",
                          chr2 = NULL, start2 = NULL, end2 = NULL) {
  read_hic_map(path, chr, start, end, resolution = resolution,
               normalization = norm, chr2 = chr2, start2 = start2, end2 = end2)
}
hc_bin_starts <- function(m, margin = 1) {
  lab <- dimnames(m)[[margin]]
  if (is.null(lab)) return(numeric(0))
  as.numeric(vapply(strsplit(lab, ":", fixed = TRUE), function(x) x[2], character(1)))
}
hc_hic_chroms      <- function(path) hic_chroms(path)
hc_hic_resolutions <- function(path) hic_resolutions(path)
hc_hic_norms       <- function(path) hic_norms(path)
# the resolution in the file closest to `target_bins` bins across the view
hc_hic_pick_resolution <- function(path, chr, start, end, target_bins = 500,
                                   norm = "KR") {
  res <- tryCatch(hic_resolutions_chr(path, chr, norm), error = function(e) numeric(0))
  if (!length(res)) res <- tryCatch(hic_resolutions(path), error = function(e) 10000)
  want <- (end - start) / max(1, target_bins)
  res[which.min(abs(log(res) - log(max(want, 1))))]
}

# bigWig signal as one value per bin across [start,end] (mean or max), and the
# raw intervals; both stream the file like the built-in bigWig track does.
hc_bigwig_bins <- function(path, chr, start, end, nbins = 1000, type = "mean")
  .track_binned_signal(path, chr, start, end, nbins, type)
hc_bigwig_intervals <- function(path, chr, start, end) {
  if (exists("bw_reader") && .bw_native_ok(path)) {
    iv <- bw_intervals(bw_reader(path), chr, max(1, floor(start)), ceiling(end))
    return(as.data.frame(iv)[, c("start", "end", "value")])
  }
  gr <- .track_import(path, chr, start, end)
  if (is.null(gr)) return(data.frame(start = numeric(0), end = numeric(0), value = numeric(0)))
  data.frame(start = GenomicRanges::start(gr), end = GenomicRanges::end(gr),
             value = as.numeric(GenomicRanges::score(gr)))
}

# ---------------------------------------------------------------------------
# Coordinate system from a plugin track (track-only mode): the plugin's own
# chroms(path) if it has one, else by what it accepts.
# ---------------------------------------------------------------------------
plugin_chrom_info <- function(path, type) {
  p <- plugin_get(type)
  if (is.null(p)) return(NULL)
  if (!is.null(p$chroms)) {
    ci <- tryCatch(p$chroms(path), error = function(e) NULL)
    if (!is.null(ci) && length(ci)) return(stats::setNames(as.numeric(ci), names(ci)))
  }
  acc <- p$accepts[1]
  inner <- switch(acc, hic = "RotMap", bigwig = "bigWig", gff3 = "gene",
                  bs = "BorderStrength", arc = "Arc", bed = "BED", NA_character_)
  if (is.na(inner)) {
    # guess from the file name as a last resort (a plugin id coming back from
    # the guess is no help here, hence the single bracket + NA check)
    g <- cat_guess_type(path)
    inner <- if (is.na(g)) NA_character_
             else unname(c(hic = "RotMap", bigwig = "bigWig", gff3 = "gene",
                           bs = "BorderStrength", arc = "Arc", bed = "BED")[g])
  }
  if (is.na(inner)) return(NULL)
  track_chrom_info(path, inner)
}

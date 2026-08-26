# ============================================================================
# tracks.R  -  1-D genome tracks (bigWig signal, BED intervals) drawn below the
# Hi-C map and synced to its x (horizontal) view range.
#
# Only the visible window is read on each draw (rtracklayer 'which' query), so
# tracks stay light even for genome-wide files. A track spec is a list:
#   list(id, name, path, type = "bigWig"|"BED", color, height)
# ============================================================================

# Parse an IGV-style track-list XML:
#   <Global><Category name="..."><Resource name="X" path="Y.bw"/>...</Category></Global>
# Returns data.frame(name, path, type) with type inferred from the extension.
parse_igv_xml <- function(src) {
  con <- if (grepl("^https?://", src)) url(src) else src
  txt <- paste(readLines(con, warn = FALSE), collapse = "\n")
  getattr <- function(x, a) {
    ok <- grepl(paste0(a, '="'), x); out <- rep(NA_character_, length(x))
    out[ok] <- sub(paste0('.*?', a, '="([^"]*)".*'), "\\1", x[ok], perl = TRUE); out
  }
  # split into <Category> blocks so each Resource keeps its category (XML order)
  blocks <- strsplit(txt, "<Category", fixed = TRUE)[[1]]
  out <- list()
  for (blk in blocks) {
    res <- regmatches(blk, gregexpr("<Resource[^>]*>", blk, perl = TRUE))[[1]]
    if (length(res) == 0) next
    m <- regexpr('name="[^"]*"', blk, perl = TRUE)   # first name attr = the Category name
    catname <- if (m > 0) sub('name="([^"]*)"', "\\1", regmatches(blk, m)) else "(uncategorized)"
    nm <- getattr(res, "name"); pt <- getattr(res, "path")
    keep <- !is.na(pt); nm <- nm[keep]; pt <- pt[keep]
    nm[is.na(nm)] <- basename(pt[is.na(nm)])
    ext  <- tolower(tools::file_ext(pt))
    type <- ifelse(ext %in% c("bed", "narrowpeak", "broadpeak"), "BED", "bigWig")
    out[[length(out) + 1]] <- data.frame(category = catname, name = nm,
                                         path = pt, type = type, stringsAsFactors = FALSE)
  }
  if (length(out) == 0)
    return(data.frame(category = character(0), name = character(0),
                      path = character(0), type = character(0)))
  do.call(rbind, out)
}

# ---------------------------------------------------------------------------
# bigWig engine.
#
# rtracklayer cannot open a bigWig over http(s) (the Bioconductor build has no
# Kent remote support), so remote tracks used to be downloaded in full before
# reading. R/bigwig_reader.R streams them instead. Same switch as for .hic:
#   "native"   stream over HTTP range requests (default)
#   "download" fetch the whole file into _hic_cache/ first, then use rtracklayer
# Anything the native reader cannot handle falls back to rtracklayer on a
# locally cached copy, so an odd file degrades instead of breaking.
# ---------------------------------------------------------------------------
.bw_native_ok <- function(path) {
  exists("bw_reader") && identical(hic_engine(), "native") &&
    tolower(tools::file_ext(path)) %in% c("bw", "bigwig")
}

# Path to hand rtracklayer: it needs a local file, so a URL must be cached.
.track_local <- function(path) cache_local(path)

# Path to store in a track spec when the user adds a track. bigWig is streamed
# by the native reader, so the URL is kept as-is; every other track type (BED,
# GFF3, Border Strength) is still parsed whole and needs a local copy.
track_source <- function(path) {
  if (.bw_native_ok(path)) path else cache_local(path)
}

# Read a track over [start,end] on `chr`. Tries the chromosome name as given and
# common variants (chrII <-> II) so naming differences don't silently blank out.
# Returns a GRanges (rtracklayer path) or a data.frame(start, end, value).
.track_import <- function(path, chr, start, end) {
  start <- max(1, floor(start)); end <- ceiling(end)

  if (.bw_native_ok(path)) {
    iv <- tryCatch(bw_intervals(bw_reader(path), chr, start, end),
                   error = function(e) {
                     message("[track] native bigWig reader failed (",
                             conditionMessage(e), ") - falling back to rtracklayer")
                     NULL
                   })
    if (!is.null(iv)) {
      if (nrow(iv) == 0) return(NULL)
      return(GenomicRanges::GRanges(
        chr, IRanges::IRanges(iv$start, iv$end), score = iv$value))
    }
  }

  p <- .track_local(path)
  cand <- unique(c(chr, sub("^chr", "", chr), paste0("chr", chr)))
  for (cc in cand) {
    gr <- tryCatch(
      rtracklayer::import(p,
        which = GenomicRanges::GRanges(cc, IRanges::IRanges(start, end))),
      error = function(e) NULL)
    if (!is.null(gr) && length(gr) > 0) return(gr)
  }
  NULL
}

# Aggregate a bigWig into `nbins` equal bins across [start,end], returning one
# value per bin. This mirrors what IGV does at wide zoom: instead of sampling a
# single point per bin, every base in the bin contributes. We use rtracklayer's
# summary(), which reads the bigWig's precomputed zoom-level summaries (the same
# machinery IGV uses) so genome-wide views are both accurate and fast.
#   type = "mean" -> average signal over the bin (IGV default)
#   type = "max"  -> peak signal in the bin (peaks are not averaged away)
# Uncovered bins become 0. Falls back to a raw import + proper overlap binning
# (NOT point sampling) if summary() is unavailable for the file.
.track_binned_signal <- function(path, chr, start, end, nbins, type = "mean") {
  nbins <- max(2L, as.integer(nbins))
  type  <- if (isTRUE(type %in% c("mean", "max"))) type else "mean"
  cand  <- unique(c(chr, sub("^chr", "", chr), paste0("chr", chr)))

  # Native streaming reader first. It uses the file's own zoom levels for wide
  # views exactly like Kent's code, and full-resolution data when that is small
  # enough (which is then exact rather than approximate).
  if (.bw_native_ok(path)) {
    v <- tryCatch({
      rd <- bw_reader(path)
      for (cc in cand) {
        got <- bw_summary(rd, cc, start, end, nbins, type)
        if (length(got) == nbins && any(got != 0)) return(got)
      }
      bw_summary(rd, cand[1], start, end, nbins, type)
    }, error = function(e) {
      message("[track] native bigWig summary failed (", conditionMessage(e),
              ") - falling back to rtracklayer")
      NULL
    })
    if (!is.null(v) && length(v) == nbins) return(v)
  }

  path <- .track_local(path)
  bwf <- tryCatch(rtracklayer::BigWigFile(path), error = function(e) NULL)
  if (!is.null(bwf)) {
    for (cc in cand) {
      v <- tryCatch({
        gr <- GenomicRanges::GRanges(cc, IRanges::IRanges(start, end))
        s  <- rtracklayer::summary(bwf, which = gr, size = nbins,
                                   type = type, defaultValue = 0)
        out <- as.numeric(GenomicRanges::score(s[[1]]))
        out[!is.finite(out)] <- 0
        out
      }, error = function(e) NULL)
      if (!is.null(v) && length(v) == nbins) return(v)
    }
  }

  # Fallback: read raw intervals and bin them by overlap (coverage-weighted mean
  # over covered bases, or max), so gaps read as 0 rather than dropping peaks.
  gr <- .track_import(path, chr, start, end)
  val <- rep(0, nbins)
  if (!is.null(gr) && length(gr) > 0) {
    rs <- GenomicRanges::start(gr); re <- GenomicRanges::end(gr)
    sv <- as.numeric(GenomicRanges::score(gr))
    breaks <- seq(start, end, length.out = nbins + 1L)
    for (i in seq_len(nbins)) {
      b0 <- breaks[i]; b1 <- breaks[i + 1L]
      ov <- which(re >= b0 & rs <= b1)
      if (length(ov) == 0) next
      if (identical(type, "max")) {
        val[i] <- suppressWarnings(max(sv[ov], na.rm = TRUE))
      } else {
        w <- pmin(re[ov], b1) - pmax(rs[ov], b0) + 1
        w[w < 0] <- 0
        val[i] <- if (sum(w) > 0) sum(sv[ov] * w, na.rm = TRUE) / sum(w) else 0
      }
    }
    val[!is.finite(val)] <- 0
  }
  val
}

# Draw one track. The x-axis spans the FULL map view [vstart,vend] (which may run
# past the chromosome ends, so it stays aligned with the contact map); signal is
# only drawn within [1, chrlen]. `nbins` = number of bins across the view.
# spec$ymax > 0 fixes the top of the vertical scale (else it auto-scales to the
# view). spec$ymin, when finite, fixes the bottom and MAY BE NEGATIVE -- that is
# what lets a subtraction / log-ratio bigWig be shown; when it is NULL/NA the
# bottom auto-scales to min(0, data min), so ordinary positive tracks keep their
# familiar 0 baseline and signed tracks open up downwards on their own.
plot_track <- function(spec, chr, vstart, vend, chrlen = Inf, nbins = 1000,
                       mar = c(0.3, 0, 0.3, 0), frame = TRUE, yscale = "inline") {
  op <- par(mar = mar); on.exit(par(op))
  dstart <- max(1, floor(vstart)); dend <- min(chrlen, ceiling(vend))
  # BED needs the raw intervals; bigWig is aggregated from zoom levels below, so
  # we avoid the expensive genome-wide raw import for it.
  gr <- if (identical(spec$type, "BED") && dend > dstart)
          .track_import(spec$path, chr, dstart, dend) else NULL
  Wpx <- tryCatch(grDevices::dev.size("px")[1], error = function(e) 800)
  gutfrac <- (66 + 8) / Wpx                     # keep labels left of the y-ruler gutter
  lx <- vstart + (1 - gutfrac) * (vend - vstart)

  if (identical(spec$type, "BED")) {
    plot(NA, xlim = c(vstart, vend), ylim = c(0, 1),
         xaxs = "i", yaxs = "i", axes = FALSE, ann = FALSE)
    if (!is.null(gr) && length(gr) > 0) {
      xs <- pmax(dstart, GenomicRanges::start(gr))
      xe <- pmin(dend,   GenomicRanges::end(gr))
      rect(xs, 0.30, xe, 0.70, col = spec$color, border = NA)
    }
    text(vstart + 0.005 * (vend - vstart), 0.90, spec$name,
         adj = c(0, 1), cex = 1.15, col = "grey20")
  } else {
    nbins   <- max(2L, as.integer(nbins))
    agg     <- if (!is.null(spec$agg) && spec$agg %in% c("mean", "max")) spec$agg else "mean"
    binw    <- (dend - dstart) / nbins
    centers <- dstart + (seq_len(nbins) - 0.5) * binw   # true bin centers
    val <- if (dend > dstart)
             .track_binned_signal(spec$path, chr, dstart, dend, nbins, agg)
           else rep(0, nbins)
    # ---- vertical scale --------------------------------------------------
    # ymax: > 0 fixes the top, otherwise auto = max(data, 0).
    # ymin: any finite value fixes the bottom, negatives included; NULL/NA means
    #       auto = min(data, 0). So a positive-only track behaves exactly as
    #       before and a subtraction track gets room below zero for free.
    dmax <- suppressWarnings(max(val, na.rm = TRUE))
    dmin <- suppressWarnings(min(val, na.rm = TRUE))
    if (!is.finite(dmax)) dmax <- 0
    if (!is.finite(dmin)) dmin <- 0
    ymax <- if (!is.null(spec$ymax) && is.finite(spec$ymax) && spec$ymax > 0) spec$ymax
            else max(dmax, 0)
    ymin <- if (!is.null(spec$ymin) && is.finite(spec$ymin)) spec$ymin
            else min(dmin, 0)
    if (!is.finite(ymin)) ymin <- 0
    if (!is.finite(ymax)) ymax <- 1
    if (ymax <= ymin) ymax <- ymin + max(abs(ymin) * 0.05, 1)   # never a flat axis
    span <- ymax - ymin
    ytop <- ymax + span * 0.05                     # 5% headroom, as before
    ybot <- if (ymin < 0) ymin - span * 0.05 else ymin   # 0 stays flush at the bottom
    base <- min(max(0, ymin), ymax)                # bars grow from zero when zero is in range

    plot(NA, xlim = c(vstart, vend), ylim = c(ybot, ytop),
         xaxs = "i", yaxs = "i", axes = FALSE, ann = FALSE)
    if (base > ybot)                               # visible zero line for signed tracks
      segments(vstart, base, vend, base, col = "grey70")
    if (dend > dstart) {
      hv <- pmin(pmax(val, ymin), ymax)            # saturate at the fixed limits
      rect(centers - binw / 2, base, centers + binw / 2, hv,
           col = spec$color, border = NA)
    }
    # name (top-left, larger) + round score labels on the right
    text(vstart + 0.005 * (vend - vstart), ymax, spec$name,
         adj = c(0, 1), cex = 1.15, col = "grey20")
    if (identical(yscale, "axis")) {
      # publication style: a real left Y-axis, ticks the SAME length (tcl) as the
      # Hi-C map's axis so they match regardless of track height.
      at <- pretty(c(ymin, ymax), 3); at <- at[at >= ybot & at <= ytop]
      axis(2, at = at, labels = formatC(at, format = "g", digits = 3), las = 1,
           tcl = -0.4, mgp = c(3, 0.5, 0), cex.axis = 0.8, col = "grey40", col.axis = "grey20")
    } else {
      # inline style: one guide line near the top and, for signed tracks, one
      # near the bottom so the negative half is readable too.
      guide <- function(yv) {
        if (!is.finite(yv) || yv == 0 || yv > ytop || yv < ybot) return(invisible(NULL))
        segments(lx, yv, vstart + (1 - 4 / Wpx) * (vend - vstart), yv, col = "grey45")
        text(lx, yv, sprintf("%.3g ", yv), adj = c(1, 0.5), cex = 1.0, col = "grey20")
      }
      if (ymax > 0) guide(signif(ymax * 0.9, 1))
      if (ymin < 0) guide(signif(ymin * 0.9, 1))
    }
  }
  if (isTRUE(frame)) box(col = "grey85")
}

# ---------------------------------------------------------------------------
# plot_ruler(): thin x-coordinate scale drawn ABOVE the tracks when no contact
# map (which has its own Leaflet ruler) is on screen. Zero left/right margins
# and the same xlim/xaxs as plot_track(), so its ticks line up with the tracks
# below. It is drawn in real genomic coordinates, so a Shiny brush on this
# plot reports bp positions directly (used for drag-to-zoom).
# ---------------------------------------------------------------------------
plot_ruler <- function(chr, vstart, vend, chrlen = Inf,
                       mar = c(0, 0, 0, 0)) {
  op <- par(mar = mar); on.exit(par(op))
  plot(NA, xlim = c(vstart, vend), ylim = c(0, 1),
       xaxs = "i", yaxs = "i", axes = FALSE, ann = FALSE)
  rng <- vend - vstart
  if (!is.finite(rng) || rng <= 0) return(invisible(NULL))
  rect(vstart, 0, vend, 1, col = "grey96", border = NA)
  segments(vstart, 0.04, vend, 0.04, col = "grey55")

  nice_step <- function(r, n) {
    raw <- r / n; mag <- 10^floor(log10(raw)); q <- raw / mag
    s <- if (q < 1.5) 1 else if (q < 3) 2 else if (q < 7) 5 else 10
    s * mag
  }
  fmtbp <- function(v) {
    v <- round(v)
    if (abs(v) >= 1e6) sprintf("%.2f Mb", v / 1e6)
    else if (abs(v) >= 1e3) sprintf("%.0f kb", v / 1e3)
    else sprintf("%d bp", v)
  }
  Wpx  <- tryCatch(grDevices::dev.size("px")[1], error = function(e) 800)
  nlab <- max(3, min(10, floor(Wpx / 150)))
  s    <- nice_step(rng, nlab); sub <- s / 5
  at   <- seq(ceiling(vstart / sub) * sub, vend, by = sub)
  if (length(at)) {
    maj <- abs(at / s - round(at / s)) < 1e-6
    segments(at, 0.04, at, ifelse(maj, 0.45, 0.24),
             col = ifelse(maj, "grey25", "grey60"))
    gutfrac <- (66 + 8) / Wpx            # keep labels left of the y-ruler gutter
    ok <- maj & at <= vstart + (1 - gutfrac) * rng & at >= vstart + 0.03 * rng
    if (any(ok))
      text(at[ok], 0.55, vapply(at[ok], fmtbp, character(1)),
           adj = c(0.5, 0), cex = 0.95, col = "grey15")
  }
  # chromosome name pinned to the left edge
  text(vstart + 0.004 * rng, 0.55, chr, adj = c(0, 0),
       cex = 1.05, font = 2, col = "grey10")
  invisible(NULL)
}

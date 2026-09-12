# ============================================================================
# arcs.R  -  Arc track: significant interactions (HiChIP / ChIA-PET / loop calls)
#
# One interaction = two anchors on the same chromosome. Drawn as an arc hanging
# from the top edge of the track, with
#
#   x      the two anchor positions
#   y      the interaction DISTANCE on a log scale (so the apex height is
#          readable off a 10 kb / 100 kb / 1 Mb ruler). Distance spans five
#          orders of magnitude in real data, which is why it is not linear.
#   colour + width   the interaction STRENGTH, as a small number of DISCRETE
#          classes. One "strength" column drives both channels, so a reader
#          who cannot separate two shades still sees two thicknesses, and the
#          settings stay to two controls instead of six.
#
# Anchors are usually a few hundred bp, i.e. well under a pixel at Mb zoom, so
# an interaction is normally a LINE between anchor midpoints. Only when both
# anchors are at least `min_anchor_px` wide on screen is it drawn as a filled
# band between them, which then shows the anchors at their real width.
#
# Arcs whose partner anchor is outside the view are the bulk of what is on
# screen at any zoom (in the ChIA-PET sample, 660 of 684). Drawing them in full
# buries the interactions that actually close inside the view, so by default
# they are COLLAPSED: one representative per anchor and direction, at a fixed
# depth in a reserved "outside view" lane, carrying the strongest score of the
# group. `outgoing = "hide"` drops them entirely, "full" draws them as ordinary
# arcs.
#
# Geometry is a symmetric cubic Bezier, not a half-ellipse: an ellipse has a
# vertical tangent at its feet, which on a panel that is 900 x 110 px reads as
# a sharp corner at every anchor. The Bezier's control points are placed so
# that every arc leaves its anchor at the same on-screen angle (`foot_angle`),
# which also makes the printed figure match the screen at any page size.
# ============================================================================

suppressWarnings(suppressMessages({ library(data.table) }))

ARC_CACHE <- new.env(parent = emptyenv())

# ---------------------------------------------------------------------------
# Colour classes.
#
# ColorBrewer sequential ramps (colorbrewer2.org, Cynthia Brewer et al.,
# Apache License 2.0), stored as the 9-class version. They are designed for
# FILLED areas, and their three lightest steps are too pale for a thin line on
# white (contrast vs white 1.3-1.5:1, where ~2:1 is the floor), so a palette of
# n classes is taken from the DARK end: tail(ramp, n). At n = 5 even the
# lightest class clears 2.3:1.
#
# Multi-hue ramps (PuBu, YlGnBu, YlGn, YlOrRd, BuPu) separate classes better
# than single-hue ones (Blues, Greys) at line widths; Greys is kept for
# black-and-white printing. All of them have monotone lightness, so the class
# order survives greyscale and colour-vision deficiency - which is what makes a
# discrete ramp legitimate here where a rainbow would not be.
# ---------------------------------------------------------------------------
ARC_PALETTES <- list(
  PuBu   = c("#fff7fb","#ece7f2","#d0d1e6","#a6bddb","#74a9cf","#3690c0","#0570b0","#045a8d","#023858"),
  YlGnBu = c("#ffffd9","#edf8b1","#c7e9b4","#7fcdbb","#41b6c4","#1d91c0","#225ea8","#253494","#081d58"),
  YlGn   = c("#ffffe5","#f7fcb9","#d9f0a3","#addd8e","#78c679","#41ab5d","#238443","#006837","#004529"),
  YlOrRd = c("#ffffcc","#ffeda0","#fed976","#feb24c","#fd8d3c","#fc4e2a","#e31a1c","#bd0026","#800026"),
  BuPu   = c("#f7fcfd","#e0ecf4","#bfd3e6","#9ebcda","#8c96c6","#8c6bb1","#88419d","#810f7c","#4d004b"),
  Blues  = c("#f7fbff","#deebf7","#c6dbef","#9ecae1","#6baed6","#4292c6","#2171b5","#08519c","#08306b"),
  Greys  = c("#ffffff","#f0f0f0","#d9d9d9","#bdbdbd","#969696","#737373","#525252","#252525","#000000")
)
ARC_PALETTE_DEFAULT <- "PuBu"
ARC_NCLASS_DEFAULT  <- 5L
ARC_NCLASS_MAX      <- 7L

# n colours from the dark end of a ramp (see the note above).
arc_palette <- function(name = ARC_PALETTE_DEFAULT, n = ARC_NCLASS_DEFAULT) {
  n <- max(2L, min(ARC_NCLASS_MAX, as.integer(n)))
  p <- ARC_PALETTES[[name]]
  if (is.null(p)) p <- ARC_PALETTES[[ARC_PALETTE_DEFAULT]]
  utils::tail(p, n)
}

# Default widths: evenly spaced, floored at 1.2 px so the weakest class - which
# is the large majority of the data - recedes without disappearing.
arc_widths <- function(n = ARC_NCLASS_DEFAULT, lo = 1.2, hi = 3.6) {
  n <- max(2L, min(ARC_NCLASS_MAX, as.integer(n)))
  round(seq(lo, hi, length.out = n), 2)
}

# ---------------------------------------------------------------------------
# Reader
#
# One entry point for every interaction format we expect, because the file the
# user has is rarely the one the menu was written for. Detection order is:
# a name-carrying header first (Juicer / FitHiChIP / anything with chr1,start1,
# ...), then column count and column types.
#
# Returns data.frame(chr, s1, e1, s2, e2, score) for CIS interactions only,
# 1-based, with attributes:
#   arc_format   what it was recognised as
#   arc_trans    how many trans rows were dropped (75 % of a ChIA-PET file!)
#   arc_score    name/index of the column used as the strength
#   arc_count    TRUE when that column is an integer count (drives the default
#                class rule, and rules OUT a quantile scale - see the note in
#                arc_breaks())
# ---------------------------------------------------------------------------
ARC_COORD_ALIASES <- list(
  s1 = c("start1","x1","chromstart1","anchor1_start","s1"),
  e1 = c("end1","x2","chromend1","anchor1_end","e1"),
  s2 = c("start2","y1","chromstart2","anchor2_start","s2"),
  e2 = c("end2","y2","chromend2","anchor2_end","e2"),
  c1 = c("chr1","chrom1","chromosome1","#chr1","chr"),
  c2 = c("chr2","chrom2","chromosome2")
)
# strength columns, best first
ARC_SCORE_ALIASES <- c("score","pet","petcount","pet_count","o","observed","count",
                       "counts","value","fdr_bl","q-value","qvalue","q_value",
                       "p-value","pvalue","p_value")

.arc_norm <- function(x) tolower(trimws(gsub("^#", "", as.character(x))))

.arc_find <- function(nms, aliases) {
  i <- match(aliases, nms)
  i <- i[!is.na(i)]
  if (length(i)) i[1] else NA_integer_
}

# Is this column an integer-valued count?
.arc_is_count <- function(v) {
  v <- v[is.finite(v)]
  length(v) > 0 && all(abs(v - round(v)) < 1e-9) && min(v) >= 0
}

# Does this column look like a probability (p-value, q-value, FDR)?
#
# Tested on the VALUES, not the column name. A headerless BEDPE calls its
# strength column "8", and judging by name alone left a raw p-value column
# reading backwards - the least significant interaction came out the darkest
# and thickest. Anything whose values all sit in [0,1] with more than a couple
# of distinct levels is a probability in practice; a count or a contact score
# never looks like that.
.arc_is_prob <- function(v) {
  v <- v[is.finite(v)]
  length(unique(v)) > 2 && all(v >= 0) && all(v <= 1)
}

# Is there a usable strength column at all? A 6-column BEDPE has none, and a
# file where every interaction carries the same number has one in name only.
arc_has_score <- function(df) {
  v <- df$score[is.finite(df$score)]
  length(unique(v)) > 1
}

# `score_dir` says which end of the strength column means "strong":
#   "auto"  probability-looking columns are inverted, everything else is not
#   "up"    use the numbers as they are (bigger = stronger)
#   "down"  force the inversion (smaller = stronger)
# It is exposed in the settings dialog because "auto" is a guess, and a guess
# that silently reverses the meaning of a figure is not one to leave unattended.
read_arcs <- function(path, score_col = NULL, score_dir = "auto") {
  if (!score_dir %in% c("auto", "up", "down")) score_dir <- "auto"
  key <- paste0(path, "\r", if (is.null(score_col)) "" else score_col, "\r", score_dir)
  if (!is.null(ARC_CACHE[[key]])) return(ARC_CACHE[[key]])

  d <- data.table::fread(path, header = FALSE, sep = "\t",
                         na.strings = c("NA", "", "NaN", "."), showProgress = FALSE)
  if (ncol(d) < 6)
    stop(sprintf("An interaction file needs at least 6 columns (chr1 start1 end1 chr2 start2 end2); got %d in %s",
                 ncol(d), basename(path)))

  # A header line survives header = FALSE as the first data row, and is spotted
  # by column 2 not being a number there. Re-read with names in that case.
  hdr <- !is.numeric(d[[2]])
  if (hdr) {
    nms <- .arc_norm(unlist(d[1, ], use.names = FALSE))
    d   <- d[-1, ]
    for (j in seq_len(ncol(d))) {
      v <- suppressWarnings(as.numeric(d[[j]]))
      if (!all(is.na(v))) data.table::set(d, j = j, value = v)
    }
    data.table::setnames(d, seq_along(nms), make.unique(nms))
  } else {
    nms <- rep("", ncol(d))
  }

  # ---- coordinate columns ------------------------------------------------
  ix <- if (hdr) vapply(ARC_COORD_ALIASES, function(a) .arc_find(nms, a), integer(1))
        else stats::setNames(c(2L, 3L, 5L, 6L, 1L, 4L), c("s1","e1","s2","e2","c1","c2"))
  if (anyNA(ix)) ix <- stats::setNames(c(2L, 3L, 5L, 6L, 1L, 4L), c("s1","e1","s2","e2","c1","c2"))

  # ---- which column is the strength --------------------------------------
  fmt <- "BEDPE"
  si  <- NA_integer_
  if (!is.null(score_col) && nzchar(as.character(score_col))) {
    sc <- suppressWarnings(as.integer(score_col))
    si <- if (!is.na(sc)) sc else .arc_find(nms, .arc_norm(score_col))
    fmt <- "manual score column"
  } else if (hdr) {
    si  <- .arc_find(nms, ARC_SCORE_ALIASES)
    fmt <- if (any(c("fdr_bl","e_bl") %in% nms)) "Juicer HiCCUPS"
           else if (any(grepl("^q.?value$", nms))) "FitHiChIP"
           else "BEDPE (with header)"
  } else if (ncol(d) >= 15 && .arc_is_count(d[[7]]) &&
             all(stats::na.omit(unique(d[[8]])) %in% c(0, 1)) &&
             is.numeric(d[[12]]) && max(d[[12]], na.rm = TRUE) <= 1) {
    # ChIA-PET Tool cluster output: PET count in 7, cis/trans flag in 8,
    # p / FDR in 12-13, -log10 of each in 14-15.
    si  <- 7L
    fmt <- "ChIA-PET cluster"
  } else if (ncol(d) >= 8 && is.numeric(d[[8]])) {
    si <- 8L                                   # BEDPE spec: name in 7, score in 8
  } else if (ncol(d) == 7 && is.numeric(d[[7]])) {
    si <- 7L
  }

  has_sc <- !is.na(si) && si >= 1 && si <= ncol(d)
  score  <- if (has_sc) suppressWarnings(as.numeric(d[[si]])) else rep(1, nrow(d))
  snm    <- if (!has_sc) NA_character_ else if (hdr) nms[si] else paste0("column ", si)

  # "small is strong" columns (p / q / FDR) have to be turned round, or the
  # least significant interaction ends up the darkest and thickest one.
  if (has_sc) {
    inv <- switch(score_dir, up = FALSE, down = TRUE, .arc_is_prob(score))
    if (inv) {
      if (all(score >= 0 & score <= 1, na.rm = TRUE)) {
        # pmax() keeps a reported p of exactly 0 (underflow) finite
        score <- -log10(pmax(score, 1e-300))
        snm   <- paste0("-log10(", snm, ")")
      } else {
        score <- suppressWarnings(max(score, na.rm = TRUE)) - score
        snm   <- paste0("max - ", snm)
      }
    }
  }
  score[!is.finite(score)] <- 0

  out <- data.frame(
    chr  = as.character(d[[ix[["c1"]]]]),
    chr2 = as.character(d[[ix[["c2"]]]]),
    # BED-style coordinates are 0-based half-open; shift the starts so anchor
    # positions line up with the 1-based contact map.
    s1 = as.numeric(d[[ix[["s1"]]]]) + 1, e1 = as.numeric(d[[ix[["e1"]]]]),
    s2 = as.numeric(d[[ix[["s2"]]]]) + 1, e2 = as.numeric(d[[ix[["e2"]]]]),
    score = score, stringsAsFactors = FALSE)

  ok  <- is.finite(out$s1) & is.finite(out$e1) & is.finite(out$s2) & is.finite(out$e2)
  out <- out[ok, , drop = FALSE]
  ntr <- sum(out$chr != out$chr2)
  out <- out[out$chr == out$chr2, , drop = FALSE]
  out$chr2 <- NULL

  # always store anchor 1 to the left, so s1 < s2 and the arc geometry below
  # never has to test the order
  sw <- out$s1 > out$s2
  if (any(sw)) {
    tmp <- out[sw, c("s1","e1")]
    out[sw, c("s1","e1")] <- out[sw, c("s2","e2")]
    out[sw, c("s2","e2")] <- tmp
  }
  out <- out[order(out$chr, out$s1), , drop = FALSE]
  rownames(out) <- NULL

  attr(out, "arc_format") <- fmt
  attr(out, "arc_trans")  <- ntr
  attr(out, "arc_score")  <- if (is.na(snm)) "(none)" else snm
  attr(out, "arc_hasscore") <- length(unique(out$score[is.finite(out$score)])) > 1
  attr(out, "arc_count")  <- .arc_is_count(out$score) && length(unique(out$score)) <= 200
  ARC_CACHE[[key]] <- out
  out
}

# Re-point the chromosome names at the ones the rest of the app uses
# (a BEDPE says "chr1" where a pombe .hic says "I"), and report what could not
# be matched - a silently empty track is the worst possible failure here.
arc_match_chrom <- function(df, chroms) {
  if (is.null(chroms) || length(chroms) == 0 || nrow(df) == 0) return(df)
  known <- names(chroms)
  miss  <- setdiff(unique(df$chr), known)
  if (length(miss)) {
    cand <- function(x) c(sub("^chr", "", x), paste0("chr", x))
    for (m in miss) {
      hit <- intersect(cand(m), known)
      if (length(hit)) df$chr[df$chr == m] <- hit[1]
    }
  }
  attr(df, "arc_unmatched") <- setdiff(unique(df$chr), known)
  df
}

# ---------------------------------------------------------------------------
# Class breaks. `breaks` is a vector of n ascending LOWER bounds; a value falls
# in class findInterval(v, breaks), and the top class is open-ended.
#
# "quantile" is deliberately NOT offered. In the ChIA-PET sample 83 % of
# interactions have exactly the minimum PET count, so they all share one rank,
# that rank lands mid-scale, and the weakest interactions come out painted as
# mid-strength. Equal-count classing is a trap for tied integer counts.
# ---------------------------------------------------------------------------
arc_breaks <- function(score, n = ARC_NCLASS_DEFAULT, rule = "auto", is_count = NA) {
  n <- max(2L, min(ARC_NCLASS_MAX, as.integer(n)))
  s <- score[is.finite(score)]
  if (length(s) == 0) return(seq_len(n))
  lo <- min(s); hi <- max(s)
  if (is.na(is_count)) is_count <- .arc_is_count(s)
  if (identical(rule, "auto")) {
    # For a count, step by 1 from the minimum and let the top class swallow the
    # tail: PET counts run 2..980 but the 99th percentile is 14, so integer
    # classes put the boundaries where the data actually is. Only when even the
    # bulk of the counts is spread over a wide range does a log ruler win.
    spread <- suppressWarnings(as.numeric(stats::quantile(s, 0.99, names = FALSE)) - lo)
    rule <- if (is_count && is.finite(spread) && spread <= 3 * n) "integer"
            else if (lo > 0) "log" else "equal"
  }
  br <- switch(rule,
    integer = lo + seq_len(n) - 1,
    log     = { a <- log10(max(lo, .Machine$double.eps)); b <- log10(max(hi, lo * 1.0001))
                10^seq(a, b, length.out = n + 1)[seq_len(n)] },
    equal   = seq(lo, hi, length.out = n + 1)[seq_len(n)],
    lo + seq_len(n) - 1)
  br <- sort(unique(round(br, 6)))
  if (length(br) < n) br <- c(br, br[length(br)] + seq_len(n - length(br)))
  br[seq_len(n)]
}

arc_class <- function(score, breaks)
  pmin(length(breaks), pmax(1L, findInterval(score, breaks)))

arc_break_labels <- function(breaks) {
  n <- length(breaks)
  intlike <- all(abs(breaks - round(breaks)) < 1e-9) &&
             (n < 2 || all(abs(diff(breaks) - 1) < 1e-9))
  f <- function(v) if (abs(v - round(v)) < 1e-9) format(round(v)) else formatC(v, format = "g", digits = 3)
  if (intlike) c(vapply(breaks[-n], f, ""), paste0("≥", f(breaks[n])))
  else c(vapply(seq_len(n - 1), function(i) paste0(f(breaks[i]), "-", f(breaks[i + 1])), ""),
         paste0("≥", f(breaks[n])))
}

# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

# Symmetric cubic Bezier from (a,0) to (b,0) with apex h. Control points sit at
# height H = 4h/3 (so the curve peaks at exactly h) and k*(b-a) in from each
# foot. Unlike a half-ellipse the slope at the foot, H/(k(b-a)), is finite -
# that is the whole reason for using it.
.arc_bezier <- function(a, b, h, k, n = 120L) {
  H  <- h / 0.75
  px <- c(a, a + k * (b - a), b - k * (b - a), b)
  py <- c(0, H, H, 0)
  t  <- seq(0, 1, length.out = n)
  B  <- cbind((1 - t)^3, 3 * (1 - t)^2 * t, 3 * (1 - t) * t^2, t^3)
  list(x = as.vector(B %*% px), y = as.vector(B %*% py))
}

# k such that the arc leaves its foot at `deg` degrees ON SCREEN. Solving for
# the angle rather than fixing k keeps long and short interactions looking
# alike, and makes the exported figure match the screen at any page size.
# Above ~0.45 the Bezier's x stops being monotone and the curve self-crosses.
.arc_k <- function(a, b, h, bp_per_px, unit_per_px, deg = 60) {
  dx <- abs(b - a) / bp_per_px
  dy <- abs(h) / unit_per_px
  if (!is.finite(dx) || dx <= 0) return(0.33)
  min(0.45, max(0.06, 4 * dy / (3 * tan(deg * pi / 180) * dx)))
}

# ---------------------------------------------------------------------------
# plot_arc_track()
#
# Same signature shape as plot_bs_track() / plot_gene_track() so app.R's track
# dispatch stays a one-line branch.
# ---------------------------------------------------------------------------
plot_arc_track <- function(df, chr, vstart, vend, chrlen = Inf, name = "arcs",
                           palette = ARC_PALETTE_DEFAULT, nclass = ARC_NCLASS_DEFAULT,
                           breaks = NULL, colors = NULL, widths = NULL, color = NULL,
                           break_rule = "auto",
                           alpha = 0.85,
                           span_lo = NULL, span_hi = NULL,
                           span_min = 0, span_max = Inf, score_min = -Inf,
                           outgoing = "collapse",
                           min_anchor_px = 3, foot_angle = 60, hook_px = 150,
                           max_arcs = 2000, orientation = "down",
                           mar = c(0.3, 0, 0.3, 0), frame = TRUE,
                           yscale = "inline", legend = TRUE) {
  op <- par(mar = mar, xpd = FALSE); on.exit(par(op))
  collapse <- identical(outgoing, "collapse")

  # distance axis occupies the top part of the panel; the rest is the lane the
  # collapsed "leaves the view" marks live in
  TOPF <- if (collapse) 0.80 else 0.96
  OUTF <- 0.93
  # the bottom ~10 % is the label / class-key row (the top edge is where every
  # anchor sits, so there is nowhere to put text up there)
  YLAB <- 1.04
  ylim <- if (identical(orientation, "up")) c(-0.02, 1.12) else c(1.12, -0.02)
  plot(NA, xlim = c(vstart, vend), ylim = ylim,
       xaxs = "i", yaxs = "i", axes = FALSE, ann = FALSE)

  # px geometry of THIS panel (par("pin") is in inches; the ratio converts it),
  # needed before any arc can be drawn because foot_angle is an on-screen angle
  dsz  <- tryCatch(grDevices::dev.size("px"), error = function(e) c(900, 600))
  din  <- tryCatch(grDevices::dev.size("in"), error = function(e) c(9, 6))
  ppi  <- if (is.finite(din[1]) && din[1] > 0) dsz[1] / din[1] else 96
  wpx  <- max(50, par("pin")[1] * ppi)
  hpx  <- max(20, par("pin")[2] * ppi)
  bp_per_px   <- (vend - vstart) / wpx
  unit_per_px <- abs(diff(ylim)) / hpx

  # Reference range for the distance ruler.
  #
  # `span_min` / `span_max` set BOTH what is drawn and where the axis ends, so
  # there is one pair of numbers rather than two that can disagree. Setting the
  # maximum distance to 5 Mb therefore also puts 5 Mb at the far end of the
  # axis - which is what anyone who reaches for a "max" expects it to do.
  #
  # Left blank, the ruler is two whole decades keyed to the VIEW WIDTH. Fixing
  # it to the data would make a deep zoom useless (every interaction left in
  # view is short, so every arc comes out flat); fitting it to the view would
  # make the picture jitter while panning. Decades keyed to the view width give
  # both: panning never changes it, and a deliberate zoom re-bases it one
  # decade at a time. Two decades because anything shorter than 1 % of the view
  # is a pixel or two wide anyway, so giving it axis room is waste. The
  # gridlines are labelled, so the reader always knows which ruler they read.
  if (is.null(span_hi) || !is.finite(span_hi) || span_hi <= 0)
    span_hi <- if (is.finite(span_max) && span_max > 0) span_max
               else 10^ceiling(log10(max(1e4, vend - vstart)))
  if (is.null(span_lo) || !is.finite(span_lo) || span_lo <= 0)
    span_lo <- if (is.finite(span_min) && span_min > 0) span_min else span_hi / 1e2
  if (span_lo >= span_hi) span_lo <- span_hi / 10

  hsp <- function(sp) {
    v <- (log10(pmax(sp, 1)) - log10(span_lo)) / (log10(span_hi) - log10(span_lo))
    pmin(TOPF, pmax(0.03, v * TOPF))
  }

  # ---- select: at least one anchor overlapping the view --------------------
  sub <- df[df$chr == chr, , drop = FALSE]
  a1in <- sub$e1 >= vstart & sub$s1 <= vend
  a2in <- sub$e2 >= vstart & sub$s2 <= vend
  sub  <- sub[a1in | a2in, , drop = FALSE]
  a1in <- sub$e1 >= vstart & sub$s1 <= vend
  a2in <- sub$e2 >= vstart & sub$s2 <= vend

  if (nrow(sub)) {
    span <- sub$e2 - sub$s1
    keep <- span >= span_min & span <= span_max & sub$score >= score_min
    sub <- sub[keep, , drop = FALSE]; a1in <- a1in[keep]; a2in <- a2in[keep]
  }
  both <- a1in & a2in
  if (identical(outgoing, "hide") && nrow(sub)) {
    sub <- sub[both, , drop = FALSE]; a1in <- a1in[both]; a2in <- a2in[both]; both <- both[both]
  }

  # ---- classes -------------------------------------------------------------
  # A file with no strength column - or one where every interaction carries the
  # same number - has nothing to class. Splitting it into five classes anyway
  # would paint everything the palest, thinnest one and print a key listing
  # four classes that do not exist, so it collapses to a single style instead:
  # the colour picked when the track was added, or the darkest palette step.
  has_score <- isTRUE(attr(df, "arc_hasscore")) ||
               (is.null(attr(df, "arc_hasscore")) && length(unique(df$score)) > 1)
  if (!has_score) {
    breaks  <- 0
    nclass  <- 1L
    colors  <- if (!is.null(color) && nzchar(color)) color
               else utils::tail(arc_palette(palette, ARC_NCLASS_DEFAULT), 1)
    widths  <- 1.8
    legend  <- FALSE
  } else {
    nclass <- max(2L, min(ARC_NCLASS_MAX, as.integer(nclass)))
    if (is.null(breaks) || length(breaks) < 2)
      breaks <- arc_breaks(df$score, nclass, break_rule, attr(df, "arc_count"))
    breaks <- sort(as.numeric(breaks))[seq_len(min(nclass, length(breaks)))]
    nclass <- length(breaks)
    if (is.null(colors) || length(colors) != nclass) colors <- arc_palette(palette, nclass)
    if (is.null(widths) || length(widths) != nclass) widths <- arc_widths(nclass)
  }
  colA <- grDevices::adjustcolor(colors, alpha.f = alpha)

  draw_arc <- function(a, b, h, col, lw) {
    k  <- .arc_k(a, b, h, bp_per_px, unit_per_px, foot_angle)
    bz <- .arc_bezier(a, b, h, k)
    lines(bz$x, bz$y, col = col, lwd = lw, lend = 1)
  }
  draw_band <- function(s1, e1, s2, e2, h, col) {
    ro <- (e2 - s1) / 2; ri <- (s2 - e1) / 2
    k  <- .arc_k(s1, e2, h, bp_per_px, unit_per_px, foot_angle)
    hi <- min(h * (ri / ro), h - 1.5 * unit_per_px)     # >= 1.5 px thick at the apex
    o  <- .arc_bezier(s1, e2, h,  k)
    i  <- .arc_bezier(e1, s2, hi, k)
    polygon(c(o$x, rev(i$x)), c(o$y, rev(i$y)), col = col, border = NA)
  }

  ndrawn <- 0L; ntotal <- nrow(sub)
  inv <- sub[both, , drop = FALSE]
  if (nrow(inv)) {
    inv <- inv[order(-(inv$e2 - inv$s1)), , drop = FALSE]   # big arcs behind
    if (nrow(inv) > max_arcs) inv <- inv[order(-inv$score)[seq_len(max_arcs)], , drop = FALSE]
    cl <- arc_class(inv$score, breaks)
    h  <- hsp(inv$e2 - inv$s1)
    wide <- pmin(inv$e1 - inv$s1, inv$e2 - inv$s2) / bp_per_px >= min_anchor_px & inv$e1 < inv$s2
    for (r in seq_len(nrow(inv))) {
      if (wide[r]) draw_band(inv$s1[r], inv$e1[r], inv$s2[r], inv$e2[r], h[r], colA[cl[r]])
      else draw_arc((inv$s1[r] + inv$e1[r]) / 2, (inv$s2[r] + inv$e2[r]) / 2,
                    h[r], colA[cl[r]], widths[cl[r]])
    }
    ndrawn <- nrow(inv)
  }

  # ---- interactions leaving the view ---------------------------------------
  nrep <- 0L
  og <- sub[!both, , drop = FALSE]
  if (collapse && nrow(og)) {
    li <- og$e1 >= vstart & og$s1 <= vend        # anchor 1 is the one in view
    a0 <- ifelse(li, og$s1, og$s2)
    a1 <- ifelse(li, og$e1, og$e2)
    dr <- ifelse(li, 1L, -1L)                    # anchor 1 in view -> partner is to the right
    o  <- order(dr, a0)
    a0 <- a0[o]; a1 <- a1[o]; dr <- dr[o]; sc <- og$score[o]
    # merge anchors that are closer together than one pixel: what the eye
    # cannot separate should not be drawn twice
    mb  <- bp_per_px
    new <- c(TRUE, dr[-1] != dr[-length(dr)] |
                   a0[-1] > cummax(a1)[-length(a1)] + mb)
    g   <- cumsum(new)
    cen <- (tapply(a0, g, min) + tapply(a1, g, max)) / 2
    dgr <- tapply(dr, g, `[`, 1)
    smx <- tapply(sc, g, max)                    # the group's strongest, as asked
    cl  <- arc_class(as.numeric(smx), breaks)
    nrep <- length(cen)
    for (i in seq_along(cen)) {
      a <- as.numeric(cen[i]); d <- as.numeric(dgr[i])
      b <- a + d * hook_px * bp_per_px
      k <- .arc_k(a, b, OUTF, bp_per_px, unit_per_px, foot_angle)
      bz <- .arc_bezier(a, b, OUTF, k)
      m  <- ceiling(length(bz$x) / 2)
      lines(bz$x[seq_len(m)], bz$y[seq_len(m)], col = colA[cl[i]], lwd = widths[cl[i]], lend = 1)
      xe <- a + d * hook_px * 0.9 * bp_per_px
      segments(bz$x[m], OUTF, xe, OUTF, col = colA[cl[i]], lwd = widths[cl[i]], lend = 1)
      ah <- 4 * bp_per_px + widths[cl[i]] * bp_per_px
      polygon(c(xe, xe - d * ah, xe - d * ah),
              c(OUTF, OUTF - 2.2 * unit_per_px - widths[cl[i]] * unit_per_px,
                       OUTF + 2.2 * unit_per_px + widths[cl[i]] * unit_per_px),
              col = colA[cl[i]], border = NA)
    }
    ndrawn <- ndrawn + nrep
  } else if (identical(outgoing, "full") && nrow(og)) {
    og <- og[order(-(og$e2 - og$s1)), , drop = FALSE]
    if (nrow(og) > max_arcs) og <- og[order(-og$score)[seq_len(max_arcs)], , drop = FALSE]
    cl <- arc_class(og$score, breaks)
    h  <- hsp(og$e2 - og$s1)
    for (r in seq_len(nrow(og)))
      draw_arc((og$s1[r] + og$e1[r]) / 2, (og$s2[r] + og$e2[r]) / 2,
               h[r], colA[cl[r]], widths[cl[r]])
    ndrawn <- ndrawn + nrow(og)
  }

  # ---- distance ruler ------------------------------------------------------
  fmtbp <- function(v) if (v >= 1e6) sprintf("%g Mb", v / 1e6)
                       else if (v >= 1e3) sprintf("%g kb", v / 1e3) else sprintf("%g bp", v)
  dec <- 10^seq(floor(log10(span_lo)), ceiling(log10(span_hi)))
  # interior decades only: a label sitting exactly on the top edge or on the
  # lane rule collides with them
  dec <- dec[dec > span_lo & dec < span_hi]
  for (d in dec) {
    yy <- hsp(d)
    segments(vstart, yy, vend, yy, col = "#d8d8d3", lwd = 0.6)
    # centred on its own line: an offset label clips against the panel edge as
    # soon as a decade lands near the top of the ruler
    if (!identical(yscale, "axis") && yy > 0.06)
      text(vstart + 0.003 * (vend - vstart), yy, fmtbp(d),
           adj = c(0, 0.5), cex = 0.75, col = "#7a7a74")
  }
  if (identical(yscale, "axis") && length(dec)) {
    # print style: a real left axis, with the same tick length (tcl) the map
    # and the other tracks use so they line up down the page. The axis is the
    # interaction DISTANCE, which is the whole reason the arc heights are
    # worth reading at all.
    axis(2, at = hsp(dec), labels = vapply(dec, fmtbp, ""), las = 1,
         tcl = -0.4, mgp = c(3, 0.5, 0), cex.axis = 0.8,
         col = "grey40", col.axis = "grey20")
  }
  if (collapse) {
    yy <- (TOPF + OUTF) / 2
    segments(vstart, yy, vend, yy, col = "#b0b0aa", lwd = 0.7, lty = 2)
  }

  # ---- name, counts and class key -----------------------------------------
  ybot <- YLAB          # always the far end from the baseline
  vadj <- 0.5
  lab <- name
  if (ntotal > ndrawn || nrep > 0)
    lab <- sprintf("%s  (%d of %d%s)", name, ndrawn, ntotal,
                   if (nrep > 0) sprintf(", %d out-of-view", nrep) else "")
  text(vstart + 0.005 * (vend - vstart), ybot, lab, adj = c(0, vadj),
       cex = 1.05, col = "grey20")
  if (isTRUE(legend) && nclass >= 2) {
    labs <- arc_break_labels(breaks)
    seg  <- 0.018 * (vend - vstart)
    gap  <- 0.008 * (vend - vstart)
    wds  <- strwidth(labs, cex = 0.72) + seg + gap * 1.6
    x    <- vend - 0.006 * (vend - vstart) - sum(wds)
    for (i in seq_len(nclass)) {
      segments(x, ybot, x + seg, ybot, col = colors[i], lwd = widths[i], lend = 1)
      text(x + seg + gap * 0.4, ybot, labs[i], adj = c(0, vadj), cex = 0.72, col = "grey25")
      x <- x + wds[i]
    }
  }
  if (isTRUE(frame)) box(col = "grey85")
  invisible(list(drawn = ndrawn, total = ntotal, out_of_view = nrep, breaks = breaks))
}

# ---------------------------------------------------------------------------
# Score distribution for the settings dialog. Showing the histogram with the
# class boundaries on it is the whole answer to "where should I cut?" - the
# ChIA-PET sample puts 83 % of its mass in one bar, which no amount of guessing
# at numbers would reveal.
# ---------------------------------------------------------------------------
plot_arc_hist <- function(df, breaks = NULL, colors = NULL,
                          mar = c(2.2, 2.2, 0.6, 0.6)) {
  op <- par(mar = mar); on.exit(par(op))
  s <- df$score[is.finite(df$score)]
  if (length(s) == 0) { plot.new(); return(invisible(NULL)) }
  logx <- min(s) > 0 && diff(range(s)) > 50
  v <- if (logx) log10(s) else s
  h <- hist(v, breaks = 40, plot = FALSE)
  plot(h, main = "", xlab = "", ylab = "", col = "grey85", border = "grey60",
       axes = FALSE, freq = TRUE)
  at <- pretty(v, 5)
  axis(1, at = at, labels = if (logx) formatC(10^at, format = "g", digits = 3) else formatC(at, format = "g", digits = 3),
       cex.axis = 0.7, tcl = -0.3, mgp = c(3, 0.3, 0), col = "grey50")
  axis(2, cex.axis = 0.7, las = 1, tcl = -0.3, mgp = c(3, 0.4, 0), col = "grey50")
  mtext(if (logx) "score (log scale)" else "score", side = 1, line = 1.2, cex = 0.75)
  if (!is.null(breaks)) {
    bv <- if (logx) log10(pmax(breaks, 1e-300)) else breaks
    if (is.null(colors) || length(colors) != length(breaks))
      colors <- arc_palette(ARC_PALETTE_DEFAULT, length(breaks))
    abline(v = bv, col = colors, lwd = 2)
  }
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Small parsers for the settings dialog, where breaks / colours / widths are
# edited as comma-separated lists. Keeping them here means app.R never has to
# know how a class list is spelled.
# ---------------------------------------------------------------------------
arc_parse_num <- function(x) {
  v <- suppressWarnings(as.numeric(trimws(strsplit(paste(as.character(x), collapse = ","),
                                                   "[,;[:space:]]+")[[1]])))
  v[is.finite(v)]
}
arc_parse_col <- function(x) {
  v <- trimws(strsplit(paste(as.character(x), collapse = ","), "[,;[:space:]]+")[[1]])
  v[nzchar(v)]
}

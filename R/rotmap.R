# ============================================================================
# rotmap.R  -  45-degree rotated Hi-C contact map, drawn as a TRACK
#
# The main view is a square matrix in a Leaflet pane. This draws the same data
# the other way round: x = genomic position, y = the separation between the two
# bins. A TAD becomes a triangle sitting on the position axis, which lines up
# directly with the bigWig / gene / arc tracks below it.
#
# The geometry is the one hicdraw's getRotate() uses (H:\work\Library\hicdraw):
# the bin pair (i, j = i+k) is a diamond centred at
#     x = start_i + res * (k + 1) / 2        y = k * res
# with half-width res/2 (in x) and half-height res (in y).
#
# Two ways to put that on screen, and the right one depends on the zoom:
#
#   polygon  every diamond as a real polygon. Crisp edges and true vector
#            output in a PDF, but the cost is proportional to the number of
#            diamonds (measured: 51k -> 60 ms, 1.26M -> 1250 ms).
#   raster   invert the mapping instead: for each PIXEL work out which bin pair
#            sits under it and look the value up. The cost is the pixel count
#            alone - 50-65 ms for 1200x300 whatever the resolution - but the
#            diamond edges come out slightly stepped when a bin is many pixels
#            wide.
#
# So: polygon while a bin is at least ROT_POLY_PX pixels across, raster below
# that. Both were checked to give the same picture in the overlapping range.
#
# Data is held as a BAND matrix B[i, k+1] = contact between bin i and bin i+k,
# k = 0..K. The full square would be 19-50 MB for a typical view; the band is
# a few MB, and the inverse mapping above reads straight out of it.
# ============================================================================

ROT_TARGET_PX  <- 1200      # bins across the panel when the resolution is auto
ROT_POLY_PX    <- 3         # bin width (px) at or above which polygons are used
ROT_POLY_MAX   <- 200000    # never draw more polygons than this (screen)
ROT_POLY_MAX_V <- 200000    # ... nor in a vector export
ROT_BAND_MAX   <- 6e6       # band cells; coarsen the resolution rather than exceed
ROT_RASTER_MAX <- 2400      # cap the raster's width/height in px
ROT_DMAX_FRAC  <- 0.25      # default distance ceiling = view width / 4

# ---------------------------------------------------------------------------
# small LRU cache: panning re-reads the same band over and over otherwise
# ---------------------------------------------------------------------------
.rot_cache <- new.env(parent = emptyenv())
.rot_cache$keys <- character(0)
.rot_cache$vals <- list()
.ROT_CACHE_N <- 6L

.rot_cache_get <- function(key) {
  i <- match(key, .rot_cache$keys)
  if (is.na(i)) return(NULL)
  # move to the front (most recently used)
  v <- .rot_cache$vals[[i]]
  .rot_cache$keys <- c(key, .rot_cache$keys[-i])
  .rot_cache$vals <- c(list(v), .rot_cache$vals[-i])
  v
}
.rot_cache_put <- function(key, val) {
  .rot_cache$keys <- c(key, .rot_cache$keys)
  .rot_cache$vals <- c(list(val), .rot_cache$vals)
  if (length(.rot_cache$keys) > .ROT_CACHE_N) {
    .rot_cache$keys <- .rot_cache$keys[seq_len(.ROT_CACHE_N)]
    .rot_cache$vals <- .rot_cache$vals[seq_len(.ROT_CACHE_N)]
  }
  invisible(val)
}
rot_forget <- function() {
  .rot_cache$keys <- character(0); .rot_cache$vals <- list(); invisible(TRUE)
}

# ---------------------------------------------------------------------------
# rot_auto_height(): panel height in px that makes the picture a TRUE 45-degree
# rotation - i.e. a bin appears as a square turned on its corner rather than a
# diamond stretched vertically.
#
#   half-width  of a bin on screen = (res/2) / ((vend-vstart)/W_px)
#   half-height of a bin on screen = res      / (dmax/H_px)
#   equal  =>  H_px = dmax * W_px / (2 * (vend - vstart))
#
# Deliberately NOT applied automatically: the height would then change on every
# zoom, which makes the track stack jump around. It is a button.
# ---------------------------------------------------------------------------
rot_auto_height <- function(vstart, vend, dmax, width_px = 900) {
  w <- as.numeric(vend) - as.numeric(vstart)
  if (!is.finite(w) || w <= 0 || !is.finite(dmax) || dmax <= 0) return(NA_real_)
  h <- dmax * width_px / (2 * w)
  max(40, min(1200, round(h)))
}

# default distance ceiling for a view, snapped to something round
rot_default_dmax <- function(vstart, vend) {
  w <- as.numeric(vend) - as.numeric(vstart)
  if (!is.finite(w) || w <= 0) return(1e5)
  d <- w * ROT_DMAX_FRAC
  signif(d, 1)
}

# resolutions this file offers for this chromosome (ascending), or NULL
rot_resolutions <- function(path, chr, norm = "NONE") {
  r <- tryCatch(hic_resolutions_chr(path, chr, norm, chr), error = function(e) NULL)
  if (is.null(r) || !length(r)) r <- tryCatch(hic_resolutions(path), error = function(e) NULL)
  if (is.null(r) || !length(r)) return(NULL)
  sort(unique(as.numeric(r)))
}

# ---------------------------------------------------------------------------
# read_rot_band(): the diagonal band of the contact matrix for one view.
#
# The panel is filled from x = vstart to x = vend, but a pair separated by
# `dmax` is drawn at the MIDPOINT of its two bins, so the left edge of the
# panel needs data from vstart - dmax/2 and the right edge up to vend + dmax/2.
# Read less than that and the two upper corners of the triangle come out empty
# (see rot_track_margin.png in the feasibility note).
#
# Returns list(B, lstart, res, K, n, chr, norm) or NULL. `B[i, k+1]` is the
# contact between bin i (starting at lstart + (i-1)*res) and bin i+k.
# ---------------------------------------------------------------------------
read_rot_band <- function(path, chr, vstart, vend, dmax,
                          res = NULL, norm = "NONE", chrlen = Inf,
                          target_px = ROT_TARGET_PX) {
  vstart <- as.numeric(vstart); vend <- as.numeric(vend)
  dmax   <- as.numeric(dmax)
  if (!is.finite(vstart) || !is.finite(vend) || vend <= vstart) return(NULL)
  if (!is.finite(dmax) || dmax <= 0) dmax <- rot_default_dmax(vstart, vend)

  # the file's own spelling of the chromosome ("chr2" here vs "2" in the file).
  # hic_chroms() returns a data.frame(name, length[, index]).
  info  <- tryCatch(hic_chroms(path), error = function(e) NULL)
  chrf  <- if (is.null(info) || is.null(info$name)) as.character(chr)[1]
           else match_chrom(chr, info$name)
  if (length(chrf) != 1 || is.na(chrf)) return(structure(list(), rot_reason = "chrom"))
  if (!is.finite(chrlen) && !is.null(info$length)) {
    cl <- suppressWarnings(as.numeric(info$length[info$name == chrf])[1])
    if (length(cl) == 1 && is.finite(cl)) chrlen <- cl
  }

  avail <- rot_resolutions(path, chrf, norm)
  if (is.null(avail)) return(structure(list(), rot_reason = "res"))
  r <- if (!is.null(res) && length(res) == 1 && is.finite(res) && res > 0)
         avail[which.min(abs(avail - res))]
       else
         choose_res((vend - vstart) / max(100, target_px), avail)

  lstart <- max(1, floor(vstart - dmax / 2))
  lend   <- ceiling(vend + dmax / 2)
  if (is.finite(chrlen)) lend <- min(lend, chrlen)
  if (lend <= lstart) return(NULL)

  # Memory guard: rather than refuse, step up to a coarser resolution until the
  # band fits. A view that asks for more than this is one where a single bin is
  # well under a pixel anyway, so nothing visible is lost.
  cells <- function(rr) (ceiling((lend - lstart) / rr) + 1) * (ceiling(dmax / rr) + 1)
  while (cells(r) > ROT_BAND_MAX) {
    nxt <- avail[avail > r]
    if (!length(nxt)) break
    r <- min(nxt)
  }

  key <- paste(path, chrf, lstart, lend, r, norm, sep = "|")
  hit <- .rot_cache_get(key)
  if (!is.null(hit)) return(hit)

  # bin grid: bin i covers [lstart0 + (i-1)*r, lstart0 + i*r)
  lstart0 <- floor((lstart - 1) / r) * r          # snap to the file's bin grid
  n <- as.integer(floor((lend - lstart0) / r)) + 1L
  K <- as.integer(ceiling(dmax / r))
  if (n < 1L || K < 0L) return(NULL)

  nrm <- if (identical(norm, "NONE")) "NONE" else {
    av <- tryCatch(hic_norms(path), error = function(e) "NONE")
    if (norm %in% av) norm else "NONE"
  }

  d <- tryCatch(
    .hic_query(path, chrf, lstart0 + 1, lend, chrf, lstart0 + 1, lend,
               r, nrm, "BP"),
    error = function(e) { message("[rotmap] read failed: ", conditionMessage(e)); NULL })
  if (is.null(d)) return(structure(list(), rot_reason = "read"))

  B <- matrix(0, nrow = n, ncol = K + 1L)
  if (nrow(d) > 0) {
    lo <- pmin(d$x, d$y); hi <- pmax(d$x, d$y)
    i  <- as.integer((lo - lstart0) / r) + 1L
    k  <- as.integer((hi - lo) / r)
    ok <- is.finite(i) & is.finite(k) & i >= 1L & i <= n & k >= 0L & k <= K &
          (i + k) <= n & is.finite(d$counts)
    if (any(ok)) B[cbind(i[ok], k[ok] + 1L)] <- d$counts[ok]
  }

  .rot_cache_put(key, list(B = B, lstart = lstart0, res = r, K = K, n = n,
                           chr = chrf, norm = nrm))
}

# ---------------------------------------------------------------------------
# observed / expected on a band matrix. Much simpler than the square version in
# draw.R: the expected value at separation k is just the mean of column k+1.
# ---------------------------------------------------------------------------
.rot_oe <- function(B, log2 = FALSE) {
  e <- colMeans(B, na.rm = TRUE)
  e[!is.finite(e) | e <= 0] <- NA_real_
  r <- sweep(B, 2, e, "/")
  if (log2) r <- base::log2(r)
  r[!is.finite(r)] <- NA_real_
  r
}

# scaling bounds, following draw.R's convention:
#   unit = "p"  min/max are quantiles (0..1)
#   unit = "v"  min/max are absolute values
.rot_bounds <- function(v, unit = "p", min = NULL, max = 0.95) {
  v <- v[is.finite(v)]
  if (!length(v)) return(list(vmin = 0, vmax = 1))
  if (identical(unit, "p")) {
    q <- function(p) {
      p <- as.numeric(p); if (!is.finite(p)) return(NA_real_)
      if (p > 1) p <- p / 100
      as.numeric(stats::quantile(v, min(max(p, 0), 1), na.rm = TRUE, names = FALSE))
    }
    lo <- if (is.null(min)) base::min(v) else q(min)
    hi <- if (is.null(max)) base::max(v) else q(max)
  } else {
    lo <- if (is.null(min)) base::min(v) else as.numeric(min)
    hi <- if (is.null(max)) base::max(v) else as.numeric(max)
  }
  if (!is.finite(lo)) lo <- base::min(v)
  if (!is.finite(hi) || hi <= lo) hi <- lo + 1e-9
  list(vmin = lo, vmax = hi)
}

# panel geometry in px (same trick plot_arc_track() uses)
.rot_panel_px <- function() {
  dsz <- tryCatch(grDevices::dev.size("px"), error = function(e) c(900, 600))
  din <- tryCatch(grDevices::dev.size("in"), error = function(e) c(9, 6))
  ppi <- if (is.finite(din[1]) && din[1] > 0) dsz[1] / din[1] else 96
  c(max(50, par("pin")[1] * ppi), max(20, par("pin")[2] * ppi))
}

# ---------------------------------------------------------------------------
# the two renderers. Both take the band and the visible window and paint the
# CURRENT plot region (the caller has already set up xlim / ylim).
# ---------------------------------------------------------------------------
.rot_draw_raster <- function(B, lstart, res, vstart, vend, dlo, dhi,
                             color, vmin, vmax, wpx, hpx, up = TRUE) {
  n <- nrow(B); K <- ncol(B) - 1L
  Wp <- max(2L, min(ROT_RASTER_MAX, as.integer(round(wpx))))
  Hp <- max(2L, min(ROT_RASTER_MAX, as.integer(round(hpx))))
  gx <- vstart + (seq_len(Wp) - 0.5) * (vend - vstart) / Wp
  # row 1 of a raster is the TOP of the image
  gy <- if (up) dhi - (seq_len(Hp) - 0.5) * (dhi - dlo) / Hp
        else    dlo + (seq_len(Hp) - 0.5) * (dhi - dlo) / Hp
  X <- matrix(gx, Hp, Wp, byrow = TRUE)
  Y <- matrix(gy, Hp, Wp, byrow = FALSE)
  # invert  x = lstart + (i-1)*res + res*(k+1)/2 ,  y = k*res
  kk <- round(Y / res)
  ii <- round((X - lstart - res * (kk + 1) / 2) / res) + 1L
  ok <- is.finite(ii) & is.finite(kk) & kk >= 0L & kk <= K &
        ii >= 1L & ii <= n & (ii + kk) <= n
  v <- rep(NA_real_, length(ii))
  if (any(ok)) v[ok] <- B[cbind(ii[ok], kk[ok] + 1L)]
  cm <- matrix(values_to_colors(v, color, vmin, vmax), Hp, Wp)
  graphics::rasterImage(grDevices::as.raster(cm), vstart, dlo, vend, dhi,
                        interpolate = FALSE)
  invisible(Wp * Hp)
}

# vertex order matches hicdraw's getRotate(): left, top, right, bottom
.rot_draw_polygon <- function(B, lstart, res, vstart, vend, dlo, dhi,
                              color, vmin, vmax, max_poly = ROT_POLY_MAX) {
  n <- nrow(B); K <- ncol(B) - 1L
  klo <- max(0L, as.integer(floor(dlo / res)) - 1L)
  khi <- min(K,  as.integer(ceiling(dhi / res)) + 1L)
  if (khi < klo) return(invisible(0L))
  xs <- ys <- vs <- vector("list", khi - klo + 1L)
  for (k in klo:khi) {
    # bins whose diamond centre can fall inside [vstart, vend]
    ctr0 <- lstart + res * (k + 1) / 2
    i1 <- max(1L, as.integer(floor((vstart - ctr0) / res)))
    i2 <- min(n - k, as.integer(ceiling((vend - ctr0) / res)) + 1L)
    if (i2 < i1) next
    idx <- i1:i2
    val <- B[cbind(idx, rep.int(k + 1L, length(idx)))]
    keep <- is.finite(val)
    if (!any(keep)) next
    idx <- idx[keep]; val <- val[keep]
    b <- lstart + (idx - 1) * res              # start of bin i
    x1 <- b + k * res / 2
    x2 <- b + (k + 1) * res / 2
    x3 <- b + res + k * res / 2
    m  <- length(idx)
    # y depends only on k, so it has to be recycled explicitly - rbind() of a
    # scalar against a vector silently produces one column, not m of them
    y1 <- rep.int(k * res, m)
    y2 <- rep.int((k + 1) * res, m)
    y4 <- rep.int((k - 1) * res, m)
    NAv <- rep.int(NA_real_, m)
    j <- length(xs) - (khi - k)
    xs[[j]] <- as.vector(rbind(x1, x2, x3, x2, NAv))
    ys[[j]] <- as.vector(rbind(y1, y2, y1, y4, NAv))
    vs[[j]] <- val
  }
  X <- unlist(xs, use.names = FALSE)
  V <- unlist(vs, use.names = FALSE)
  if (!length(V)) return(invisible(0L))
  if (length(V) > max_poly) return(invisible(-length(V)))   # caller falls back
  graphics::polygon(X, unlist(ys, use.names = FALSE),
                    col = values_to_colors(V, color, vmin, vmax), border = NA)
  invisible(length(V))
}

# ---------------------------------------------------------------------------
# plot_rot_track(): draw one rotated map into the current device.
#
# Signature mirrors plot_track() / plot_arc_track() so app.R can treat it the
# same way: same mar / frame / yscale contract, x range in genomic bp.
#
# Note on the vertical axis: it is DISTANCE, so the generic per-track Min / Max
# must not be wired to it (that mistake made dead controls on the arc track).
# `dmin` / `dmax` set what is drawn AND where the axis ends - one pair of
# numbers, not two that can disagree.
# ---------------------------------------------------------------------------
plot_rot_track <- function(band, chr, vstart, vend, chrlen = Inf,
                           name = "", dmax = NULL, dmin = 0,
                           color = "matlab", unit = "p",
                           vmin = NULL, vmax = 0.95,
                           oe = FALSE, method = "auto",
                           orientation = "up",
                           mar = c(0.3, 0, 0.3, 0), frame = TRUE,
                           yscale = "inline", note = NULL) {
  op <- par(mar = mar, xpd = FALSE); on.exit(par(op))
  vstart <- as.numeric(vstart); vend <- as.numeric(vend)

  dhi <- suppressWarnings(as.numeric(dmax))
  if (length(dhi) != 1 || !is.finite(dhi) || dhi <= 0)
    dhi <- rot_default_dmax(vstart, vend)
  dlo <- suppressWarnings(as.numeric(dmin))
  if (length(dlo) != 1 || !is.finite(dlo) || dlo < 0) dlo <- 0
  if (dlo >= dhi) dlo <- 0

  up   <- !identical(orientation, "down")
  ylim <- if (up) c(dlo, dhi) else c(dhi, dlo)
  plot(NA, xlim = c(vstart, vend), ylim = ylim,
       xaxs = "i", yaxs = "i", axes = FALSE, ann = FALSE)

  msg <- NULL
  if (is.null(band) || is.null(band$B) || !nrow(band$B)) {
    msg <- switch(attr(band, "rot_reason") %||% "empty",
                  chrom = tr("rot_no_chrom"), res = tr("rot_no_res"),
                  read  = tr("rot_read_fail"), tr("rot_empty"))
  }

  drawn <- 0L
  if (is.null(msg)) {
    B <- band$B
    if (identical(oe, "oe"))            B <- .rot_oe(B, FALSE)
    else if (identical(oe, "oe_log2"))  B <- .rot_oe(B, TRUE)

    bd <- .rot_bounds(as.numeric(B), unit, vmin, vmax)
    # A log2 observed/expected map is signed and its meaningful midpoint is 0,
    # so an asymmetric range would make "no enrichment" look like a colour.
    # Unless the user pinned the bottom explicitly, centre the scale.
    if (identical(oe, "oe_log2") && is.null(vmin)) {
      lim <- max(abs(bd$vmin), abs(bd$vmax))
      if (!is.finite(lim) || lim <= 0) lim <- 1
      bd <- list(vmin = -lim, vmax = lim)
    }
    px <- .rot_panel_px()
    binpx <- band$res / ((vend - vstart) / max(1, px[1]))

    want <- method
    if (identical(want, "auto")) want <- if (binpx >= ROT_POLY_PX) "polygon" else "raster"
    if (identical(want, "polygon")) {
      cap <- if (identical(yscale, "axis")) ROT_POLY_MAX_V else ROT_POLY_MAX
      drawn <- .rot_draw_polygon(B, band$lstart, band$res, vstart, vend,
                                 dlo, dhi, color, bd$vmin, bd$vmax, cap)
      if (drawn < 0) want <- "raster"      # too many diamonds - fall back
    }
    if (identical(want, "raster"))
      drawn <- .rot_draw_raster(B, band$lstart, band$res, vstart, vend,
                                dlo, dhi, color, bd$vmin, bd$vmax,
                                px[1], px[2], up)
    scale_lab <- formatC(bd$vmax, format = "g", digits = 3)
  } else {
    scale_lab <- NULL
  }

  # ---- axis / labels -------------------------------------------------------
  # The panel is a dense colour field, so plain text on top of it is unreadable
  # over the saturated end of the palette. Everything drawn inside the map goes
  # through .rot_text(), which lays a translucent white plate under the words.
  # The other tracks draw on white and need no such thing.
  span_x <- vend - vstart; span_y <- dhi - dlo
  ytop <- if (up) dhi else dlo
  ydir <- if (up) -1 else 1                        # "downwards" in data units

  if (identical(yscale, "axis")) {
    at <- pretty(c(dlo, dhi), 3)
    at <- at[at >= min(dlo, dhi) & at <= max(dlo, dhi)]
    axis(2, at = at, labels = rot_fmt_bp(at), las = 1, tcl = -0.4,
         mgp = c(3, 0.5, 0), cex.axis = 0.8, col = "grey40", col.axis = "grey20")
  } else if (is.null(msg)) {
    # inline: one distance reference at the right edge. A full-width rule (what
    # plot_track does for a signal track) would sit across the map itself.
    gy <- signif(dlo + span_y * 0.85, 2)
    if (is.finite(gy) && gy > dlo && gy < dhi) {
      tw <- span_x * 0.012
      segments(vend - tw, gy, vend, gy, col = "grey15", lwd = 1.2)
      .rot_text(vend - tw * 1.4, gy, rot_fmt_bp(gy), adj = c(1, 0.5), cex = 0.9)
    }
  }

  lbl <- if (nzchar(name %||% "")) name else "Hi-C"
  if (!is.null(band$res)) lbl <- sprintf("%s  (%s)", lbl, fmt_res(band$res))
  .rot_text(vstart + 0.006 * span_x, ytop + ydir * span_y * 0.04, lbl,
            adj = c(0, 0.5), cex = 1.1)
  if (!is.null(scale_lab) && identical(yscale, "inline"))
    .rot_text(vstart + 0.006 * span_x, ytop + ydir * span_y * 0.14,
              paste0("max ", scale_lab), adj = c(0, 0.5), cex = 0.82)
  if (!is.null(msg))
    text(mean(c(vstart, vend)), mean(c(dlo, dhi)), msg, cex = 0.95, col = "grey40")
  if (!is.null(note) && nzchar(note))
    .rot_text(vend - 0.006 * span_x, ytop + ydir * span_y * 0.04, note,
              adj = c(1, 0.5), cex = 0.82)

  if (isTRUE(frame)) box(col = "grey85")
  invisible(list(drawn = drawn, res = band$res))
}

# text with a translucent plate behind it, so a label stays readable wherever
# it lands on the colour field
.rot_text <- function(x, y, labels, adj = c(0, 0.5), cex = 1,
                      col = "grey10", bg = "#FFFFFFCC") {
  w <- strwidth(labels, cex = cex); h <- strheight(labels, cex = cex)
  padx <- strwidth("n", cex = cex) * 0.4; pady <- h * 0.35
  x0 <- x - adj[1] * w; y0 <- y - adj[2] * h
  rect(x0 - padx, y0 - pady, x0 + w + padx, y0 + h + pady,
       col = bg, border = NA)
  text(x0, y0, labels, adj = c(0, 0), cex = cex, col = col)
}

# short bp label for the distance axis (1.5 Mb / 250 kb / 900 bp)
rot_fmt_bp <- function(v) {
  vapply(v, function(x) {
    if (!is.finite(x)) return("")
    if (abs(x) >= 1e6) sprintf("%g Mb", signif(x / 1e6, 3))
    else if (abs(x) >= 1e3) sprintf("%g kb", signif(x / 1e3, 3))
    else sprintf("%g bp", signif(x, 3))
  }, character(1))
}

# ============================================================================
# virtual4c.R  -  HiCarta plugin: "virtual 4C" contact profile from one anchor
#
# Draws, under the contact map, how often every bin in view touches ONE
# anchor position (a promoter, an enhancer, a boundary...). It reads the .hic
# through HiCarta's own streaming reader, so it works on local files, http(s)
# URLs and private s3:// objects alike, at whatever resolution fits the view.
#
# Catalog row:
#   file_type = v4c      path = <the .hic>      set_anchor = 21975000
#   (set_anchor_chr, set_res, set_norm, set_window, set_smooth are optional)
# Or add the .hic from Load data > Direct file with Type = "Virtual 4C", then
# set the anchor in the track's settings (click its name in the Tracks panel).
#
# Parameters (all overridable from the catalog, the dialog, or a session file):
#   anchor     bp position of the anchor; 0 = the centre of the current view
#   anchor_chr chromosome of the anchor; "" = the chromosome on screen
#              (name a different one and you get the trans profile)
#   res        bin size in bp; 0 = the file's resolution closest to ~400 bins
#              across the view
#   norm       normalization to read (KR / ICE / VC / NONE); falls back to
#              NONE when the file lacks it
#   window     number of anchor bins to sum (1 = the anchor bin only, 3 = +-1)
#   smooth     running-mean width in bins (1 = none)
#   log        TRUE = draw log10(1 + value)
# ============================================================================

hicarta_plugin(
  id          = "v4c",
  label       = "Virtual 4C",
  description = "Contact profile between one anchor and every bin in view, read from the .hic at the resolution that fits the view.",
  accepts     = "hic",
  height      = 110,
  color       = "#B2182B",
  defaults    = list(anchor = 0, anchor_chr = "", res = 0, norm = "KR",
                     window = 1, smooth = 1, log = FALSE),

  # ---- data for the part of the view inside the chromosome ----------------
  read = function(path, chr, start, end, p) {
    res <- if (is.finite(p$res) && p$res > 0) p$res
           else hc_hic_pick_resolution(path, chr, start, end,
                                       target_bins = 400, norm = p$norm)
    achr <- if (nzchar(p$anchor_chr)) p$anchor_chr else chr
    a    <- if (is.finite(p$anchor) && p$anchor > 0) p$anchor else (start + end) / 2
    w    <- max(1, round(p$window))
    half <- floor((w - 1) / 2) * res
    # a thin slab: every bin of [start,end] on `chr` against the anchor bins
    m <- hc_hic_region(path, chr, start, end, resolution = res, norm = p$norm,
                       chr2 = achr, start2 = max(1, a - half), end2 = a + half + res)
    v <- if (ncol(m)) rowSums(m, na.rm = TRUE) else numeric(nrow(m))
    v[!is.finite(v)] <- 0
    k <- max(1, round(p$smooth))
    if (k > 1 && length(v) >= k)
      v <- as.numeric(stats::filter(v, rep(1 / k, k), sides = 2, circular = FALSE))
    v[!is.finite(v)] <- 0
    s <- hc_bin_starts(m, 1)
    data.frame(start = s + 1, end = s + res, value = v,
               anchor = a, anchor_chr = achr, res = res,
               stringsAsFactors = FALSE)
  },

  # ---- drawing: same x range as the map (hc_canvas does that) -------------
  draw = function(d, chr, vstart, vend, style) {
    p <- style$params
    if (is.null(d) || nrow(d) == 0) {
      hc_canvas(vstart, vend)
      hc_label(style$name)
      hc_message("no contacts in view", col = "grey50")
      return(invisible(NULL))
    }
    v <- d$value
    if (isTRUE(p$log)) v <- log10(1 + pmax(v, 0))
    vmax <- suppressWarnings(max(v, na.rm = TRUE))
    if (!is.finite(vmax) || vmax <= 0) {
      # nothing touches the anchor from here (anchor far away, or off this
      # chromosome): say so instead of drawing a flat line with a 1e-9 scale
      hc_canvas(vstart, vend)
      hc_label(style$name)
      hc_message("no contacts with the anchor in this view", col = "grey50")
      return(invisible(NULL))
    }
    ymax <- if (is.finite(style$ymax) && style$ymax > 0) style$ymax else vmax
    hc_canvas(vstart, vend, ylim = c(0, ymax))
    rect(d$start, 0, d$end, pmin(v, ymax), col = style$color, border = NA)
    # the anchor, when it is on this chromosome and in view
    a <- d$anchor[1]
    if (identical(d$anchor_chr[1], chr) && a >= vstart && a <= vend) {
      abline(v = a, col = "grey25", lty = 3)
      text(a, ymax * 0.98, sprintf(" anchor %s", format(round(a), big.mark = ",")),
           adj = c(0, 1), cex = 0.9, col = "grey25")
    }
    hc_label(sprintf("%s  (%s%s)", style$name,
                     if (d$res[1] >= 1000) paste0(d$res[1] / 1000, " kb") else paste0(d$res[1], " bp"),
                     if (isTRUE(p$log)) ", log10" else ""))
    if (isTRUE(style$print)) hc_yaxis() else hc_guide(signif(ymax * 0.9, 2))
    invisible(NULL)
  }
)

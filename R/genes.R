# ============================================================================
# genes.R  -  Gene-model track from a GFF3 (e.g. PomBase S. pombe).
#
# A GFF3 is parsed ONCE into a compact structure (genes + exon/UTR segments) and
# cached: as an <gff3>.genes.rds next to the file, and in memory (GENE_CACHE) so
# panning never re-parses. Drawing filters to the visible window; exon detail and
# gene names are only rendered when zoomed in enough (cheap at any zoom).
# ============================================================================

suppressWarnings(suppressMessages({ library(data.table) }))

GENE_CACHE <- new.env(parent = emptyenv())

.gff_attr <- function(v, key) {
  out <- rep(NA_character_, length(v))
  has <- grepl(paste0("(?:^|;)", key, "="), v, perl = TRUE)
  out[has] <- sub(paste0(".*(?:^|;)", key, "=([^;]*).*"), "\\1", v[has], perl = TRUE)
  out
}

# Parse a GFF3 into list(genes = df(chr,start,end,strand,name,gene_id),
#                        seg   = df(gene_id,chr,start,end,kind))  and cache to RDS.
gff3_to_genes <- function(gff3, rds = paste0(gff3, ".genes.rds")) {
  # drop GFF3 comment/directive lines (##, ###, #!) before parsing, else fread
  # mis-detects the column count from a comment line
  lines <- readLines(gff3, warn = FALSE)
  lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
  g <- data.table::fread(text = paste(lines, collapse = "\n"),
         sep = "\t", header = FALSE, quote = "", fill = TRUE,
         col.names = c("chr","src","type","start","end","score","strand","phase","attr"))
  g <- g[type %in% c("gene","mRNA","CDS","five_prime_UTR","three_prime_UTR",
                     "ncRNA","tRNA","snoRNA","snRNA","rRNA","pseudogenic_transcript")]
  g[, ID     := .gff_attr(attr, "ID")]
  g[, Parent := .gff_attr(attr, "Parent")]
  g[, Name   := .gff_attr(attr, "Name")]

  gene <- g[type == "gene"]
  genes <- data.frame(chr = as.character(gene$chr),
                      start = as.numeric(gene$start), end = as.numeric(gene$end),
                      strand = gene$strand,
                      name = ifelse(is.na(gene$Name) | gene$Name == "", gene$ID, gene$Name),
                      gene_id = gene$ID, stringsAsFactors = FALSE)

  tx <- g[type %in% c("mRNA","ncRNA","tRNA","snoRNA","snRNA","rRNA","pseudogenic_transcript")]
  tx2gene <- setNames(tx$Parent, tx$ID)          # transcript ID -> gene ID
  seg <- g[type %in% c("CDS","five_prime_UTR","three_prime_UTR")]
  gid <- unname(tx2gene[seg$Parent])
  segdf <- data.frame(gene_id = gid, chr = as.character(seg$chr),
                      start = as.numeric(seg$start), end = as.numeric(seg$end),
                      kind = ifelse(seg$type == "CDS", "CDS", "UTR"),
                      stringsAsFactors = FALSE)
  segdf <- segdf[!is.na(segdf$gene_id), ]

  struct <- list(genes = genes, seg = segdf)
  tryCatch(saveRDS(struct, rds), error = function(e) NULL)
  struct
}

# Load genes (memoised). Accepts a .gff3 (parses + caches RDS) or a prebuilt .rds.
read_genes <- function(path) {
  if (!is.null(GENE_CACHE[[path]])) return(GENE_CACHE[[path]])
  rds <- if (grepl("\\.rds$", tolower(path))) path else paste0(path, ".genes.rds")
  struct <- if (file.exists(rds)) readRDS(rds) else gff3_to_genes(path, rds)
  GENE_CACHE[[path]] <- struct
  struct
}

# Draw the gene track for chr:[vstart,vend]. x-axis matches the map (aligned).
# + genes go in the upper row, - genes in the lower row. Gene glyph heights are
# CONSTANT (fixed y-bands) regardless of zoom. Names (GFF3 Name) are thinned so
# labels never overlap, adapting to the current resolution.
#
# Vertical layout (top -> bottom), as fractions of the track height:
#   space 8 | + genes 20 | + names 20 | space 5 | - genes 20 | - names 20 | space 7
plot_gene_track <- function(struct, chr, vstart, vend, chrlen = Inf,
                            name = "genes", color = "grey20") {
  op <- par(mar = c(0, 0, 0, 0)); on.exit(par(op))
  vstart <- floor(vstart); vend <- ceiling(vend); span <- vend - vstart
  plot(NA, xlim = c(vstart, vend), ylim = c(0, 1), xaxs = "i", yaxs = "i",
       axes = FALSE, ann = FALSE)

  # y-bands (measured from the TOP): cumulative 8,20,20,5,20,20,7 -> [0,1] from top
  top <- 1
  Bp_g <- c(top - 0.28, top - 0.08)   # + gene glyphs
  Bp_n <- c(top - 0.48, top - 0.28)   # + names
  Bm_g <- c(top - 0.73, top - 0.53)   # - gene glyphs
  Bm_n <- c(top - 0.93, top - 0.73)   # - names
  text(vstart + 0.004 * span, 0.995, name, adj = c(0, 1), cex = 0.95, col = "grey45")

  g <- struct$genes
  vis <- g[g$chr == chr & g$end >= vstart & g$start <= vend, , drop = FALSE]
  if (nrow(vis) == 0) { box(col = "grey85"); return(invisible()) }
  Wpx     <- tryCatch(grDevices::dev.size("px")[1], error = function(e) 900)
  showEx  <- span <= 3e5
  charbp  <- (7 / max(Wpx, 1)) * span   # approx width of one label character, in bp

  draw_strand <- function(sub, gb, nb, isplus) {
    if (nrow(sub) == 0) return()
    s <- pmax(vstart, sub$start); e <- pmin(vend, sub$end)
    gy <- mean(gb); gh <- (gb[2] - gb[1]) * 0.35
    suppressWarnings(arrows(x0 = ifelse(isplus, s, e), y0 = gy,
                            x1 = ifelse(isplus, e, s), y1 = gy,
                            length = 0.03, angle = 25, code = 2, col = color, lwd = 1))
    if (showEx) {
      seg <- struct$seg
      sv <- seg[seg$gene_id %in% sub$gene_id & seg$chr == chr &
                seg$end >= vstart & seg$start <= vend, , drop = FALSE]
      if (nrow(sv) > 0) {
        utr <- sv$kind != "CDS"
        rect(pmax(vstart, sv$start[utr]),  gy - gh * 0.5, pmin(vend, sv$end[utr]),  gy + gh * 0.5, col = color, border = NA)
        rect(pmax(vstart, sv$start[!utr]), gy - gh,       pmin(vend, sv$end[!utr]), gy + gh,       col = color, border = NA)
      }
    } else {
      rect(s, gy - gh, e, gy + gh, col = color, border = NA)
    }
    # names, thinned greedily left-to-right so labels never overlap
    cx <- (s + e) / 2; ny <- mean(nb)
    ord <- order(cx); last <- -Inf
    for (k in ord) {
      w <- (nchar(sub$name[k]) + 1) * charbp
      if (cx[k] - w / 2 > last) {
        text(cx[k], ny, sub$name[k], cex = 0.8, col = "grey20")
        last <- cx[k] + w / 2
      }
    }
  }
  draw_strand(vis[vis$strand == "+", , drop = FALSE], Bp_g, Bp_n, TRUE)
  draw_strand(vis[vis$strand == "-", , drop = FALSE], Bm_g, Bm_n, FALSE)
  box(col = "grey85")
}

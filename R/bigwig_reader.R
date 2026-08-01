# ============================================================================
# bigwig_reader.R  -  Stateful bigWig (BBI) reader in pure R.
#
# WHY THIS EXISTS
# ---------------
# rtracklayer cannot open a bigWig over http(s): the Bioconductor build ships
# without Kent's remote/udc support, so BigWigFile(url) fails with
# "Couldn't open ... UCSC library operation failed" before sending a single
# request. HiCarta therefore downloaded every remote track into _hic_cache/
# before reading it. This reader streams instead, the same way R/hic_reader.R
# does for .hic: one kept-alive connection, cached index, LRU block cache.
#
# FORMAT
# ------
# BBI (Kent et al., "BigWig and BigBed: enabling browsing of large distributed
# datasets", Bioinformatics 2010, supplementary tables 5-16):
#
#   header (64 B)  magic 0x888FFC26, version, zoomLevels, chromosomeTreeOffset,
#                  fullDataOffset, fullIndexOffset, ..., totalSummaryOffset,
#                  uncompressBufSize
#   zoom headers   zoomLevels x (reductionLevel, reserved, dataOffset, indexOffset)
#   chrom B+ tree  magic 0x78CA8C91, then nodes of (key, chromId, chromSize)
#   R-tree index   magic 0x2468ACE0, then nodes of
#                  (startChromIx, startBase, endChromIx, endBase, offset[, size])
#   data blocks    zlib-deflated when uncompressBufSize > 0; each holds a
#                  section header (chromId, chromStart, chromEnd, itemStep,
#                  itemSpan, type, itemCount) followed by items of one of
#                  three shapes: 1 = bedGraph, 2 = varStep, 3 = fixedStep
#   zoom blocks    fixed 32 B records
#                  (chromId, start, end, validCount, min, max, sum, sumSq)
#
# Byte order is taken from the magic number, so both endiannesses are handled.
#
# PUBLIC API
# ----------
#   bw_reader(path)                 cached, one reader per path per session
#   bw_open(path) / bw_close(rd)
#   bw_chroms(rd)                   data.frame(name, id, size)
#   bw_intervals(rd, chr, s, e)     data.frame(start, end, value)  1-based, inclusive
#   bw_summary(rd, chr, s, e, nbins, type)   numeric(nbins), uncovered = 0
#   bw_io_stats(rd)                 list(reads, bytes)
#   bw_forget(path = NULL)
#
# `path` may be a local file or an http(s):// URL (URLs need the `curl` package).
# ============================================================================

BW_MAGIC        <- 0x888FFC26
BBI_CHROM_MAGIC <- 0x78CA8C91
BBI_RTREE_MAGIC <- 0x2468ACE0


# ---------------------------------------------------------------------------
# unsigned integer readers. R has no uint32/uint64, so both are assembled into
# doubles: file offsets and coordinates are well under 2^53, so this is exact.
# ---------------------------------------------------------------------------
.bw_u32 <- function(r, big) {
  if (big) r <- rev(r)
  sum(as.numeric(r) * c(1, 256, 65536, 16777216))
}

.bw_u16 <- function(r, big) {
  if (big) r <- rev(r)
  sum(as.numeric(r) * c(1, 256))
}

.bw_rc_u16 <- function(con, big)
  readBin(con, "integer", size = 2, n = 1, signed = FALSE,
          endian = if (big) "big" else "little")

.bw_rc_u32 <- function(con, big) .bw_u32(readBin(con, "raw", n = 4), big)

.bw_rc_u64 <- function(con, big) {
  r <- readBin(con, "raw", n = 8)
  if (big) r <- rev(r)
  .bw_u32(r[1:4], FALSE) + .bw_u32(r[5:8], FALSE) * 4294967296
}

.bw_rc_u8  <- function(con) as.integer(readBin(con, "raw", n = 1)[1])

.bw_rc_f32 <- function(con, big)
  readBin(con, "double", size = 4, n = 1, endian = if (big) "big" else "little")

.bw_rc_f64 <- function(con, big)
  readBin(con, "double", size = 8, n = 1, endian = if (big) "big" else "little")

# Vectorised decoders that work straight off a raw vector. Everything hot goes
# through these -- no per-field connections (an earlier version leaked one
# rawConnection per field and hit R's connection limit).
.bw_u32v <- function(raw, big) {
  n <- length(raw) %/% 4L
  if (n == 0L) return(numeric(0))
  m <- matrix(as.numeric(raw[seq_len(4L * n)]), nrow = 4L)
  if (big) m <- m[4:1, , drop = FALSE]
  as.vector(c(1, 256, 65536, 16777216) %*% m)
}

.bw_f32v <- function(raw, big) {
  n <- length(raw) %/% 4L
  if (n == 0L) return(numeric(0))
  readBin(raw, "double", size = 4, n = n, endian = if (big) "big" else "little")
}

.bw_vec_u32 <- function(con, n, big) .bw_u32v(readBin(con, "raw", n = 4 * n), big)
.bw_vec_f32 <- function(con, n, big) .bw_f32v(readBin(con, "raw", n = 4 * n), big)


# ---------------------------------------------------------------------------
# byte source: reused curl handle (remote) or open connection (local)
# ---------------------------------------------------------------------------
.bw_is_url <- function(p) grepl("^https?://", p)

.bw_range <- function(rd, pos, n) {
  n <- as.numeric(n)
  if (n <= 0) return(raw(0))

  # The header, zoom headers, chromosome B+ tree and the top of the R-tree all
  # live in the first few KB. One prefetch at open serves all of them, turning
  # ~6 round trips into 1 -- which matters when each costs a WAN RTT.
  if (!is.null(rd$head) && pos + n <= length(rd$head))
    return(rd$head[(pos + 1):(pos + n)])

  rd$nreads <- rd$nreads + 1L
  rd$nbytes <- rd$nbytes + n

  if (!rd$remote) {
    seek(rd$con, where = pos, origin = "start")
    return(readBin(rd$con, "raw", n = n))
  }
  curl::handle_setheaders(rd$handle,
    Range = sprintf("bytes=%.0f-%.0f", pos, pos + n - 1))
  r <- curl::curl_fetch_memory(rd$path, handle = rd$handle)
  if (!(r$status_code %in% c(200L, 206L)))
    stop(sprintf("HTTP %d while reading %s", r$status_code, rd$path),
         call. = FALSE)
  if (is.null(rd$size)) {
    h  <- curl::parse_headers_list(r$headers)
    cr <- h[["content-range"]]
    if (!is.null(cr)) {
      tot <- sub(".*/", "", cr)
      if (grepl("^[0-9]+$", tot)) rd$size <- as.numeric(tot)
    }
  }
  r$content
}

.bw_con <- function(rd, pos, n) {
  con <- rawConnection(.bw_range(rd, pos, n), "rb")
  con
}


# ---------------------------------------------------------------------------
# header + zoom levels + total summary
# ---------------------------------------------------------------------------
.bw_read_header <- function(rd) {
  # Pull the whole head of the file in one request, then parse everything that
  # lives there out of memory (see the note in .bw_range).
  want <- if (is.null(rd$size)) 65536 else min(rd$size, 65536)
  rd$head <- NULL
  rd$head <- .bw_range(rd, 0, want)
  raw0 <- rd$head[1:64]
  m_le <- .bw_u32(raw0[1:4], FALSE)
  m_be <- .bw_u32(raw0[1:4], TRUE)
  rd$big <- if (isTRUE(all.equal(m_le, BW_MAGIC))) FALSE
            else if (isTRUE(all.equal(m_be, BW_MAGIC))) TRUE
            else stop("not a bigWig file (bad magic): ", rd$path, call. = FALSE)
  big <- rd$big

  con <- rawConnection(raw0, "rb"); on.exit(close(con))
  .bw_rc_u32(con, big)                                  # magic
  rd$version      <- .bw_rc_u16(con, big)
  rd$zoomLevels   <- .bw_rc_u16(con, big)
  rd$chromTreeOff <- .bw_rc_u64(con, big)
  rd$fullDataOff  <- .bw_rc_u64(con, big)
  rd$fullIndexOff <- .bw_rc_u64(con, big)
  rd$fieldCount   <- .bw_rc_u16(con, big)
  rd$definedField <- .bw_rc_u16(con, big)
  rd$autoSqlOff   <- .bw_rc_u64(con, big)
  rd$totalSumOff  <- .bw_rc_u64(con, big)
  rd$uncompressBufSize <- .bw_rc_u32(con, big)

  # zoom headers follow the 64-byte header, 24 bytes each
  if (rd$zoomLevels > 0) {
    zc <- .bw_con(rd, 64, 24 * rd$zoomLevels); on.exit(close(zc), add = TRUE)
    red <- numeric(rd$zoomLevels); dof <- numeric(rd$zoomLevels)
    iof <- numeric(rd$zoomLevels)
    for (i in seq_len(rd$zoomLevels)) {
      red[i] <- .bw_rc_u32(zc, big)
      .bw_rc_u32(zc, big)                               # reserved
      dof[i] <- .bw_rc_u64(zc, big)
      iof[i] <- .bw_rc_u64(zc, big)
    }
    o <- order(red)
    rd$zoom <- data.frame(reduction = red[o], dataOffset = dof[o],
                          indexOffset = iof[o])
  } else {
    rd$zoom <- data.frame(reduction = numeric(0), dataOffset = numeric(0),
                          indexOffset = numeric(0))
  }
  invisible(rd)
}

bw_total_summary <- function(rd) {
  if (rd$totalSumOff <= 0) return(NULL)
  con <- .bw_con(rd, rd$totalSumOff, 40); on.exit(close(con))
  list(validCount = .bw_rc_u64(con, rd$big),
       min = .bw_rc_f64(con, rd$big), max = .bw_rc_f64(con, rd$big),
       sumData = .bw_rc_f64(con, rd$big), sumSquares = .bw_rc_f64(con, rd$big))
}


# ---------------------------------------------------------------------------
# chromosome B+ tree. Few chromosomes in practice, so the whole tree is walked
# once and cached rather than implementing key search.
# ---------------------------------------------------------------------------
.bw_read_chroms <- function(rd) {
  if (!is.null(rd$chroms)) return(rd$chroms)
  big <- rd$big
  hc <- .bw_con(rd, rd$chromTreeOff, 32); on.exit(close(hc))
  magic <- .bw_rc_u32(hc, big)
  if (!isTRUE(all.equal(magic, BBI_CHROM_MAGIC)))
    stop("bad chromosome B+ tree magic in ", rd$path, call. = FALSE)
  .bw_rc_u32(hc, big)                                   # blockSize
  keySize <- .bw_rc_u32(hc, big)
  .bw_rc_u32(hc, big)                                   # valSize
  itemCount <- .bw_rc_u64(hc, big)

  nm <- character(0); id <- numeric(0); sz <- numeric(0)
  walk <- function(off) {
    hraw   <- .bw_range(rd, off, 4)
    isLeaf <- as.integer(hraw[1])
    cnt    <- as.integer(.bw_u16(hraw[3:4], big))
    if (cnt <= 0L) return(invisible(NULL))
    # leaf record: key[keySize] chromId(u32) chromSize(u32)
    # inner record: key[keySize] childOffset(u64)
    rec <- keySize + 8L
    body <- .bw_range(rd, off + 4, cnt * rec)
    if (isLeaf == 1L) {
      for (i in seq_len(cnt)) {
        o <- (i - 1L) * rec
        k <- body[(o + 1L):(o + keySize)]
        k <- k[k != as.raw(0)]
        nm <<- c(nm, if (length(k)) rawToChar(k) else "")
        id <<- c(id, .bw_u32(body[(o + keySize + 1L):(o + keySize + 4L)], big))
        sz <<- c(sz, .bw_u32(body[(o + keySize + 5L):(o + keySize + 8L)], big))
      }
    } else {
      kids <- vapply(seq_len(cnt), function(i) {
        o <- (i - 1L) * rec
        lo <- .bw_u32(body[(o + keySize + 1L):(o + keySize + 4L)], big)
        hi <- .bw_u32(body[(o + keySize + 5L):(o + keySize + 8L)], big)
        if (big) hi * 4294967296 + lo else lo + hi * 4294967296
      }, numeric(1))
      for (k in kids) walk(k)
    }
    invisible(NULL)
  }
  walk(rd$chromTreeOff + 32)

  rd$chroms <- data.frame(name = nm, id = id, size = sz,
                          stringsAsFactors = FALSE)
  rd$chroms
}

bw_chroms <- function(rd) .bw_read_chroms(rd)


# ---------------------------------------------------------------------------
# R-tree query -> the data blocks overlapping [qs, qe) on chromosome qid.
# Node reads are cached, so repeated queries in the same region cost nothing.
# ---------------------------------------------------------------------------
.bw_rtree_find <- function(rd, indexOffset, qid, qs, qe) {
  big <- rd$big
  key <- sprintf("hdr:%.0f", indexOffset)
  hdr <- rd$idx[[key]]
  if (is.null(hdr)) {
    h <- .bw_con(rd, indexOffset, 48); on.exit(close(h))
    magic <- .bw_rc_u32(h, big)
    if (!isTRUE(all.equal(magic, BBI_RTREE_MAGIC)))
      stop("bad R-tree magic in ", rd$path, call. = FALSE)
    hdr <- list(root = indexOffset + 48)
    rd$idx[[key]] <- hdr
  }

  # an interval [(sIx,sB),(eIx,eB)) overlaps the query on chromosome qid
  ov <- function(sIx, sB, eIx, eB)
    !(eIx < qid || (eIx == qid && eB <= qs)) &&
    !(sIx > qid || (sIx == qid && sB >= qe))

  offs <- numeric(0); sizes <- numeric(0)

  walk <- function(off) {
    nk <- sprintf("n:%.0f", off)
    nd <- rd$idx[[nk]]
    if (is.null(nd)) {
      hraw   <- .bw_range(rd, off, 4)
      isLeaf <- as.integer(hraw[1])
      cnt    <- as.integer(.bw_u16(hraw[3:4], big))
      nd <- list(isLeaf = isLeaf, cnt = cnt)
      if (cnt > 0L) {
        # leaf record: sIx sB eIx eB offset(u64) size(u64)   = 8 x u32
        # inner record: sIx sB eIx eB childOffset(u64)       = 6 x u32
        nu  <- if (isLeaf == 1L) 8L else 6L
        m   <- matrix(.bw_u32v(.bw_range(rd, off + 4, cnt * nu * 4L), big),
                      nrow = nu)
        nd$sIx <- m[1, ]; nd$sB <- m[2, ]
        nd$eIx <- m[3, ]; nd$eB <- m[4, ]
        nd$off <- m[5, ] + m[6, ] * 4294967296
        nd$size <- if (isLeaf == 1L) m[7, ] + m[8, ] * 4294967296 else NULL
      }
      rd$idx[[nk]] <- nd
    }
    if (nd$cnt <= 0) return(invisible(NULL))
    for (i in seq_len(nd$cnt)) {
      if (!ov(nd$sIx[i], nd$sB[i], nd$eIx[i], nd$eB[i])) next
      if (nd$isLeaf == 1L) {
        offs  <<- c(offs, nd$off[i])
        sizes <<- c(sizes, nd$size[i])
      } else {
        walk(nd$off[i])
      }
    }
    invisible(NULL)
  }
  walk(hdr$root)
  o <- order(offs)
  list(offset = offs[o], size = sizes[o])
}


# ---------------------------------------------------------------------------
# data blocks
# ---------------------------------------------------------------------------
.bw_touch <- function(rd, k) rd$blockord <- c(setdiff(rd$blockord, k), k)

.bw_evict <- function(rd) {
  if (length(rd$blockord) <= rd$maxBlocks) return(invisible(NULL))
  drop <- rd$blockord[seq_len(length(rd$blockord) - rd$maxBlocks)]
  rd$blockord <- setdiff(rd$blockord, drop)
  for (d in drop) if (!is.null(rd$blocks[[d]])) rm(list = d, envir = rd$blocks)
  invisible(NULL)
}

.bw_store <- function(rd, off, bytes) {
  k <- sprintf("%.0f", off)
  if (rd$uncompressBufSize > 0) bytes <- memDecompress(bytes, type = "gzip")
  rd$blocks[[k]] <- bytes
  .bw_touch(rd, k)
  bytes
}

.bw_raw_block <- function(rd, off, size) {
  k <- sprintf("%.0f", off)
  hit <- rd$blocks[[k]]
  if (!is.null(hit)) { .bw_touch(rd, k); return(hit) }
  b <- .bw_store(rd, off, .bw_range(rd, off, size))
  .bw_evict(rd)
  b
}

# ---------------------------------------------------------------------------
# Fetch many blocks at once. Data blocks covering a contiguous region are laid
# out contiguously in the file, so instead of one range request per block we
# coalesce neighbours into a single request and slice the result locally. Over
# a WAN this is the difference between ~25 round trips and ~2 for a whole
# chromosome. Cached blocks are never re-fetched.
# ---------------------------------------------------------------------------
.bw_blocks <- function(rd, offs, sizes) {
  n <- length(offs)
  out <- vector("list", n)
  if (n == 0L) return(out)

  miss <- integer(0)
  for (i in seq_len(n)) {
    k <- sprintf("%.0f", offs[i])
    hit <- rd$blocks[[k]]
    if (!is.null(hit)) { out[[i]] <- hit; .bw_touch(rd, k) }
    else miss <- c(miss, i)
  }
  if (length(miss)) {
    miss <- miss[order(offs[miss])]
    gstart <- 1L
    flush <- function(idx) {
      lo  <- offs[idx[1]]
      hi  <- max(offs[idx] + sizes[idx])
      buf <- .bw_range(rd, lo, hi - lo)
      for (i in idx) {
        s <- offs[i] - lo
        out[[i]] <<- .bw_store(rd, offs[i], buf[(s + 1):(s + sizes[i])])
      }
    }
    for (j in seq_along(miss)) {
      if (j == length(miss)) { flush(miss[gstart:j]); break }
      cur <- miss[j]; nxt <- miss[j + 1L]
      gap  <- offs[nxt] - (offs[cur] + sizes[cur])
      span <- offs[nxt] + sizes[nxt] - offs[miss[gstart]]
      if (gap > rd$coalesceGap || span > rd$coalesceMax) {
        flush(miss[gstart:j]); gstart <- j + 1L
      }
    }
    .bw_evict(rd)
  }
  out
}

# one full-resolution wig section -> start/end/value vectors (0-based half-open,
# as stored)
.bw_decode_wig <- function(rd, raw0) {
  big <- rd$big
  n   <- length(raw0)
  p   <- 0L                                  # 0-based cursor into raw0
  out <- list()
  # a block may hold several consecutive sections
  while (p + 24L <= n) {
    h <- raw0[(p + 1L):(p + 24L)]
    u <- .bw_u32v(h[1:20], big)              # 5 x u32
    chromId <- u[1]; chromStart <- u[2]; itemStep <- u[4]; itemSpan <- u[5]
    type      <- as.integer(h[21])
    itemCount <- as.integer(.bw_u16(h[23:24], big))
    p <- p + 24L
    if (itemCount == 0L) next
    if (type == 1L) {                                    # bedGraph
      need <- 12L * itemCount; if (p + need > n) break
      v <- raw0[(p + 1L):(p + need)]; p <- p + need
      st <- .bw_u32v(.bbi_field(v, c(4L, 4L, 4L), 1L), big)
      en <- .bw_u32v(.bbi_field(v, c(4L, 4L, 4L), 2L), big)
      va <- .bw_f32v(.bbi_field(v, c(4L, 4L, 4L), 3L), big)
    } else if (type == 2L) {                             # varStep
      need <- 8L * itemCount; if (p + need > n) break
      v <- raw0[(p + 1L):(p + need)]; p <- p + need
      st <- .bw_u32v(.bbi_field(v, c(4L, 4L), 1L), big)
      va <- .bw_f32v(.bbi_field(v, c(4L, 4L), 2L), big)
      en <- st + itemSpan
    } else if (type == 3L) {                             # fixedStep
      need <- 4L * itemCount; if (p + need > n) break
      va <- .bw_f32v(raw0[(p + 1L):(p + need)], big); p <- p + need
      st <- chromStart + (seq_len(itemCount) - 1L) * itemStep
      en <- st + itemSpan
    } else {
      stop("unknown bigWig section type ", type, call. = FALSE)
    }
    out[[length(out) + 1L]] <- list(id = chromId, start = st, end = en,
                                    value = va)
  }
  out
}

# extract field k of fixed-width records out of a packed raw vector
.bbi_field <- function(raw, widths, k) {
  rec  <- sum(widths)
  off  <- if (k == 1L) 0L else sum(widths[seq_len(k - 1L)])
  keep <- rep(FALSE, rec)
  keep[(off + 1L):(off + widths[k])] <- TRUE
  raw[rep(keep, length.out = length(raw))]
}

# zoom records are a flat array of 32-byte summaries
.bw_decode_zoom <- function(rd, raw0) {
  big <- rd$big
  n <- length(raw0) %/% 32L
  if (n == 0L) return(NULL)
  raw0 <- raw0[seq_len(32L * n)]
  f <- function(k) .bbi_field(raw0, rep(4L, 8L), k)
  list(id = .bw_u32v(f(1L), big), start = .bw_u32v(f(2L), big),
       end = .bw_u32v(f(3L), big), validCount = .bw_u32v(f(4L), big),
       min = .bw_f32v(f(5L), big), max = .bw_f32v(f(6L), big),
       sumData = .bw_f32v(f(7L), big), sumSquares = .bw_f32v(f(8L), big))
}


# ---------------------------------------------------------------------------
# reader lifecycle
# ---------------------------------------------------------------------------
bw_open <- function(path, max_blocks = 256L) {
  rd <- new.env(parent = emptyenv())
  rd$path   <- path
  rd$remote <- .bw_is_url(path)
  rd$nreads <- 0L
  rd$nbytes <- 0
  rd$maxBlocks <- as.integer(max_blocks)
  rd$coalesceGap <- 65536      # merge block reads separated by less than this
  rd$coalesceMax <- 8 * 1024^2 # but never build a single request bigger than this
  rd$head   <- NULL
  rd$idx    <- new.env(parent = emptyenv())
  rd$blocks <- new.env(parent = emptyenv())
  rd$blockord <- character(0)
  rd$chroms <- NULL

  if (rd$remote) {
    if (!requireNamespace("curl", quietly = TRUE))
      stop("reading bigWig over http(s) needs the 'curl' package", call. = FALSE)
    rd$handle <- curl::new_handle()
    curl::handle_setopt(rd$handle, useragent = "HiCarta", followlocation = TRUE,
                        tcp_keepalive = TRUE, connecttimeout = 20L)
    rd$size <- NULL
  } else {
    if (!file.exists(path)) stop("no such file: ", path, call. = FALSE)
    rd$con  <- file(path, "rb")
    rd$size <- file.info(path)$size
  }
  .bw_read_header(rd)
  .bw_read_chroms(rd)
  rd
}

bw_close <- function(rd) {
  if (isTRUE(rd$remote)) rd$handle <- NULL
  else if (!is.null(rd$con)) { try(close(rd$con), silent = TRUE); rd$con <- NULL }
  invisible(NULL)
}

.bw_readers <- new.env(parent = emptyenv())

bw_reader <- function(path, max_blocks = 256L) {
  hit <- .bw_readers[[path]]
  if (!is.null(hit)) return(hit)
  rd <- bw_open(path, max_blocks = max_blocks)
  .bw_readers[[path]] <- rd
  rd
}

bw_forget <- function(path = NULL) {
  keys <- if (is.null(path)) ls(.bw_readers) else path
  for (k in keys) {
    rd <- .bw_readers[[k]]
    if (!is.null(rd)) bw_close(rd)
    if (!is.null(.bw_readers[[k]])) rm(list = k, envir = .bw_readers)
  }
  invisible(NULL)
}

bw_io_stats <- function(rd) list(reads = rd$nreads, bytes = rd$nbytes)

# resolve a chromosome name, tolerating chr-prefix differences
.bw_chrom_id <- function(rd, chr) {
  ch <- .bw_read_chroms(rd)
  for (cc in unique(c(chr, sub("^chr", "", chr), paste0("chr", chr)))) {
    i <- match(cc, ch$name)
    if (!is.na(i)) return(list(id = ch$id[i], size = ch$size[i], name = ch$name[i]))
  }
  NULL
}


# ---------------------------------------------------------------------------
# bw_intervals(): full-resolution intervals overlapping chr:[start,end].
# Returns 1-based inclusive coordinates, matching rtracklayer::import().
# ---------------------------------------------------------------------------
bw_intervals <- function(rd, chr, start, end) {
  ci <- .bw_chrom_id(rd, chr)
  empty <- data.frame(start = numeric(0), end = numeric(0), value = numeric(0))
  if (is.null(ci)) return(empty)
  qs <- max(0, as.numeric(start) - 1)                    # to 0-based half-open
  qe <- min(ci$size, as.numeric(end))
  if (qe <= qs) return(empty)

  blk <- .bw_rtree_find(rd, rd$fullIndexOff, ci$id, qs, qe)
  if (!length(blk$offset)) return(empty)

  bufs <- .bw_blocks(rd, blk$offset, blk$size)
  S <- V <- E <- vector("list", length(blk$offset))
  for (i in seq_along(blk$offset)) {
    secs <- .bw_decode_wig(rd, bufs[[i]])
    for (s in secs) {
      if (s$id != ci$id) next
      keep <- s$end > qs & s$start < qe
      if (!any(keep)) next
      S[[i]] <- c(S[[i]], s$start[keep])
      E[[i]] <- c(E[[i]], s$end[keep])
      V[[i]] <- c(V[[i]], s$value[keep])
    }
  }
  st <- unlist(S, use.names = FALSE)
  en <- unlist(E, use.names = FALSE)
  va <- unlist(V, use.names = FALSE)
  if (!length(st)) return(empty)
  o <- order(st, en)
  # Kent's bigWigIntervalQuery (and therefore rtracklayer::import) clips the
  # returned intervals to the query window, so a bin straddling the edge comes
  # back truncated. Match that, or callers that bin by overlap would weight the
  # edge bins differently.
  data.frame(start = pmax(st[o] + 1, as.numeric(start)),
             end   = pmin(en[o], as.numeric(end)),
             value = va[o])
}


# ---------------------------------------------------------------------------
# bw_summary(): one value per bin over chr:[start,end].
#
# type = "mean" -> coverage-weighted mean over covered bases in the bin
# type = "max"  -> peak value in the bin
# Bins with no data are 0, matching rtracklayer's defaultValue = 0.
#
# Full-resolution data is used when the R-tree says the overlapping blocks are
# small enough (exact, and for a compact genome that is nearly always). For wide
# views it falls back to the bigWig's own precomputed zoom summaries, which is
# what IGV and Kent's tools do.
# ---------------------------------------------------------------------------
bw_summary <- function(rd, chr, start, end, nbins, type = "mean",
                       max_full_bytes = NULL) {
  # Full-resolution data gives the exact answer, but for a wide view it can be
  # megabytes where a zoom level would look identical for a few KB. Locally
  # bytes are nearly free, so prefer exactness; over the network, don't.
  if (is.null(max_full_bytes))
    max_full_bytes <- if (isTRUE(rd$remote)) 1024^2 else 16 * 1024^2
  nbins <- max(1L, as.integer(nbins))
  type  <- if (isTRUE(type %in% c("mean", "max"))) type else "mean"
  out   <- rep(0, nbins)

  ci <- .bw_chrom_id(rd, chr)
  if (is.null(ci)) return(out)
  qs <- max(0, as.numeric(start) - 1)
  qe <- min(ci$size, as.numeric(end))
  if (qe <= qs) return(out)

  edges <- seq(qs, qe, length.out = nbins + 1L)
  wsum  <- rep(0, nbins)                                 # covered bases per bin
  vsum  <- rep(0, nbins)                                 # value * bases
  vmax  <- rep(-Inf, nbins)

  # Accumulate (start, end, value[, covered]) records into the bins.
  # `cov` is the number of bases actually carrying signal (= span for
  # full-resolution data, = validCount for a zoom record).
  acc <- function(st0, en0, va, cov = NULL) {
    span0 <- en0 - st0
    st <- pmax(st0, qs); en <- pmin(en0, qe)
    keep <- en > st & is.finite(va) & span0 > 0
    if (!any(keep)) return(invisible(NULL))
    st <- st[keep]; en <- en[keep]; va <- va[keep]
    # clipping must shrink the covered-base count proportionally, otherwise a
    # sparsely covered zoom record straddling the edge is over-weighted
    cov <- if (is.null(cov)) en - st
           else pmax(0, cov[keep] * (en - st) / span0[keep])

    b0 <- pmax(1L, findInterval(st, edges, rightmost.closed = TRUE))
    b1 <- pmin(nbins, findInterval(en - 1e-9, edges, rightmost.closed = TRUE))
    b1 <- pmax(b0, b1)

    # Fast path: records living entirely inside one bin (the vast majority).
    one <- b0 == b1
    if (any(one)) {
      bb <- b0[one]; ww <- cov[one]; vv <- va[one]
      s1 <- rowsum(ww,      bb, reorder = TRUE)
      s2 <- rowsum(vv * ww, bb, reorder = TRUE)
      ix <- as.integer(rownames(s1))
      wsum[ix] <<- wsum[ix] + as.vector(s1)
      vsum[ix] <<- vsum[ix] + as.vector(s2)
      mx <- tapply(vv, bb, max)
      jx <- as.integer(names(mx))
      vmax[jx] <<- pmax(vmax[jx], as.vector(mx))
    }
    # Slow path: records straddling a bin boundary, split by overlap.
    for (i in which(!one)) {
      for (b in b0[i]:b1[i]) {
        lo <- max(st[i], edges[b]); hi <- min(en[i], edges[b + 1L])
        if (hi <= lo) next
        w <- cov[i] * (hi - lo) / (en[i] - st[i])
        wsum[b] <<- wsum[b] + w
        vsum[b] <<- vsum[b] + va[i] * w
        if (va[i] > vmax[b]) vmax[b] <<- va[i]
      }
    }
    invisible(NULL)
  }

  # -- decide between full data and a zoom level ---------------------------
  # A zoom level is only usable if its reduction is finer than the bin, else it
  # smears signal across neighbouring bins. When none is fine enough, Kent's
  # reader falls back to full data and so do we, regardless of size.
  want <- (qe - qs) / nbins / 2
  cand <- if (nrow(rd$zoom)) which(rd$zoom$reduction <= want) else integer(0)
  zi   <- if (length(cand)) cand[length(cand)] else NA_integer_

  full <- .bw_rtree_find(rd, rd$fullIndexOff, ci$id, qs, qe)
  use_full <- length(full$offset) > 0 &&
              (is.na(zi) || sum(full$size) <= max_full_bytes)

  if (use_full) {
    bufs <- .bw_blocks(rd, full$offset, full$size)
    for (i in seq_along(full$offset)) {
      secs <- .bw_decode_wig(rd, bufs[[i]])
      for (s in secs) if (s$id == ci$id) acc(s$start, s$end, s$value)
    }
  } else {
    if (is.na(zi)) return(out)
    zblk <- .bw_rtree_find(rd, rd$zoom$indexOffset[zi], ci$id, qs, qe)
    zbufs <- .bw_blocks(rd, zblk$offset, zblk$size)
    for (i in seq_along(zblk$offset)) {
      z <- .bw_decode_zoom(rd, zbufs[[i]])
      if (is.null(z)) next
      keep <- z$id == ci$id & z$end > qs & z$start < qe
      if (!any(keep)) next
      # mean of a zoom record is sumData/validCount; weight by covered bases
      n  <- z$validCount[keep]
      mu <- ifelse(n > 0, z$sumData[keep] / n, 0)
      acc(z$start[keep], z$end[keep],
          if (type == "max") z$max[keep] else mu, cov = n)
    }
  }

  if (type == "max") {
    out <- ifelse(is.finite(vmax), vmax, 0)
  } else {
    out <- ifelse(wsum > 0, vsum / wsum, 0)
  }
  out[!is.finite(out)] <- 0
  out
}

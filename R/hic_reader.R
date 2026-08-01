# ============================================================================
# hic_reader.R  -  Stateful .hic reader (pure R, no compiler required).
#
# WHY THIS EXISTS
# ---------------
# strawr is a port of the `dump` command line tool: it is stateless. Every
# strawr::straw() call re-opens the file FOUR times (two HiCFile constructions
# inside straw() plus readHicBpResolutions/readHicNormTypes in the caller),
# each with a fresh libcurl handle -- so a fresh TCP+TLS handshake -- and each
# HiCFile construction re-reads the first 100 KB of the file. Over HTTPS a
# 256 px tile therefore costs ~5 handshakes and ~400 KB of redundant header,
# and one screen of ~20 tiles moved more bytes than downloading the whole file.
#
# This reader does what Juicebox does instead: open once, keep it open.
#   * ONE curl handle per file, reused  -> keep-alive, no repeated handshake
#   * header parsed once
#   * footer parsed ONCE into three lookup tables (matrix index, expected
#     values, normalization-vector index). strawr re-parses the footer on
#     every query; we never touch it again.
#   * block index cached per (chr pair, unit, resolution)
#   * decompressed blocks in an LRU cache -> pan/zoom hits RAM
#   * normalization vectors cached per (type, chrom, unit, resolution)
#
# FORMAT REFERENCE
# ----------------
# Ported from aidenlab/straw C++/straw.cpp (MIT). Validated byte-for-byte
# against real .hic files: inter-chromosomal record sums reproduce the
# `sumCounts` field exactly, and intra-chromosomal sums satisfy the identity
#     sumCounts == 2 * sum(stored) - sum(diagonal)
# (off-diagonal cells are counted twice by the writer, stored once) across
# every chromosome, resolution and file tested.
#
# AGREEMENT WITH strawr
# ---------------------
# Records are identical to strawr::straw() for every region, resolution and
# normalization tested. With a normalization applied the values differ by up to
# 6e-8 relative, because straw casts the normalized value to float32
# (`static_cast<float>(c / (c1Norm[binX] * c2Norm[binY]))`) while this reader
# keeps double precision. Compare with a tolerance of ~1e-5, not exactly.
#
# A strawr bug worth knowing about: strawr::readHicNormTypes() has no HTTP
# branch. It reads from HiCFile::fin, the local ifstream, which is never opened
# for a URL -- so it parses garbage lengths off a failed stream, spins ~30 s of
# pure CPU, and returns a wrong answer (normalizations missing). Never call it
# on a URL; hic_meta() answers correctly from the parsed footer instead.
#
# PUBLIC API
# ----------
#   hic_reader(path)        cached, one reader per path per session  <- use this
#   hic_open(path)          force a fresh reader
#   hic_meta(rd)            list(chroms, resolutions, norms, version, genomeId)
#   hic_records(rd, ...)    data.frame(x, y, counts) -- same shape as strawr::straw()
#   hic_close(rd)           release the handle / connection
#   hic_io_stats(rd)        list(reads, bytes) for diagnostics
#
# `path` may be a local file or an http(s):// URL. Requires the `curl` package
# for URLs only; everything else is base R (readBin + memDecompress).
# ============================================================================


# ---------------------------------------------------------------------------
# little-endian scalar readers over a rawConnection
#
# R's readBin cannot read 8-byte integers, so int64 is assembled from two
# unsigned 32-bit halves into a double. Every int64 in the .hic format is a
# file offset or a length (non-negative, < 2^53), so this is exact.
# ---------------------------------------------------------------------------
.rc_i8  <- function(con) readBin(con, "integer", size = 1, n = 1, signed = TRUE)
.rc_i16 <- function(con) readBin(con, "integer", size = 2, n = 1, signed = TRUE,
                                 endian = "little")
.rc_i32 <- function(con) readBin(con, "integer", size = 4, n = 1,
                                 endian = "little")
.rc_f32 <- function(con) readBin(con, "double", size = 4, n = 1,
                                 endian = "little")
.rc_f64 <- function(con) readBin(con, "double", size = 8, n = 1,
                                 endian = "little")

.raw_u32 <- function(r) sum(as.numeric(r) * c(1, 256, 65536, 16777216))

.rc_i64 <- function(con) {
  r <- readBin(con, "raw", n = 8)
  .raw_u32(r[1:4]) + .raw_u32(r[5:8]) * 4294967296
}

# null-terminated string
.rc_cstr <- function(con) {
  out <- raw(0)
  repeat {
    b <- readBin(con, "raw", n = 1)
    if (length(b) == 0L || b[1] == as.raw(0)) break
    out <- c(out, b)
  }
  if (length(out) == 0L) "" else rawToChar(out)
}

# version-dependent readers
.rc_i64_or_i32 <- function(con, v9) if (v9) .rc_i64(con) else .rc_i32(con)
.rc_f32_or_f64 <- function(con, v9) if (v9) .rc_f32(con) else .rc_f64(con)

# read n floats (v9) or doubles (v8) as one vectorised call
.rc_vals <- function(con, n, v9) {
  if (n <= 0) return(numeric(0))
  readBin(con, "double", size = if (v9) 4L else 8L, n = n, endian = "little")
}

# ---------------------------------------------------------------------------
# de-interleave fixed-width fields out of a packed record array.
# widths: byte width of each field; k: which field to extract.
# ---------------------------------------------------------------------------
.deint <- function(raw, widths, k) {
  rec  <- sum(widths)
  off  <- if (k == 1L) 0L else sum(widths[seq_len(k - 1L)])
  keep <- rep(FALSE, rec)
  keep[(off + 1L):(off + widths[k])] <- TRUE
  raw[rep(keep, length.out = length(raw))]
}


# ---------------------------------------------------------------------------
# byte source: one reused curl handle (remote) or one open connection (local)
# ---------------------------------------------------------------------------
.hic_is_url <- function(p) grepl("^https?://", p)

.hic_range <- function(rd, pos, n) {
  n <- as.numeric(n)
  if (n <= 0) return(raw(0))
  rd$nreads <- rd$nreads + 1L
  rd$nbytes <- rd$nbytes + n

  if (!rd$remote) {
    seek(rd$con, where = pos, origin = "start")
    return(readBin(rd$con, "raw", n = n))
  }

  # Reusing rd$handle across calls is the whole point: libcurl keeps the
  # connection alive, so only the first request pays for TCP + TLS.
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
    if (is.null(rd$size)) {
      cl <- h[["content-length"]]
      if (!is.null(cl) && r$status_code == 200L) rd$size <- as.numeric(cl)
    }
    if (is.null(rd$size))
      stop("server did not report the file size (no Content-Range); ",
           "range requests may not be supported by this host", call. = FALSE)
  }
  r$content
}


# ---------------------------------------------------------------------------
# header
# ---------------------------------------------------------------------------
.hic_read_header <- function(rd) {
  raw0 <- .hic_range(rd, 0, min(100000, rd$size %||% 100000))
  con  <- rawConnection(raw0, "rb"); on.exit(close(con))

  magic <- .rc_cstr(con)
  if (!grepl("^HIC", magic))
    stop("not a .hic file (magic string missing): ", rd$path, call. = FALSE)

  rd$version <- .rc_i32(con)
  if (rd$version < 6L)
    stop("hic version ", rd$version, " is not supported", call. = FALSE)
  rd$v9     <- rd$version > 8L
  rd$master <- .rc_i64(con)
  rd$genomeId <- .rc_cstr(con)
  if (rd$v9) {
    rd$nviPosition <- .rc_i64(con)
    rd$nviLength   <- .rc_i64(con)
  }

  nattr <- .rc_i32(con)
  attrs <- list()
  for (i in seq_len(nattr)) {
    k <- .rc_cstr(con); v <- .rc_cstr(con); attrs[[k]] <- v
  }
  rd$attributes <- attrs

  nchr  <- .rc_i32(con)
  nm    <- character(nchr); ln <- numeric(nchr)
  for (i in seq_len(nchr)) {
    nm[i] <- .rc_cstr(con)
    ln[i] <- if (rd$v9) .rc_i64(con) else .rc_i32(con)
  }
  rd$chroms <- data.frame(index = seq_len(nchr) - 1L, name = nm, length = ln,
                          stringsAsFactors = FALSE)

  nres <- .rc_i32(con)
  rd$resolutions <- if (nres > 0L)
    readBin(con, "integer", size = 4, n = nres, endian = "little") else integer(0)
  invisible(rd)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Cache-key builder. Numbers MUST be formatted without scientific notation:
# a resolution read from the file is an integer (100000) but one supplied by a
# caller is a double (1e+05), and paste() would render those differently,
# silently missing the cache entry.
.k <- function(...) {
  paste(vapply(list(...), function(z)
    if (is.numeric(z)) sprintf("%.0f", z) else as.character(z),
    character(1)), collapse = "\r")
}


# ---------------------------------------------------------------------------
# footer: parsed ONCE into three lookup tables.
#
# Layout from master to EOF:
#   nBytes                                (int64 v9 / int32 v8)
#   nEntries, then per entry: key cstr, position int64, size int32   <- matrices
#   nExpectedValues, then per entry: unit, binSize, nValues, values,
#                                    nFactors, (chrIdx, factor)*      <- NONE
#   nExpectedValues, then per entry: type, unit, binSize, nValues, values,
#                                    nFactors, (chrIdx, factor)*      <- normalized
#   nEntries, then per entry: type, chrIdx, unit, resolution,
#                            position int64, size (int64 v9 / int32 v8)
#
# The last two sections are ABSENT in v8 files written without any
# normalization -- the footer simply ends. Real files do this, so every
# section is guarded by a remaining-bytes check.
# ---------------------------------------------------------------------------
.hic_read_footer <- function(rd) {
  if (!is.null(rd$footerTbl)) return(rd$footerTbl)

  tail_len <- rd$size - rd$master
  # For files with normalization the region after `master` also holds the
  # normalization vectors themselves, which can dwarf the index. Read a
  # bounded chunk first and only fetch the whole tail if the parse needs it.
  want <- min(tail_len, 8 * 1024^2)
  raw0 <- .hic_range(rd, rd$master, want)
  tbl  <- tryCatch(.hic_parse_footer(rd, raw0, complete = (want >= tail_len)),
                   error = function(e) NULL)
  if (is.null(tbl) && want < tail_len) {
    raw0 <- .hic_range(rd, rd$master, tail_len)
    tbl  <- .hic_parse_footer(rd, raw0, complete = TRUE)
  }
  if (is.null(tbl)) stop("could not parse .hic footer: ", rd$path, call. = FALSE)
  rd$footerTbl <- tbl
  tbl
}

.hic_parse_footer <- function(rd, raw0, complete) {
  con <- rawConnection(raw0, "rb"); on.exit(close(con))
  v9  <- rd$v9
  n   <- length(raw0)
  left <- function() n - seek(con, where = NA)

  nBytes <- .rc_i64_or_i32(con, v9)

  # --- matrix index -------------------------------------------------------
  ne  <- .rc_i32(con)
  mkey <- character(ne); mpos <- numeric(ne)
  for (i in seq_len(ne)) {
    mkey[i] <- .rc_cstr(con)
    mpos[i] <- .rc_i64(con)
    .rc_i32(con)                      # size in bytes, unused
  }
  matrixIndex <- stats::setNames(as.list(mpos), mkey)

  expected <- list()

  # --- expected value vectors (normalization NONE) ------------------------
  if (left() >= 4) {
    nev <- .rc_i32(con)
    for (i in seq_len(nev)) {
      unit <- .rc_cstr(con); binSize <- .rc_i32(con)
      nV   <- .rc_i64_or_i32(con, v9)
      vals <- .rc_vals(con, nV, v9)
      nf   <- .rc_i32(con)
      fac  <- numeric(0); fci <- integer(0)
      for (j in seq_len(nf)) {
        fci <- c(fci, .rc_i32(con)); fac <- c(fac, .rc_f32_or_f64(con, v9))
      }
      expected[[.k("NONE", unit, binSize)]] <-
        list(values = vals, factorChr = fci, factor = fac)
    }
  }

  # --- normalized expected value vectors ---------------------------------
  if (left() >= 4) {
    nev <- .rc_i32(con)
    for (i in seq_len(nev)) {
      typ <- .rc_cstr(con); unit <- .rc_cstr(con); binSize <- .rc_i32(con)
      nV   <- .rc_i64_or_i32(con, v9)
      vals <- .rc_vals(con, nV, v9)
      nf   <- .rc_i32(con)
      fac  <- numeric(0); fci <- integer(0)
      for (j in seq_len(nf)) {
        fci <- c(fci, .rc_i32(con)); fac <- c(fac, .rc_f32_or_f64(con, v9))
      }
      expected[[.k(typ, unit, binSize)]] <-
        list(values = vals, factorChr = fci, factor = fac)
    }
  }

  # --- normalization vector index ----------------------------------------
  normIndex <- list()
  if (left() >= 4) {
    ne <- .rc_i32(con)
    for (i in seq_len(ne)) {
      typ <- .rc_cstr(con); ci <- .rc_i32(con)
      unit <- .rc_cstr(con); res <- .rc_i32(con)
      pos <- .rc_i64(con)
      sz  <- if (v9) .rc_i64(con) else .rc_i32(con)
      normIndex[[.k(typ, ci, unit, res)]] <- c(pos, sz)
    }
  }

  list(matrixIndex = matrixIndex, expected = expected, normIndex = normIndex,
       nBytes = nBytes)
}


# ---------------------------------------------------------------------------
# block index for one (chr pair, unit, resolution). Cached.
#
# At the matrix position: c1 int32, c2 int32, nRes int32, then nRes
# MatrixZoomData records. Each record's header length depends on the unit
# string ("BP" -> 3 bytes with terminator, "FRAG" -> 5), so the first byte is
# probed to size the header read, exactly as straw does.
# ---------------------------------------------------------------------------
.hic_block_index <- function(rd, c1, c2, unit, res) {
  key <- .k(c1, c2, unit, res)
  hit <- rd$blockidx[[key]]
  if (!is.null(hit)) return(hit)

  ft <- .hic_read_footer(rd)
  p  <- ft$matrixIndex[[paste0(c1, "_", c2)]]
  if (is.null(p))
    stop(sprintf("this file has no matrix for chromosome pair %d_%d", c1, c2),
         call. = FALSE)

  hd <- rawConnection(.hic_range(rd, p, 12), "rb")
  .rc_i32(hd); .rc_i32(hd); nRes <- .rc_i32(hd); close(hd)
  p <- p + 12

  out <- NULL
  for (i in seq_len(nRes)) {
    first <- .hic_range(rd, p, 1)
    hs <- 5L * 4L + 4L * 4L +
      if (first[1] == charToRaw("B")) 3L
      else if (first[1] == charToRaw("F")) 5L
      else stop("unrecognised unit in matrix zoom data", call. = FALSE)

    hc <- rawConnection(.hic_range(rd, p, hs), "rb")
    u  <- .rc_cstr(hc)
    .rc_i32(hc)                                   # legacy zoom index
    sumCounts <- .rc_f32(hc)
    .rc_f32(hc); .rc_f32(hc); .rc_f32(hc)         # occupied, stdDev, pct95
    binSize         <- .rc_i32(hc)
    blockBinCount   <- .rc_i32(hc)
    blockColumnCount<- .rc_i32(hc)
    nBlocks         <- .rc_i32(hc)
    close(hc)

    chunk <- nBlocks * 16L
    if (identical(u, unit) && binSize == res) {
      bc  <- rawConnection(.hic_range(rd, p + hs, chunk), "rb")
      num <- integer(nBlocks); bpos <- numeric(nBlocks); bsz <- integer(nBlocks)
      for (b in seq_len(nBlocks)) {
        num[b]  <- .rc_i32(bc)
        bpos[b] <- .rc_i64(bc)
        bsz[b]  <- .rc_i32(bc)
      }
      close(bc)
      out <- list(sumCounts = sumCounts, blockBinCount = blockBinCount,
                  blockColumnCount = blockColumnCount, binSize = binSize,
                  num = num, pos = bpos, size = bsz)
      break
    }
    p <- p + hs + chunk
  }
  if (is.null(out))
    stop(sprintf("resolution %s %s is not present in this file", res, unit),
         call. = FALSE)
  rd$blockidx[[key]] <- out
  out
}


# ---------------------------------------------------------------------------
# decompress + decode one block -> list(x, y, v) of bin indices and counts
# ---------------------------------------------------------------------------
.hic_decode_block <- function(rd, cmp) {
  u   <- memDecompress(cmp, type = "gzip")
  con <- rawConnection(u, "rb"); on.exit(close(con))

  n <- .rc_i32(con)
  empty <- list(x = integer(0), y = integer(0), v = numeric(0))
  if (is.na(n) || n <= 0L) return(empty)

  if (rd$version < 7L) {
    packed <- readBin(con, "raw", n = n * 12L)
    return(list(
      x = readBin(.deint(packed, c(4L, 4L, 4L), 1L), "integer", size = 4,
                  n = n, endian = "little"),
      y = readBin(.deint(packed, c(4L, 4L, 4L), 2L), "integer", size = 4,
                  n = n, endian = "little"),
      v = readBin(.deint(packed, c(4L, 4L, 4L), 3L), "double", size = 4,
                  n = n, endian = "little")))
  }

  bxo <- .rc_i32(con); byo <- .rc_i32(con)
  useShort <- .rc_i8(con) == 0L          # note: inverted, as in straw
  shortX <- TRUE; shortY <- TRUE
  if (rd$version > 8L) {
    shortX <- .rc_i8(con) == 0L
    shortY <- .rc_i8(con) == 0L
  }
  type <- .rc_i8(con)

  wx <- if (shortX) 2L else 4L
  wv <- if (useShort) 2L else 4L

  if (type == 1L) {
    # row-major, variable length rows: sequential scan is unavoidable, but
    # every row's payload is read in one vectorised call.
    X <- integer(n); Y <- integer(n); V <- numeric(n); k <- 0L
    rowCount <- if (shortY) .rc_i16(con) else .rc_i32(con)
    if (is.na(rowCount)) return(empty)
    for (r in seq_len(rowCount)) {
      binY <- byo + (if (shortY) .rc_i16(con) else .rc_i32(con))
      colCount <- if (shortX) .rc_i16(con) else .rc_i32(con)
      if (is.na(colCount) || colCount <= 0L) next

      if (shortX && useShort) {
        # x and count are both int16 and interleaved: one read, de-interleave
        both <- readBin(con, "integer", size = 2, n = 2L * colCount,
                        signed = TRUE, endian = "little")
        xs <- bxo + both[seq.int(1L, length(both), by = 2L)]
        vs <- as.numeric(both[seq.int(2L, length(both), by = 2L)])
      } else {
        packed <- readBin(con, "raw", n = colCount * (wx + wv))
        xs <- bxo + readBin(.deint(packed, c(wx, wv), 1L), "integer",
                            size = wx, n = colCount,
                            signed = TRUE, endian = "little")
        vs <- if (useShort)
          as.numeric(readBin(.deint(packed, c(wx, wv), 2L), "integer",
                             size = 2, n = colCount, signed = TRUE,
                             endian = "little"))
        else
          readBin(.deint(packed, c(wx, wv), 2L), "double", size = 4,
                  n = colCount, endian = "little")
      }
      idx <- k + seq_len(colCount)
      X[idx] <- xs; Y[idx] <- binY; V[idx] <- vs
      k <- k + colCount
    }
    if (k < n) { X <- X[seq_len(k)]; Y <- Y[seq_len(k)]; V <- V[seq_len(k)] }
    return(list(x = X, y = Y, v = V))
  }

  if (type == 2L) {
    # dense rectangle; fully vectorised
    nPts <- .rc_i32(con); w <- .rc_i16(con)
    if (is.na(nPts) || nPts <= 0L || is.na(w) || w <= 0L) return(empty)
    vals <- if (useShort)
      as.numeric(readBin(con, "integer", size = 2, n = nPts, signed = TRUE,
                         endian = "little"))
    else readBin(con, "double", size = 4, n = nPts, endian = "little")
    i0   <- seq_len(length(vals)) - 1L
    row  <- i0 %/% w
    col  <- i0 - row * w
    keep <- if (useShort) vals != -32768 else !is.na(vals)
    return(list(x = bxo + col[keep], y = byo + row[keep], v = vals[keep]))
  }

  stop("unknown .hic block type ", type, call. = FALSE)
}

# LRU-cached block fetch
.hic_block <- function(rd, pos, size) {
  if (size <= 0) return(list(x = integer(0), y = integer(0), v = numeric(0)))
  key <- sprintf("%.0f", pos)
  hit <- rd$blocks[[key]]
  if (!is.null(hit)) {
    rd$blockord <- c(setdiff(rd$blockord, key), key)
    return(hit)
  }
  val <- .hic_decode_block(rd, .hic_range(rd, pos, size))
  rd$blocks[[key]] <- val
  rd$blockord <- c(rd$blockord, key)
  if (length(rd$blockord) > rd$maxBlocks) {
    drop <- rd$blockord[seq_len(length(rd$blockord) - rd$maxBlocks)]
    rd$blockord <- setdiff(rd$blockord, drop)
    for (d in drop) rm(list = d, envir = rd$blocks)
  }
  val
}


# ---------------------------------------------------------------------------
# normalization vector, cached
# ---------------------------------------------------------------------------
.hic_norm_vector <- function(rd, type, ci, unit, res) {
  key <- .k(type, ci, unit, res)
  hit <- rd$normvec[[key]]
  if (!is.null(hit)) return(hit)
  ft  <- .hic_read_footer(rd)
  ent <- ft$normIndex[[key]]
  if (is.null(ent))
    stop(sprintf("no %s normalization vector for chromosome index %d at %s %s",
                 type, ci, res, unit), call. = FALSE)
  con <- rawConnection(.hic_range(rd, ent[1], ent[2]), "rb")
  on.exit(close(con))
  nV  <- .rc_i64_or_i32(con, rd$v9)
  val <- .rc_vals(con, nV, rd$v9)
  rd$normvec[[key]] <- val
  val
}


# ---------------------------------------------------------------------------
# which blocks cover a region (bin units)
# ---------------------------------------------------------------------------
.hic_blocks_v8 <- function(ri, bbc, bcc, intra) {
  col1 <- ri[1] %/% bbc; col2 <- (ri[2] + 1) %/% bbc
  row1 <- ri[3] %/% bbc; row2 <- (ri[4] + 1) %/% bbc
  s <- as.vector(outer(row1:row2 * bcc, col1:col2, "+"))
  if (intra) s <- c(s, as.vector(outer(col1:col2 * bcc, row1:row2, "+")))
  sort(unique(as.integer(s)))
}

.hic_blocks_v9_intra <- function(ri, bbc, bcc) {
  lo <- (ri[1] + ri[3]) %/% 2 %/% bbc
  hi <- (ri[2] + ri[4]) %/% 2 %/% bbc + 1
  nd <- as.integer(log2(1 + abs(ri[1] - ri[4]) / sqrt(2) / bbc))
  fd <- as.integer(log2(1 + abs(ri[2] - ri[3]) / sqrt(2) / bbc))
  near <- min(nd, fd)
  if ((ri[1] > ri[4] && ri[2] < ri[3]) || (ri[2] > ri[3] && ri[1] < ri[4]))
    near <- 0L
  far <- max(nd, fd) + 1L
  sort(unique(as.integer(as.vector(outer(near:far * bcc, lo:hi, "+")))))
}


# ---------------------------------------------------------------------------
# reader lifecycle
# ---------------------------------------------------------------------------
hic_open <- function(path, max_blocks = 256L) {
  rd <- new.env(parent = emptyenv())
  rd$path   <- path
  rd$remote <- .hic_is_url(path)
  rd$nreads <- 0L
  rd$nbytes <- 0
  rd$maxBlocks <- as.integer(max_blocks)
  rd$blockidx <- new.env(parent = emptyenv())
  rd$blocks   <- new.env(parent = emptyenv())
  rd$normvec  <- new.env(parent = emptyenv())
  rd$blockord <- character(0)
  rd$footerTbl <- NULL

  if (rd$remote) {
    if (!requireNamespace("curl", quietly = TRUE))
      stop("reading .hic over http(s) needs the 'curl' package", call. = FALSE)
    rd$handle <- curl::new_handle()
    curl::handle_setopt(rd$handle,
                        useragent      = "HiCarta",
                        followlocation = TRUE,
                        tcp_keepalive  = TRUE,
                        connecttimeout = 20L)
    rd$size <- NULL                    # learned from the first Content-Range
  } else {
    if (!file.exists(path)) stop("no such file: ", path, call. = FALSE)
    rd$con  <- file(path, "rb")
    rd$size <- file.info(path)$size
  }
  .hic_read_header(rd)
  rd
}

hic_close <- function(rd) {
  if (isTRUE(rd$remote)) {
    rd$handle <- NULL
  } else if (!is.null(rd$con)) {
    try(close(rd$con), silent = TRUE); rd$con <- NULL
  }
  invisible(NULL)
}

# ---- session-wide reader cache: ONE reader per path -----------------------
.hic_readers <- new.env(parent = emptyenv())

hic_reader <- function(path, max_blocks = 256L) {
  hit <- .hic_readers[[path]]
  if (!is.null(hit)) return(hit)
  rd <- hic_open(path, max_blocks = max_blocks)
  .hic_readers[[path]] <- rd
  rd
}

hic_forget <- function(path = NULL) {
  keys <- if (is.null(path)) ls(.hic_readers) else path
  for (k in keys) {
    rd <- .hic_readers[[k]]
    if (!is.null(rd)) hic_close(rd)
    if (!is.null(.hic_readers[[k]])) rm(list = k, envir = .hic_readers)
  }
  invisible(NULL)
}

hic_io_stats <- function(rd) list(reads = rd$nreads, bytes = rd$nbytes)


# ---------------------------------------------------------------------------
# metadata (shapes match strawr::readHicChroms / BpResolutions / NormTypes)
# ---------------------------------------------------------------------------
hic_meta <- function(rd) {
  norms <- names(.hic_read_footer(rd)$normIndex)
  norms <- if (length(norms)) unique(vapply(strsplit(norms, "\r", fixed = TRUE),
                                           `[`, "", 1L)) else character(0)
  list(chroms      = rd$chroms,
       resolutions = rd$resolutions,
       norms       = unique(c("NONE", sort(norms))),
       version     = rd$version,
       genomeId    = rd$genomeId,
       attributes  = rd$attributes)
}


# ---------------------------------------------------------------------------
# hic_records(): the query. Returns data.frame(x, y, counts) where x and y are
# bin start positions in bp -- identical in shape and semantics to
# strawr::straw(), so it is a drop-in replacement.
# ---------------------------------------------------------------------------
hic_records <- function(rd, chr1, start1, end1, chr2 = chr1,
                        start2 = start1, end2 = end1,
                        resolution, normalization = "NONE", unit = "BP") {
  ci <- function(nm) {
    i <- match(nm, rd$chroms$name)
    if (is.na(i)) {
      # tolerate chr-prefix mismatch in either direction
      alt <- if (grepl("^chr", nm)) sub("^chr", "", nm) else paste0("chr", nm)
      i <- match(alt, rd$chroms$name)
    }
    if (is.na(i)) stop("chromosome '", nm, "' is not in this file; available: ",
                       paste(rd$chroms$name, collapse = ", "), call. = FALSE)
    rd$chroms$index[i]
  }
  i1 <- ci(chr1); i2 <- ci(chr2)

  # straw orders the pair by chromosome index and swaps the regions with it
  if (i1 <= i2) {
    c1 <- i1; c2 <- i2; o <- c(start1, end1, start2, end2)
  } else {
    c1 <- i2; c2 <- i1; o <- c(start2, end2, start1, end1)
  }
  o <- as.numeric(o)

  bi    <- .hic_block_index(rd, c1, c2, unit, resolution)
  intra <- (c1 == c2)
  bbc   <- bi$blockBinCount
  bcc   <- bi$blockColumnCount
  ri    <- o %/% resolution

  nums <- if (rd$v9 && intra) .hic_blocks_v9_intra(ri, bbc, bcc)
          else                .hic_blocks_v8(ri, bbc, bcc, intra)

  n1 <- n2 <- NULL
  if (!identical(normalization, "NONE")) {
    n1 <- .hic_norm_vector(rd, normalization, c1, unit, resolution)
    n2 <- if (intra) n1 else .hic_norm_vector(rd, normalization, c2, unit,
                                              resolution)
  }

  xs <- ys <- vs <- vector("list", length(nums))
  for (k in seq_along(nums)) {
    j <- match(nums[k], bi$num)
    if (is.na(j)) next
    b <- .hic_block(rd, bi$pos[j], bi$size[j])
    if (!length(b$v)) next

    x <- b$x * resolution
    y <- b$y * resolution
    keep <- (x >= o[1] & x <= o[2] & y >= o[3] & y <= o[4]) |
            (intra & y >= o[1] & y <= o[2] & x >= o[3] & x <= o[4])
    if (!any(keep)) next

    cnt <- b$v[keep]
    if (!is.null(n1)) cnt <- cnt / (n1[b$x[keep] + 1L] * n2[b$y[keep] + 1L])
    xs[[k]] <- x[keep]; ys[[k]] <- y[keep]; vs[[k]] <- cnt
  }

  data.frame(x = unlist(xs, use.names = FALSE),
             y = unlist(ys, use.names = FALSE),
             counts = unlist(vs, use.names = FALSE))
}

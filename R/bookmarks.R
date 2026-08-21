# ============================================================================
# bookmarks.R  -  bookmark <-> .xlsx exchange (catalog spec v0.3 §8).
#
# A bookmark stores WHERE to look (chr, x/y range) and — when a contact map
# was open — WHICH data it was (catalog_id, path(s), entry, normalization,
# pinned resolution, colour-scale max), so jumping to it can restore the
# whole picture. Import only ever APPENDS to the current list (per spec).
#
# xlsx columns: bookmark_name, catalog_id, path, entry, chr, start, end,
#               chr_y, ystart, yend, norm, resolution, vmax, comment
# Required: bookmark_name, chr, start, end. Broken rows are excluded and
# reported with the name and the reason, like the catalog's own validation.
#
# `chr` is the X axis and `chr_y` the Y axis; they differ only for an
# inter-chromosome (trans) view. An empty or missing chr_y means "same as chr",
# which is what every bookmark written before trans views existed meant.
# ============================================================================

if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a)) b else a

.bm_num <- function(x) suppressWarnings(as.numeric(x))

# in-memory bookmark list -> the data.frame written by the export button
bookmarks_to_df <- function(bms) {
  empty <- data.frame(bookmark_name = character(0), catalog_id = numeric(0),
                      path = character(0), entry = character(0),
                      chr = character(0), start = numeric(0), end = numeric(0),
                      chr_y = character(0),
                      ystart = numeric(0), yend = numeric(0),
                      norm = character(0), resolution = numeric(0),
                      vmax = numeric(0), comment = character(0),
                      stringsAsFactors = FALSE)
  if (length(bms) == 0) return(empty)
  do.call(rbind, lapply(unname(bms), function(b) data.frame(
    bookmark_name = as.character(b$name %||% ""),
    catalog_id    = .bm_num(b$cat_id %||% NA),
    path          = as.character(b$path %||% ""),
    entry         = as.character(b$entry %||% ""),
    chr           = as.character(b$chr %||% ""),
    start         = .bm_num(b$x0 %||% NA),
    end           = .bm_num(b$x1 %||% NA),
    chr_y         = as.character(b$chr_y %||% b$chr %||% ""),
    ystart        = .bm_num(b$y0 %||% NA),
    yend          = .bm_num(b$y1 %||% NA),
    norm          = as.character(b$norm %||% ""),
    resolution    = .bm_num(b$resolution %||% NA),
    vmax          = .bm_num(b$vmax %||% NA),
    comment       = as.character(b$comment %||% ""),
    stringsAsFactors = FALSE)))
}

# .xlsx -> list(ok, rows = bookmark-shaped lists WITHOUT ids,
#               errors = data.frame(row, name, message))
# Reuses catalog_fetch() (URL download / locked-file copy) from catalog.R.
read_bookmarks <- function(src) {
  if (is.null(src) || !nzchar(trimws(src)))
    return(list(ok = FALSE, fatal = tr("bm_v_no_file")))
  path <- catalog_fetch(src)
  on.exit(unlink(path), add = TRUE)
  raw <- suppressMessages(
    readxl::read_excel(path, sheet = 1, col_types = "text",
                       .name_repair = "unique"))
  df <- as.data.frame(raw, stringsAsFactors = FALSE)
  if (nrow(df) > 0) for (j in seq_along(df)) {
    x <- as.character(df[[j]])
    df[[j]] <- ifelse(is.na(x), NA_character_, trimws(x))
  }
  canon <- tolower(trimws(names(df)))
  col <- function(key) {
    j <- which(canon == key)[1]
    if (is.na(j)) rep(NA_character_, nrow(df)) else df[[j]]
  }
  need <- setdiff(c("bookmark_name", "chr", "start", "end"), canon)
  if (length(need) > 0)
    return(list(ok = FALSE,
                fatal = sprintf(tr("cat_v_req_missing"),
                                paste(need, collapse = ", "))))

  nm  <- col("bookmark_name"); ch <- col("chr"); chy <- col("chr_y")
  x0  <- .bm_num(col("start"));  x1 <- .bm_num(col("end"))
  y0  <- .bm_num(col("ystart")); y1 <- .bm_num(col("yend"))
  cid <- .bm_num(col("catalog_id"))
  pth <- col("path"); ent <- col("entry"); nrmv <- col("norm")
  res <- .bm_num(col("resolution")); vmx <- .bm_num(col("vmax"))
  cmt <- col("comment")

  rows <- list(); errors <- list()
  bad <- function(i, msg) {
    errors[[length(errors) + 1L]] <<- data.frame(
      row = i + 1L, name = if (is.na(nm[i])) "" else nm[i],
      message = msg, stringsAsFactors = FALSE)
  }
  for (i in seq_len(nrow(df))) {
    # skip fully empty rows silently
    vals <- unlist(df[i, ], use.names = FALSE)
    if (all(is.na(vals) | !nzchar(vals))) next
    if (is.na(nm[i]) || !nzchar(nm[i])) { bad(i, tr("bm_v_name"));  next }
    if (is.na(ch[i]) || !nzchar(ch[i])) { bad(i, tr("bm_v_chr"));   next }
    if (!is.finite(x0[i]) || !is.finite(x1[i]) || x1[i] <= x0[i]) {
      bad(i, tr("bm_v_range")); next
    }
    rows[[length(rows) + 1L]] <- list(
      name = nm[i], chr = ch[i],
      chr_y = if (!is.na(chy[i]) && nzchar(chy[i])) chy[i] else ch[i],
      x0 = x0[i], x1 = x1[i],
      y0 = if (is.finite(y0[i])) y0[i] else x0[i],
      y1 = if (is.finite(y1[i])) y1[i] else x1[i],
      cat_id = if (is.finite(cid[i])) cid[i] else NA,
      path = if (is.na(pth[i])) "" else pth[i],
      entry = if (is.na(ent[i])) "" else ent[i],
      norm = if (is.na(nrmv[i])) "" else nrmv[i],
      resolution = if (is.finite(res[i])) res[i] else NA,
      vmax = if (is.finite(vmx[i])) vmx[i] else NA,
      comment = if (is.na(cmt[i])) "" else cmt[i])
  }
  err_df <- if (length(errors) == 0)
    data.frame(row = integer(0), name = character(0), message = character(0),
               stringsAsFactors = FALSE)
  else do.call(rbind, errors)
  list(ok = TRUE, rows = rows, errors = err_df)
}

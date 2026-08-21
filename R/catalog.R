# ============================================================================
# catalog.R  -  the Excel (.xlsx) data catalog.
#
# One catalog row = one SAMPLE. Spec: workspace file
# "HiCarta_Excelカタログ仕様書_草案.md" (v0.3). Summary:
#   * sheet 1 only; row 1 = header; rows whose `id` cell starts with "#" are
#     DIRECTIVE rows (e.g. "#show" = initial column visibility), not data.
#   * required columns  : id (numeric, unique), name, path
#   * recognised columns: file_type (hic/bigwig/bed/gff3/bs; guessed from the
#     path extension when absent), experiment_type, project, sample_sheet,
#     date (YYYY-MM-DD), genome, label, comment
#   * "set_" prefix     : per-sample setting overrides (kept out of the list)
#   * multi-value cells : path / label / set_* may hold several ";"-separated
#     values (full-width "；" tolerated). Within a row every such column must
#     hold 1 or N values; single values are recycled to all N entries.
#   * validation        : broken rows (bad/duplicated id, empty path,
#     mismatched ";" counts) are EXCLUDED and reported with name + reason;
#     soft problems (unparsable date, unknown file_type / set_ column /
#     directive) are warnings only.
#
# read_catalog() is pure (no shiny) apart from tr() for message text, so it
# can be unit-tested from a plain R session:
#   source("R/i18n.R"); source("R/catalog.R"); read_catalog("catalog.xlsx")
# ============================================================================

CAT_REQUIRED   <- c("id", "name", "path")
CAT_FILE_TYPES <- c("hic", "bigwig", "bed", "gff3", "bs")
# columns shown in the list by default when the catalog has no "#show" row
# (matched against lower-cased column names; only columns that exist appear)
CAT_DEFAULT_SHOW <- c("id", "name", "file_type", "experiment_type",
                      "project", "date")
# a column becomes an automatic dropdown filter when it holds at most this
# many distinct non-empty values (spec v0.3 §2.4)
CAT_FILTER_MAX_UNIQUE <- 20

# ---- fetch: URL -> temp download; local path -> temp copy -------------------
# The catalog is deliberately NOT cached (collaborators edit it online; every
# Load must see the current version). A local file is copied first so an .xlsx
# that is open in Excel (locked) can still be read.
catalog_fetch <- function(src) {
  src <- trimws(src)
  tf  <- tempfile(fileext = ".xlsx")
  if (grepl("^https?://", src)) {
    ok <- FALSE
    if (requireNamespace("curl", quietly = TRUE)) {
      ok <- tryCatch({ curl::curl_download(src, tf, quiet = TRUE); TRUE },
                     error = function(e) FALSE)
    }
    if (!ok)
      utils::download.file(src, tf, mode = "wb", quiet = TRUE)
  } else {
    if (!file.exists(src)) stop(sprintf(tr("cat_v_no_file"), src))
    if (!file.copy(src, tf, overwrite = TRUE))
      stop(sprintf(tr("cat_v_no_file"), src))
  }
  tf
}

# normalise a multi-value cell into its parts: full-width "；" -> ";",
# split, trim, drop empty parts. NA / empty -> character(0).
cat_split <- function(x) {
  if (is.na(x) || !nzchar(trimws(x))) return(character(0))
  x <- gsub("；", ";", x, fixed = TRUE)      # full-width semicolon
  parts <- trimws(strsplit(x, ";", fixed = TRUE)[[1]])
  parts[nzchar(parts)]
}

# guess the file type from a path (used when the file_type column is absent
# or empty). Returns NA_character_ when the extension is not recognised.
cat_guess_type <- function(path) {
  b <- tolower(basename(path))
  b <- sub("\\.gz$", "", b)
  if (grepl("\\.hic$", b))                                    return("hic")
  if (grepl("\\.(bw|bigwig|bedgraph|bdg)$", b))               return("bigwig")
  if (grepl("\\.(bed|narrowpeak|broadpeak)$", b))             return("bed")
  if (grepl("\\.(gff|gff3|gtf)$", b))                         return("gff3")
  if (grepl("_bs\\.txt$", b))                                 return("bs")
  NA_character_
}

# parse a date string; accepts YYYY-MM-DD (recommended), YYYY/MM/DD, YYYY.MM.DD,
# YYYYMMDD, and a bare Excel date serial (a mixed text/date Excel column comes
# through the text read as e.g. "45759", and the typed re-read cannot recover
# it because the column as a whole is not a date column).
cat_parse_date <- function(x) {
  if (is.na(x) || !nzchar(x)) return(as.Date(NA))
  x <- trimws(x)
  for (f in c("%Y-%m-%d", "%Y/%m/%d", "%Y.%m.%d")) {
    d <- tryCatch(as.Date(x, format = f), error = function(e) as.Date(NA))
    if (!is.na(d)) return(d)
  }
  if (grepl("^[0-9]{8}$", x)) {
    d <- tryCatch(as.Date(x, format = "%Y%m%d"), error = function(e) as.Date(NA))
    if (!is.na(d)) return(d)
  }
  if (grepl("^[0-9]{5}(\\.0+)?$", x)) {         # Excel serial: 1954..2119
    n <- suppressWarnings(as.numeric(x))
    if (is.finite(n) && n >= 20000 && n <= 80000)
      return(as.Date(n, origin = "1899-12-30"))
  }
  as.Date(NA)
}

# ---- main entry -------------------------------------------------------------
# Returns a list:
#   ok        : TRUE, or FALSE with $fatal (message) when nothing was loaded
#   data      : character data.frame of the VALID rows, original column names
#   columns   : column names as written in Excel;  canon: lower-cased
#   id        : numeric id per valid row
#   paths     : list of character vectors (split path entries) per valid row
#   labels    : list, entry labels recycled to the same length as paths
#   file_type : canonical type per row ("hic", ..., or NA = not openable)
#   n_entries : number of ";"-entries per row
#   date      : Date per row (NA when absent or unparsable)
#   show_cols : column names flagged in a "#show" row, or NULL
#   errors, warnings : data.frame(row, id, name, column, message);
#     `row` is the Excel row number (header = row 1)
read_catalog <- function(src) {
  if (is.null(src) || !nzchar(trimws(src)))
    return(list(ok = FALSE, fatal = tr("msg_cat_choose")))
  path <- catalog_fetch(src)
  on.exit(unlink(path), add = TRUE)

  # Read once with everything as text (so "#show" and mixed columns survive),
  # and once with type guessing only to recover true DATE cells as ISO text.
  raw <- suppressMessages(
    readxl::read_excel(path, sheet = 1, col_types = "text",
                       .name_repair = "unique"))
  df  <- as.data.frame(raw, stringsAsFactors = FALSE)
  if (nrow(df) > 0) for (j in seq_along(df)) {
    x <- as.character(df[[j]])
    df[[j]] <- ifelse(is.na(x), NA_character_, trimws(x))
  }
  typed <- tryCatch(
    suppressMessages(suppressWarnings(as.data.frame(
      readxl::read_excel(path, sheet = 1, .name_repair = "unique"),
      stringsAsFactors = FALSE))),
    error = function(e) NULL)
  if (!is.null(typed) && identical(dim(typed), dim(df))) {
    for (j in seq_along(typed)) {
      cl <- typed[[j]]
      if (inherits(cl, "POSIXct") || inherits(cl, "Date")) {
        iso <- format(cl, "%Y-%m-%d")
        keep <- !is.na(iso)
        df[[j]][keep] <- iso[keep]
      }
    }
  }

  columns <- trimws(names(df))
  names(df) <- columns
  canon <- tolower(columns)

  # required columns present at all?
  miss <- setdiff(CAT_REQUIRED, canon)
  if (length(miss) > 0)
    return(list(ok = FALSE,
                fatal = sprintf(tr("cat_v_req_missing"),
                                paste(miss, collapse = ", "))))

  col_of  <- function(key) which(canon == key)[1]
  id_col  <- col_of("id"); name_col <- col_of("name"); path_col <- col_of("path")
  split_cols <- which(canon %in% c("path", "label") | startsWith(canon, "set_"))

  errors   <- list(); warnings <- list()
  add_issue <- function(store, row, id, name, column, message) {
    store[[length(store) + 1L]] <- data.frame(
      row = row, id = id, name = name, column = column, message = message,
      stringsAsFactors = FALSE)
    store
  }

  # ---- directive rows (id cell starts with "#") -----------------------------
  idv   <- df[[id_col]]
  is_dir <- !is.na(idv) & grepl("^#", idv)
  show_cols <- NULL
  for (i in which(is_dir)) {
    key <- tolower(idv[i])
    if (identical(key, "#show")) {
      on <- vapply(seq_along(df), function(j) {
        if (j == id_col) return(FALSE)
        v <- df[[j]][i]
        !is.na(v) && nzchar(v) && !(tolower(v) %in% c("0", "false", "no"))
      }, logical(1))
      show_cols <- unique(c(columns[on],
                            columns[name_col]))   # name is always shown
    } else {
      warnings <- add_issue(warnings, i + 1L, idv[i], "", columns[id_col],
                            sprintf(tr("cat_v_dir_unknown"), idv[i]))
    }
  }

  # ---- data rows ------------------------------------------------------------
  empty_row <- vapply(seq_len(nrow(df)), function(i) {
    vals <- unlist(df[i, ], use.names = FALSE)
    all(is.na(vals) | !nzchar(vals))
  }, logical(1))
  keep_i <- which(!is_dir & !empty_row)

  # unknown set_ columns get one warning each (not per row)
  known_set <- c("set_norm", "set_vmax", "set_resolution",
                 "set_color", "set_height")
  for (j in which(startsWith(canon, "set_") & !(canon %in% known_set)))
    warnings <- add_issue(warnings, 1L, "", "", columns[j],
                          tr("cat_v_set_unknown"))

  n <- length(keep_i)
  id_num    <- rep(NA_real_, n)
  paths     <- vector("list", n)
  labels    <- vector("list", n)
  ftype     <- rep(NA_character_, n)
  n_entries <- rep(1L, n)
  dates     <- rep(as.Date(NA), n)
  bad       <- rep(FALSE, n)

  ft_col    <- col_of("file_type")
  date_col  <- col_of("date")
  label_col <- col_of("label")

  for (k in seq_len(n)) {
    i   <- keep_i[k]
    xr  <- i + 1L                       # Excel row number (header = 1)
    nm  <- df[[name_col]][i]; if (is.na(nm)) nm <- ""
    idc <- df[[id_col]][i];  if (is.na(idc)) idc <- ""

    # id: numeric and non-empty
    v <- suppressWarnings(as.numeric(idc))
    if (!nzchar(idc) || is.na(v)) {
      errors <- add_issue(errors, xr, idc, nm, columns[id_col],
                          tr("cat_v_id_bad"))
      bad[k] <- TRUE
    } else id_num[k] <- v

    # multi-value columns: every non-empty one must hold 1 or N values
    lens <- vapply(split_cols, function(j) length(cat_split(df[[j]][i])),
                   integer(1))
    pos  <- lens[lens > 0]
    N    <- if (length(pos)) max(pos) else 0L
    if (length(pos) && any(pos != 1L & pos != N)) {
      det <- paste(sprintf("%s=%d", columns[split_cols[lens > 0]], pos),
                   collapse = ", ")
      errors <- add_issue(errors, xr, idc, nm, "",
                          sprintf(tr("cat_v_multi_mismatch"), det))
      bad[k] <- TRUE
    }

    # path: required, non-empty
    ps <- cat_split(df[[path_col]][i])
    if (length(ps) == 0) {
      errors <- add_issue(errors, xr, idc, nm, columns[path_col],
                          tr("cat_v_path_empty"))
      bad[k] <- TRUE
    }
    paths[[k]]   <- ps
    n_entries[k] <- max(1L, length(ps))

    # entry labels, recycled to the number of path entries
    lb <- if (!is.na(label_col)) cat_split(df[[label_col]][i])
          else character(0)
    labels[[k]] <-
      if (length(ps) == 0)      character(0)
      else if (length(lb) == 0) basename(ps)
      else if (length(lb) == 1) rep(lb, length(ps))
      else if (length(lb) == length(ps)) lb
      else basename(ps)         # mismatch already reported above

    # file type: column value, else guessed from the first path entry
    ft <- if (!is.na(ft_col)) df[[ft_col]][i] else NA_character_
    ft <- if (is.na(ft) || !nzchar(ft)) NA_character_ else tolower(ft)
    if (!is.na(ft) && !(ft %in% CAT_FILE_TYPES)) {
      warnings <- add_issue(warnings, xr, idc, nm, columns[ft_col],
                            sprintf(tr("cat_v_ftype_bad"), ft))
      ft <- NA_character_
    }
    if (is.na(ft) && length(ps) > 0) ft <- cat_guess_type(ps[1])
    if (is.na(ft) && length(ps) > 0)
      warnings <- add_issue(warnings, xr, idc, nm,
                            if (!is.na(ft_col)) columns[ft_col] else "",
                            tr("cat_v_ftype_unknown"))
    ftype[k] <- ft

    # date: recommended YYYY-MM-DD; failures are shown but excluded from the
    # (future) date filter
    if (!is.na(date_col)) {
      dv <- df[[date_col]][i]
      if (!is.na(dv) && nzchar(dv)) {
        d <- cat_parse_date(dv)
        if (is.na(d)) {
          warnings <- add_issue(warnings, xr, idc, nm, columns[date_col],
                                sprintf(tr("cat_v_date_bad"), dv))
        } else {
          # normalise the displayed cell to ISO (serials, slashes, yyyymmdd)
          iso <- format(d, "%Y-%m-%d")
          if (!identical(dv, iso)) df[[date_col]][i] <- iso
        }
        dates[k] <- d
      }
    }
  }

  # duplicated ids: exclude EVERY row involved (a clear signal to fix the file)
  dup_vals <- unique(id_num[!is.na(id_num)][duplicated(id_num[!is.na(id_num)])])
  if (length(dup_vals) > 0) for (k in which(id_num %in% dup_vals)) {
    i <- keep_i[k]
    errors <- add_issue(errors, i + 1L, df[[id_col]][i],
                        df[[name_col]][i], columns[id_col],
                        tr("cat_v_id_dup"))
    bad[k] <- TRUE
  }

  ok_k <- which(!bad)
  data <- df[keep_i[ok_k], , drop = FALSE]
  rownames(data) <- NULL

  bind_issues <- function(lst) {
    if (length(lst) == 0)
      return(data.frame(row = integer(0), id = character(0),
                        name = character(0), column = character(0),
                        message = character(0), stringsAsFactors = FALSE))
    do.call(rbind, lst)
  }

  list(ok = TRUE,
       data      = data,
       columns   = columns,
       canon     = canon,
       id        = id_num[ok_k],
       paths     = paths[ok_k],
       labels    = labels[ok_k],
       file_type = ftype[ok_k],
       n_entries = n_entries[ok_k],
       date      = dates[ok_k],
       show_cols = show_cols,
       name_col  = name_col,
       errors    = bind_issues(errors),
       warnings  = bind_issues(warnings))
}

# ---- helpers used by the UI -------------------------------------------------

# which columns the list shows initially: the "#show" row fully decides when
# present, otherwise the default set. id and name are ALWAYS shown (the #show
# marker lives in the id cell itself, so id could never be flagged there).
# path and set_* are not in the default set, so they start hidden unless a
# #show row flags them.
catalog_visible_cols <- function(cat) {
  vis <- if (!is.null(cat$show_cols)) intersect(cat$columns, cat$show_cols)
         else cat$columns[cat$canon %in% CAT_DEFAULT_SHOW]
  idnm <- cat$columns[cat$canon %in% c("id", "name")]
  unique(c(idnm, vis))
}

# value of a set_<key> column for row i, entry `entry` (spec §2.3): a single
# value applies to every entry (recycling), a ";"-list is indexed per entry.
# entry = NA marks the virtual "auto" open, where only a COMMON single value
# is meaningful — a per-entry list is ambiguous there and yields NA.
# Returns NA_character_ when the column is absent or the cell empty.
catalog_set_value <- function(cat, i, key, entry = 1L) {
  j <- which(cat$canon == paste0("set_", key))[1]
  if (is.na(j)) return(NA_character_)
  parts <- cat_split(cat$data[[j]][i])
  if (length(parts) == 0) return(NA_character_)
  if (length(parts) == 1) return(parts[1])
  if (is.na(entry)) return(NA_character_)
  if (entry >= 1 && entry <= length(parts)) return(parts[entry])
  NA_character_
}

# columns that get an automatic dropdown filter in the sidebar. Everything is
# a candidate except id, name, path, label, comment, date (date has its own
# dropdown + range control) and the set_* setting columns; a candidate
# qualifies when it holds 1..CAT_FILTER_MAX_UNIQUE distinct non-empty values.
# The recognised metadata columns come first (experiment_type, project,
# sample_sheet), then the rest in catalog column order.
# Returns data.frame(j = column index, name = column name as written).
catalog_filter_cols <- function(cat) {
  excl <- cat$canon %in% c("id", "name", "path", "label", "comment", "date") |
          startsWith(cat$canon, "set_")
  cand <- which(!excl)
  ok <- cand[vapply(cand, function(j) {
    v <- cat$data[[j]]
    v <- v[!is.na(v) & nzchar(v)]
    n <- length(unique(v))
    n >= 1 && n <= CAT_FILTER_MAX_UNIQUE
  }, logical(1))]
  main <- c("experiment_type", "project", "sample_sheet")
  pri  <- match(cat$canon[ok], main)
  pri[is.na(pri)] <- length(main) + 1L
  ok <- ok[order(pri, ok)]
  data.frame(j = ok, name = cat$columns[ok], stringsAsFactors = FALSE)
}

# distinct non-empty values of one column, sorted, for a filter dropdown
catalog_filter_choices <- function(cat, j, rows = NULL) {
  v <- cat$data[[j]]
  if (!is.null(rows)) v <- v[rows]
  v <- v[!is.na(v) & nzchar(v)]
  sort(unique(v))
}

# flatten the catalog's hic rows into one entry per file, for e.g. the
# comparison sample's dropdown: data.frame(disp, path, row, entry)
catalog_hic_entries <- function(cat) {
  out <- list()
  for (k in seq_len(nrow(cat$data))) {
    if (!identical(cat$file_type[k], "hic")) next
    ps <- cat$paths[[k]]; lb <- cat$labels[[k]]
    nm <- cat$data[[cat$name_col]][k]
    for (e in seq_along(ps)) {
      disp <- if (length(ps) > 1) paste(nm, lb[e], sep = " / ") else nm
      out[[length(out) + 1L]] <- data.frame(
        disp = disp, path = ps[e], row = k, entry = e,
        stringsAsFactors = FALSE)
    }
  }
  if (length(out) == 0)
    return(data.frame(disp = character(0), path = character(0),
                      row = integer(0), entry = integer(0),
                      stringsAsFactors = FALSE))
  do.call(rbind, out)
}

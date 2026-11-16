# ============================================================================
# s3.R  -  read private Amazon S3 objects (AWS Signature Version 4)
#
# Catalog paths may name S3 objects two ways:
#
#   s3://bucket/key                                   explicit S3 URI
#   https://bucket.s3.<region>.amazonaws.com/key      ordinary S3 https URL
#
# Who may read what is decided by S3, not here (see scripts/aws/README.md: an
# "access" tag on each object, IAM policies per lab / P01, a bucket policy for
# public). HiCarta only has to (1) sign the request when it has credentials and
# (2) report a refusal in words the user can act on.
#
# Behaviour, chosen so nothing that works today can break:
#   * https:// S3 URL  -> sent UNSIGNED first, exactly as before. Only if S3
#                         answers 403 and credentials exist is it re-sent signed.
#   * s3:// URI        -> signed when credentials exist, unsigned otherwise. A
#                         signed request rejected because the KEY itself is bad
#                         (deleted, mistyped, expired) is retried unsigned, so a
#                         stale credentials file never hides public data.
#   * region           -> taken from config / environment / ~/.aws/config, and
#                         corrected automatically from S3's x-amz-bucket-region
#                         reply if wrong (cached per bucket).
#
# Credentials, first hit wins:
#   1. config.txt  aws_profile = NAME            -> that profile, nothing else
#   2. AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (/ AWS_SESSION_TOKEN) env vars
#   3. AWS_PROFILE env var, else profile "default"
# Profiles are read from AWS_SHARED_CREDENTIALS_FILE or <home>/.aws/credentials,
# and from AWS_CONFIG_FILE or <home>/.aws/config ("[profile NAME]" sections).
# <home> is %USERPROFILE% on Windows -- R's "~" there is Documents, which is not
# where the AWS CLI keeps its files.
#
# Only HMAC-SHA256 and SHA-256 are needed; they come from 'digest', which every
# shiny installation already has (htmltools imports it). No compiler, no SDK.
#
# Public API used by the readers:
#   is_remote_path(p)              TRUE for http(s):// and s3://
#   remote_target(path)            env describing how to fetch `path`
#   remote_fetch(tg, handle, range = NULL, dest = NULL)   one GET, with retries
#   remote_stop(tg, r)             stop() with a readable message for a bad reply
#   remote_download(path, dest)    whole file to disk (cache, catalog, XML)
#   set_s3_config(profile, region) from config.txt;  s3_forget() drops caches
#   s3_status()                    what HiCarta currently sees (settings dialog)
# ============================================================================

is_s3_uri      <- function(p) grepl("^s3://", p, ignore.case = TRUE)
is_remote_path <- function(p) grepl("^(https?|s3)://", p, ignore.case = TRUE)

S3_DEFAULT_REGION <- "us-west-2"     # where uo-cgf lives; corrected per bucket

.s3 <- new.env(parent = emptyenv())
.s3$profile <- ""                    # from config.txt (aws_profile)
.s3$region  <- ""                    # from config.txt (aws_region)
.s3$creds   <- NULL                  # cached credentials (FALSE = none found)
.s3$bucket_region <- new.env(parent = emptyenv())

set_s3_config <- function(profile = "", region = "") {
  clean <- function(x) {
    x <- tryCatch(trimws(as.character(x)[1]), error = function(e) "")
    if (length(x) != 1 || is.na(x)) "" else x
  }
  p <- clean(profile); r <- clean(region)
  if (!identical(p, .s3$profile) || !identical(r, .s3$region)) {
    .s3$profile <- p; .s3$region <- r
    s3_forget()
    # Readers opened with the previous key keep their signing state, so a
    # file the new account may not read would still display. Drop them.
    for (f in c("hic_forget", "bw_forget"))
      if (exists(f, mode = "function")) try(get(f)(), silent = TRUE)
  }
  invisible(NULL)
}

s3_forget <- function() {
  .s3$creds <- NULL
  rm(list = ls(.s3$bucket_region), envir = .s3$bucket_region)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# AWS shared config / credentials files
# ---------------------------------------------------------------------------
.aws_home <- function() {
  h <- if (.Platform$OS.type == "windows") Sys.getenv("USERPROFILE") else ""
  if (!nzchar(h)) h <- Sys.getenv("HOME")
  if (!nzchar(h)) h <- path.expand("~")
  h
}

.aws_file <- function(env, name) {
  f <- Sys.getenv(env, unset = "")
  if (nzchar(f)) return(path.expand(f))
  file.path(.aws_home(), ".aws", name)
}

# minimal INI reader: list(section = list(key = value)); ";"/"#" comments
.read_ini <- function(path) {
  out <- list()
  if (!file.exists(path)) return(out)
  sec <- NULL
  for (ln in readLines(path, warn = FALSE, encoding = "UTF-8")) {
    ln <- trimws(sub("^﻿", "", ln))
    if (!nzchar(ln) || grepl("^[;#]", ln)) next
    if (grepl("^\\[.*\\]$", ln)) {
      sec <- trimws(substr(ln, 2, nchar(ln) - 1))
      if (is.null(out[[sec]])) out[[sec]] <- list()
      next
    }
    if (is.null(sec) || !grepl("=", ln, fixed = TRUE)) next
    k <- tolower(trimws(sub("=.*$", "", ln)))
    v <- trimws(sub("^[^=]*=", "", ln))
    out[[sec]][[k]] <- v
  }
  out
}

.aws_profile_section <- function(profile) {
  cr <- .read_ini(.aws_file("AWS_SHARED_CREDENTIALS_FILE", "credentials"))
  cf <- .read_ini(.aws_file("AWS_CONFIG_FILE", "config"))
  a <- cr[[profile]]
  b <- if (profile == "default") cf[["default"]] else cf[[paste("profile", profile)]]
  if (is.null(b) && profile != "default") b <- cf[[profile]]
  c(a %||% list(), b[setdiff(names(b), names(a))] %||% list())
}

# -> list(id, secret, token, source, profile) or NULL
s3_credentials <- function() {
  if (identical(.s3$creds, FALSE)) return(NULL)
  if (!is.null(.s3$creds)) return(.s3$creds)
  found <- NULL
  from_profile <- function(p) {
    s <- .aws_profile_section(p)
    if (nzchar(s$aws_access_key_id %||% "") && nzchar(s$aws_secret_access_key %||% ""))
      list(id = s$aws_access_key_id, secret = s$aws_secret_access_key,
           token = s$aws_session_token %||% "", source = "profile", profile = p,
           region = s$region %||% "")
    else NULL
  }
  if (nzchar(.s3$profile)) {
    found <- from_profile(.s3$profile)
  } else {
    id <- Sys.getenv("AWS_ACCESS_KEY_ID"); sk <- Sys.getenv("AWS_SECRET_ACCESS_KEY")
    if (nzchar(id) && nzchar(sk)) {
      found <- list(id = id, secret = sk, token = Sys.getenv("AWS_SESSION_TOKEN"),
                    source = "environment", profile = "", region = "")
    } else {
      p <- Sys.getenv("AWS_PROFILE", unset = "")
      found <- from_profile(if (nzchar(p)) p else "default")
    }
  }
  .s3$creds <- if (is.null(found)) FALSE else found
  found
}

.s3_region_for <- function(bucket) {
  hit <- .s3$bucket_region[[bucket]]
  if (!is.null(hit)) return(hit)
  for (r in c(.s3$region, Sys.getenv("AWS_REGION"), Sys.getenv("AWS_DEFAULT_REGION"),
              (s3_credentials() %||% list())$region %||% ""))
    if (nzchar(r)) return(r)
  S3_DEFAULT_REGION
}

# What HiCarta sees, for the settings dialog / diagnostics.
s3_status <- function() {
  cr <- s3_credentials()
  list(have = !is.null(cr),
       source = if (is.null(cr)) "" else cr$source,
       profile = if (is.null(cr)) (if (nzchar(.s3$profile)) .s3$profile else "") else cr$profile,
       key_id = if (is.null(cr)) "" else paste0(substr(cr$id, 1, 4), "...",
                                               substr(cr$id, nchar(cr$id) - 3, nchar(cr$id))),
       credentials_file = .aws_file("AWS_SHARED_CREDENTIALS_FILE", "credentials"))
}

# ---------------------------------------------------------------------------
# addressing
# ---------------------------------------------------------------------------
# RFC 3986 unreserved characters pass, everything else is %XX (upper case) --
# the encoding SigV4 requires. Applied per path segment so "/" survives.
.s3_unreserved <- c(48:57, 65:90, 97:122, 45L, 46L, 95L, 126L)   # 0-9 A-Z a-z - . _ ~
.s3_enc <- function(x) {
  b <- as.integer(charToRaw(enc2utf8(x)))
  paste0(ifelse(b %in% .s3_unreserved, intToUtf8(b, multiple = TRUE),
                sprintf("%%%02X", b)), collapse = "")
}
.s3_enc_path <- function(key) {
  segs <- strsplit(key, "/", fixed = TRUE)[[1]]
  out <- paste(vapply(segs, .s3_enc, ""), collapse = "/")
  if (endsWith(key, "/")) out <- paste0(out, "/")
  out
}

# s3://bucket/key -> list(bucket, key)
.s3_parse_uri <- function(p) {
  m <- regmatches(p, regexec("^[sS]3://([^/]+)/(.+)$", p))[[1]]
  if (length(m) != 3) stop("not a valid s3:// path (need s3://bucket/key): ", p,
                           call. = FALSE)
  list(bucket = m[2], key = m[3])
}

# Recognise S3 https URLs: virtual-hosted (bucket.s3[.-]region.amazonaws.com/key,
# bucket.s3.amazonaws.com/key) and path style (s3[.-]region.amazonaws.com/bucket/key).
# The key is URL-decoded so it can be re-encoded canonically.
.s3_parse_https <- function(u) {
  m <- regmatches(u, regexec("^https?://([^/?#]+)/([^?#]*)", u))[[1]]
  if (length(m) != 3) return(NULL)
  host <- tolower(m[2]); path <- m[3]
  if (!grepl("\\.amazonaws\\.com$", host)) return(NULL)
  dec <- function(x) utils::URLdecode(x)
  vh <- regmatches(host, regexec("^(.+)\\.s3(?:[.-](?:dualstack\\.)?([a-z0-9-]+))?\\.amazonaws\\.com$",
                                 host, perl = TRUE))[[1]]
  if (length(vh) == 3 && nzchar(vh[2]) && !grepl("^s3[.-]", host)) {
    reg <- if (nzchar(vh[3])) vh[3] else ""
    if (!nzchar(path)) return(NULL)
    return(list(bucket = vh[2], key = dec(path), region = reg))
  }
  ps <- regmatches(host, regexec("^s3(?:[.-]([a-z0-9-]+))?\\.amazonaws\\.com$", host))[[1]]
  if (length(ps) == 2) {
    parts <- strsplit(path, "/", fixed = TRUE)[[1]]
    if (length(parts) < 2) return(NULL)
    return(list(bucket = parts[1], key = dec(paste(parts[-1], collapse = "/")),
                region = ps[2]))
  }
  NULL
}

# Build the request URL + canonical URI for (bucket, key, region). Bucket names
# containing dots break TLS with virtual-hosted style, so they go path style.
.s3_address <- function(bucket, key, region) {
  if (grepl(".", bucket, fixed = TRUE)) {
    host <- sprintf("s3.%s.amazonaws.com", region)
    uri  <- paste0("/", .s3_enc(bucket), "/", .s3_enc_path(key))
  } else {
    host <- sprintf("%s.s3.%s.amazonaws.com", bucket, region)
    uri  <- paste0("/", .s3_enc_path(key))
  }
  list(host = host, uri = uri, url = paste0("https://", host, uri))
}

# ---------------------------------------------------------------------------
# Signature Version 4 (header-based, unsigned payload)
# https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
# ---------------------------------------------------------------------------
.sha256_hex <- function(x) digest::digest(x, algo = "sha256", serialize = FALSE)
.hmac_raw   <- function(key, x) digest::hmac(key, x, algo = "sha256", raw = TRUE)

# Generic signer, kept separate so the AWS documentation test vectors can be
# checked byte-for-byte (scripts/test_s3.R). `headers` = named character vector
# of headers to SIGN (host included); names any case. Returns the extra headers
# to send: Authorization (+ whatever was passed in, excluding host).
s3_sign <- function(method, host, uri, headers, creds, region,
                    amz_date, payload_hash = "UNSIGNED-PAYLOAD",
                    query = "", service = "s3") {
  date <- substr(amz_date, 1, 8)
  h <- c(host = host, headers)
  names(h) <- tolower(names(h))
  h <- vapply(h, function(v) gsub("\\s+", " ", trimws(v)), "")
  o <- order(names(h)); h <- h[o]
  signed <- paste(names(h), collapse = ";")
  canonical <- paste(method, uri, query,
                     paste0(paste0(names(h), ":", h, "\n"), collapse = ""),
                     signed, payload_hash, sep = "\n")
  scope <- paste(date, region, service, "aws4_request", sep = "/")
  sts <- paste("AWS4-HMAC-SHA256", amz_date, scope, .sha256_hex(canonical), sep = "\n")
  k <- .hmac_raw(charToRaw(paste0("AWS4", creds$secret)), date)
  k <- .hmac_raw(k, region); k <- .hmac_raw(k, service); k <- .hmac_raw(k, "aws4_request")
  sig <- paste(sprintf("%02x", as.integer(.hmac_raw(k, sts))), collapse = "")
  auth <- sprintf("AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s",
                  creds$id, scope, signed, sig)
  out <- c(headers, Authorization = auth)
  out[tolower(names(out)) != "host"]
}

.s3_auth_headers <- function(tg, method = "GET") {
  amz <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
  hd <- c(`x-amz-content-sha256` = "UNSIGNED-PAYLOAD", `x-amz-date` = amz)
  if (nzchar(tg$creds$token %||% "")) hd <- c(hd, `x-amz-security-token` = tg$creds$token)
  s3_sign(method, tg$host, tg$uri, hd, tg$creds, tg$region, amz)
}

# ---------------------------------------------------------------------------
# fetch target: how to GET one path
# ---------------------------------------------------------------------------
remote_target <- function(path) {
  tg <- new.env(parent = emptyenv())
  tg$path <- path
  tg$s3   <- FALSE
  tg$sign <- FALSE
  if (is_s3_uri(path)) {
    b <- .s3_parse_uri(path)
    tg$s3 <- TRUE; tg$bucket <- b$bucket; tg$key <- b$key
    tg$region <- .s3_region_for(b$bucket)
    tg$creds <- s3_credentials()
    tg$sign <- !is.null(tg$creds)
    tg$can_unsign <- TRUE                    # bad key -> try anonymously
    tg$can_sign   <- FALSE
  } else {
    p <- .s3_parse_https(path)
    if (!is.null(p)) {
      tg$s3 <- TRUE; tg$bucket <- p$bucket; tg$key <- p$key
      tg$region <- if (nzchar(p$region)) p$region else .s3_region_for(p$bucket)
      tg$creds <- NULL                       # looked up only if S3 says 403
      tg$can_sign   <- TRUE
      tg$can_unsign <- FALSE
      tg$url <- path                         # keep the exact URL while unsigned
    } else {
      tg$url <- path
    }
  }
  if (tg$s3 && is.null(tg$url)) .s3_readdress(tg)
  tg
}

.s3_readdress <- function(tg) {
  a <- .s3_address(tg$bucket, tg$key, tg$region)
  tg$host <- a$host; tg$uri <- a$uri; tg$url <- a$url
  invisible(tg)
}

.s3_error_code <- function(r) {
  if (is.null(r$content) || !length(r$content)) return("")
  txt <- tryCatch(rawToChar(r$content[seq_len(min(length(r$content), 4096))]),
                  error = function(e) "")
  m <- regmatches(txt, regexec("<Code>([^<]+)</Code>", txt))[[1]]
  if (length(m) == 2) m[2] else ""
}

# One GET (optionally a byte range, optionally streamed to `dest`), handling the
# S3 cases: sign-on-403 for https URLs, unsign-on-bad-key for s3://, and a
# wrong region. Returns the curl response; the caller checks the status.
remote_fetch <- function(tg, handle, range = NULL, dest = NULL) {
  for (attempt in 1:4) {
    hd <- character(0)
    if (!is.null(range)) hd <- c(hd, Range = range)
    if (isTRUE(tg$sign)) {
      if (is.null(tg$host)) .s3_readdress(tg)
      hd <- c(hd, .s3_auth_headers(tg))
    }
    do.call(curl::handle_setheaders, c(list(handle), as.list(hd)))
    if (!is.null(dest) && file.exists(dest)) unlink(dest)
    r <- if (is.null(dest)) curl::curl_fetch_memory(tg$url, handle = handle)
         else curl::curl_fetch_disk(tg$url, dest, handle = handle)
    if (!is.null(dest) && r$status_code >= 300 && file.exists(dest)) {
      r$content <- tryCatch(readBin(dest, "raw", 4096), error = function(e) raw(0))
    }
    st <- r$status_code
    if (!isTRUE(tg$s3) || st %in% c(200L, 206L)) return(r)
    code <- .s3_error_code(r)
    hl <- curl::parse_headers_list(r$headers)

    # wrong region: S3 names the right one
    br <- hl[["x-amz-bucket-region"]]
    if (is.null(br)) {
      txt <- tryCatch(rawToChar(r$content[seq_len(min(length(r$content), 4096))]),
                      error = function(e) "")
      m <- regmatches(txt, regexec("<Region>([^<]+)</Region>", txt))[[1]]
      if (length(m) == 2) br <- m[2]
    }
    if (!is.null(br) && nzchar(br) && !identical(br, tg$region) &&
        (st %in% c(301L, 307L, 400L) ||
         code %in% c("PermanentRedirect", "AuthorizationHeaderMalformed"))) {
      assign(tg$bucket, br, envir = .s3$bucket_region)
      tg$region <- br
      .s3_readdress(tg)
      next
    }
    # https S3 URL refused anonymously -> sign it, if we can
    if (st == 403L && !isTRUE(tg$sign) && isTRUE(tg$can_sign)) {
      tg$can_sign <- FALSE
      tg$creds <- s3_credentials()
      if (!is.null(tg$creds)) {
        tg$sign <- TRUE
        .s3_readdress(tg)
        next
      }
      return(r)
    }
    # s3:// signed with a key S3 does not accept -> try anonymously once
    if (st == 403L && isTRUE(tg$sign) && isTRUE(tg$can_unsign) &&
        code %in% c("InvalidAccessKeyId", "SignatureDoesNotMatch", "ExpiredToken",
                    "InvalidToken", "TokenRefreshRequired")) {
      tg$can_unsign <- FALSE
      tg$sign <- FALSE
      tg$bad_key <- code
      next
    }
    return(r)
  }
  r
}

.s3_tr <- function(key, default) {
  if (exists("tr", mode = "function")) {
    v <- tryCatch(tr(key), error = function(e) NULL)
    if (is.character(v) && length(v) == 1 && nzchar(v) && !identical(v, key)) return(v)
  }
  default
}

# Turn a failed reply into one sentence the user can act on.
remote_stop <- function(tg, r) {
  st <- r$status_code
  if (isTRUE(tg$s3) && st %in% c(403L, 404L)) {
    code <- .s3_error_code(r)
    who <- if (isTRUE(tg$sign)) {
      cr <- tg$creds
      if (identical(cr$source, "environment")) "AWS_ACCESS_KEY_ID"
      else sprintf("profile '%s'", cr$profile)
    } else ""
    msg <- if (identical(code, "RequestTimeTooSkewed")) {
      sprintf(.s3_tr("s3_err_clock",
        "AWS refused the request because this computer's clock is wrong. Correct the date/time and retry: %s"),
        tg$path)
    } else if (!is.null(tg$bad_key)) {
      sprintf(.s3_tr("s3_err_badkey",
        "AWS rejected your access key (%s) and the file is not public: %s"),
        tg$bad_key, tg$path)
    } else if (isTRUE(tg$sign)) {
      sprintf(.s3_tr("s3_err_denied",
        "No permission to read this file with your AWS account (%s), or it does not exist: %s"),
        who, tg$path)
    } else if (st == 403L) {
      sprintf(.s3_tr("s3_err_private",
        "This file is not public (or does not exist), and no AWS credentials were found (looked in %s): %s"),
        .aws_file("AWS_SHARED_CREDENTIALS_FILE", "credentials"), tg$path)
    } else {
      sprintf(.s3_tr("s3_err_missing", "File not found on S3: %s"), tg$path)
    }
    if (nzchar(code) && !grepl(code, msg, fixed = TRUE)) msg <- paste0(msg, " [", code, "]")
    .remote_error(msg)
  }
  .remote_error(sprintf("HTTP %d while reading %s", st, tg$path))
}

# A failed fetch is signalled with its own class. The readers fall back to
# strawr / rtracklayer when the native reader cannot PARSE a file, but a refused
# or failed download is not a parsing problem: the fallback would hit the same
# refusal and replace this message with an unhelpful one ("cannot be opened
# for reading"). .rethrow_remote() lets those handlers pass it through.
.remote_error <- function(msg)
  stop(structure(class = c("hicarta_remote_error", "error", "condition"),
                 list(message = msg, call = NULL)))

.rethrow_remote <- function(e) if (inherits(e, "hicarta_remote_error")) stop(e)

.remote_handle <- function() {
  h <- curl::new_handle()
  curl::handle_setopt(h, useragent = "HiCarta", followlocation = TRUE,
                      tcp_keepalive = TRUE, connecttimeout = 20L)
  h
}

# Whole file to `dest` (used for the download cache, the catalog and XML lists).
remote_download <- function(path, dest) {
  if (!requireNamespace("curl", quietly = TRUE))
    stop("downloading ", path, " needs the 'curl' package", call. = FALSE)
  tg <- remote_target(path)
  tmp <- paste0(dest, ".part")
  r <- remote_fetch(tg, .remote_handle(), dest = tmp)
  if (!(r$status_code %in% c(200L, 206L))) {
    unlink(tmp)
    remote_stop(tg, r)
  }
  if (file.exists(dest)) unlink(dest)
  if (!file.rename(tmp, dest)) { file.copy(tmp, dest, overwrite = TRUE); unlink(tmp) }
  invisible(dest)
}

if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a)) b else a

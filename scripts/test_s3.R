# Offline + online checks for R/s3.R.
#   Rscript scripts/test_s3.R                 # offline: SigV4 test vectors, parsing
#   Rscript scripts/test_s3.R s3://bucket/key # also: open it (uses your AWS profile)
#
# The three signatures below are the worked examples in the AWS S3 docs
# ("Signature Calculations for the Authorization Header", examples for
# GET Object, GET Bucket Lifecycle, GET Bucket (List Objects)).
`%||%` <- function(a, b) if (is.null(a)) b else a
source("R/s3.R")
ok <- 0L; bad <- 0L
check <- function(what, got, want) {
  if (identical(got, want)) { ok <<- ok + 1L; cat("  ok   ", what, "\n") }
  else { bad <<- bad + 1L; cat("  FAIL ", what, "\n       got : ", format(got),
                              "\n       want: ", format(want), "\n") }
}
sig_of <- function(h) sub(".*Signature=", "", h[["Authorization"]])

cr <- list(id = "AKIAIOSFODNN7EXAMPLE",
           secret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", token = "")
e0 <- "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
dt <- "20130524T000000Z"

cat("SigV4 (AWS documentation vectors)\n")
h <- s3_sign("GET", "examplebucket.s3.amazonaws.com", "/test.txt",
             c(range = "bytes=0-9", `x-amz-content-sha256` = e0, `x-amz-date` = dt),
             cr, "us-east-1", dt, payload_hash = e0)
check("GET Object",       sig_of(h), "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
check("SignedHeaders",    sub(".*SignedHeaders=([^,]+),.*", "\\1", h[["Authorization"]]),
      "host;range;x-amz-content-sha256;x-amz-date")
h <- s3_sign("GET", "examplebucket.s3.amazonaws.com", "/",
             c(`x-amz-content-sha256` = e0, `x-amz-date` = dt),
             cr, "us-east-1", dt, payload_hash = e0, query = "lifecycle=")
check("GET Bucket lifecycle", sig_of(h), "fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543")
h <- s3_sign("GET", "examplebucket.s3.amazonaws.com", "/",
             c(`x-amz-content-sha256` = e0, `x-amz-date` = dt),
             cr, "us-east-1", dt, payload_hash = e0, query = "max-keys=2&prefix=J")
check("GET Bucket list",  sig_of(h), "34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7")

cat("addressing\n")
check("encode key", .s3_enc_path("P/020/a b+c(1).hic"), "P/020/a%20b%2Bc%281%29.hic")
check("encode utf8", .s3_enc("\u00e9"), "%C3%A9")
a <- .s3_address("uo-cgf", "P/020/x.hic", "us-west-2")
check("virtual-hosted url", a$url, "https://uo-cgf.s3.us-west-2.amazonaws.com/P/020/x.hic")
a <- .s3_address("my.bucket", "k", "eu-west-1")
check("dotted bucket -> path style", a$url, "https://s3.eu-west-1.amazonaws.com/my.bucket/k")
p <- .s3_parse_https("https://uo-cgf.s3.us-west-2.amazonaws.com/P/020/a%20b.hic")
check("parse vhost", unlist(p), c(bucket = "uo-cgf", key = "P/020/a b.hic", region = "us-west-2"))
p <- .s3_parse_https("https://uo-cgf.s3.amazonaws.com/x/y.bw")
check("parse global vhost", unlist(p), c(bucket = "uo-cgf", key = "x/y.bw", region = ""))
p <- .s3_parse_https("https://s3.us-west-2.amazonaws.com/uo-cgf/x/y.bw")
check("parse path style", unlist(p), c(bucket = "uo-cgf", key = "x/y.bw", region = "us-west-2"))
p <- .s3_parse_https("https://uo-cgf.s3-us-west-2.amazonaws.com/x")
check("parse dash region", p$region, "us-west-2")
check("non-S3 host", .s3_parse_https("https://example.com/a.hic"), NULL)
check("s3 uri", unlist(.s3_parse_uri("s3://uo-cgf/P/020/x.hic")),
      c(bucket = "uo-cgf", key = "P/020/x.hic"))
check("is_remote_path", is_remote_path(c("s3://b/k", "https://x/y", "C:/a.hic", "http://z")),
      c(TRUE, TRUE, FALSE, TRUE))

cat("credentials files\n")
td <- tempfile(); dir.create(td)
writeLines(c("[default]", "aws_access_key_id = AKIADEFAULT0000",
             "aws_secret_access_key = s1", "", "[hicarta]",
             "aws_access_key_id=AKIAHICARTA0000", "aws_secret_access_key=s2"),
           file.path(td, "credentials"))
writeLines(c("[profile hicarta]", "region = ap-northeast-1"), file.path(td, "config"))
Sys.setenv(AWS_SHARED_CREDENTIALS_FILE = file.path(td, "credentials"),
           AWS_CONFIG_FILE = file.path(td, "config"))
old <- Sys.getenv(c("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_PROFILE"))
Sys.unsetenv(c("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_PROFILE", "AWS_REGION",
               "AWS_DEFAULT_REGION"))
set_s3_config("", "");        s3_forget()
check("default profile", s3_credentials()$id, "AKIADEFAULT0000")
set_s3_config("hicarta", "")
check("named profile", s3_credentials()$id, "AKIAHICARTA0000")
check("profile region from config", .s3_region_for("somebucket"), "ap-northeast-1")
set_s3_config("hicarta", "us-east-2")
check("aws_region overrides", .s3_region_for("somebucket"), "us-east-2")
set_s3_config("nosuch", "")
check("missing profile -> none", s3_credentials(), NULL)
set_s3_config("", "")
Sys.setenv(AWS_ACCESS_KEY_ID = "AKIAENV", AWS_SECRET_ACCESS_KEY = "s3"); s3_forget()
check("env vars", s3_credentials()$source, "environment")
Sys.unsetenv(c("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SHARED_CREDENTIALS_FILE",
               "AWS_CONFIG_FILE"))
for (k in names(old)) if (nzchar(old[[k]])) do.call(Sys.setenv, as.list(old[k]))
s3_forget()

args <- commandArgs(TRUE)
if (length(args)) {
  # same profile / region as the app: config.txt in the current folder
  cfg <- if (file.exists("config.txt")) readLines("config.txt", warn = FALSE) else character(0)
  val <- function(k) { m <- grep(paste0("^\\s*", k, "\\s*="), cfg, value = TRUE)
                       if (length(m)) trimws(sub("^[^=]*=", "", m[1])) else "" }
  set_s3_config(val("aws_profile"), val("aws_region"))
  st <- s3_status()
  cat("online  (credentials:", if (st$have) paste(st$source, st$profile, st$key_id) else "none", ")\n")
  for (p in args) {
    tg <- remote_target(p)
    r <- remote_fetch(tg, .remote_handle(), range = "bytes=0-15")
    cat(sprintf("  %-70s HTTP %d  signed=%s  region=%s\n", p, r$status_code,
                isTRUE(tg$sign), tg$region %||% "-"))
    if (!(r$status_code %in% c(200L, 206L)))
      cat("   -> ", tryCatch(remote_stop(tg, r), error = conditionMessage), "\n")
  }
}
cat(sprintf("\n%d ok, %d failed\n", ok, bad))
if (bad) quit(status = 1)

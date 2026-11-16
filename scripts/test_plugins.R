# ============================================================================
# test_plugins.R  -  headless check of the plugin mechanism (R/plugins.R)
#
#   Rscript scripts/test_plugins.R [path/to/some.hic] [out_dir]
#
# Runs without Shiny: sources the R/ files the way app.R does, loads every
# plugin in plugins/, then draws the two shipped examples to PNG files
# (screen style and print style) and exercises the catalog / session paths
# a plugin track goes through. Exit status is non-zero on any failure.
# ============================================================================
args <- commandArgs(trailingOnly = TRUE)
hic_path <- if (length(args) >= 1) args[1] else ""
out_dir  <- if (length(args) >= 2) args[2] else file.path(tempdir(), "hicarta_plugin_test")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

if (!file.exists("app.R")) stop("run from the HiCarta folder (where app.R is)")
suppressWarnings(suppressMessages({
  for (f in c("i18n", "s3", "hic_reader", "bigwig_reader", "readers", "juicer_menu",
              "catalog", "bookmarks", "draw", "tiles", "tracks", "genes",
              "borderstrength", "arcs", "rotmap", "chrominfo", "export", "plugins"))
    source(file.path("R", paste0(f, ".R")), local = FALSE)
}))
`%||%` <- function(a, b) if (is.null(a)) b else a
fails <- character(0)
check <- function(ok, what) {
  cat(if (isTRUE(ok)) "  ok   " else "  FAIL ", what, "\n")
  if (!isTRUE(ok)) fails <<- c(fails, what)
}

cat("== load plugins\n")
ids <- load_plugins("plugins")
for (ln in plugin_report_text()) cat("  ", ln, "\n")
check(all(c("v4c", "table") %in% ids), "v4c and table are registered")
check(!length(plugin_failures()), "no plugin file failed")
check(identical(plugin_type("v4c"), "plugin:v4c") && is_plugin_type("plugin:v4c") &&
        !is_plugin_type("bigWig"), "type helpers")
check(identical(plugin_guess("x/y/scores.csv"), "table") &&
        is.na(plugin_guess("a.bw")), "extension claim (csv -> table)")
check(identical(cat_guess_type("my.tsv"), "table"), "cat_guess_type consults plugins")
check("table" %in% cat_file_types(), "cat_file_types() includes plugin ids")

# a broken plugin must be reported, not fatal
bad_dir <- file.path(tempdir(), "bad_plugins"); dir.create(bad_dir, showWarnings = FALSE)
writeLines(c("hicarta_plugin(id = 'oops', draw = 42)"), file.path(bad_dir, "a_bad.R"))
writeLines(c("# no registration here", "x <- 1"), file.path(bad_dir, "b_empty.R"))
file.copy("plugins/table_signal.R", file.path(bad_dir, "c_good.R"), overwrite = TRUE)
ids2 <- load_plugins(bad_dir)
rep2 <- plugin_report()
check(identical(ids2, "table") && !rep2[["a_bad.R"]]$ok && !rep2[["b_empty.R"]]$ok &&
        rep2[["c_good.R"]]$ok, "bad / empty / good plugin files are reported correctly")
load_plugins("plugins")

cat("== parameters\n")
spec <- list(id = 1, name = "t", path = "x", type = "plugin:v4c", color = "red",
             height = 90, ymin = NA, ymax = 0,
             params = list(anchor = "1234", log = "yes", norm = "", window = "abc"))
pp <- plugin_params(spec)
check(identical(pp$anchor, 1234) && isTRUE(pp$log) && identical(pp$norm, "KR") &&
        identical(pp$window, 1), "text overrides are coerced to the defaults' types")
check(identical(plugin_params_text(spec)$anchor, "1234"), "params back to text")

cat("== table plugin: draw from a CSV\n")
csv <- file.path(out_dir, "scores.csv")
set.seed(1)
tab <- data.frame(chr = "I", start = seq(0, 999000, by = 1000),
                  end = seq(1000, 1000000, by = 1000))
tab$value <- round(sin(tab$start / 50000) + rnorm(nrow(tab), sd = 0.2), 3)
write.csv(tab, csv, row.names = FALSE, quote = FALSE)
tspec <- list(id = 2, name = "my score", path = csv, type = "plugin:table",
              color = "#2166AC", height = 90, ymin = NA, ymax = 0, params = list())
ci <- track_chrom_info(csv, "plugin:table")
check(identical(names(ci), "I") && ci[["I"]] == 1e6, "chroms() via track_chrom_info")
for (sty in c("bar", "line", "area")) {
  tspec$params <- list(style = sty)
  png(file.path(out_dir, sprintf("table_%s.png", sty)), width = 1200, height = 140)
  plugin_draw(tspec, "I", 200000, 600000, chrlen = 1e6)
  dev.off()
}
png(file.path(out_dir, "table_print.png"), width = 1200, height = 140)
plugin_draw(tspec, "I", 200000, 600000, chrlen = 1e6, mar = c(0.3, 4, 0.3, 0),
            frame = FALSE, yscale = "axis")
dev.off()
check(file.exists(file.path(out_dir, "table_bar.png")), "table plugin drew (bar/line/area/print)")
# a view running past the chromosome end (dend clamps) and an empty region
png(file.path(out_dir, "table_edge.png"), width = 1200, height = 140)
plugin_draw(tspec, "I", 900000, 1300000, chrlen = 1e6); dev.off()
png(file.path(out_dir, "table_empty.png"), width = 1200, height = 140)
plugin_draw(tspec, "II", 1, 1000, chrlen = 1e6); dev.off()
check(TRUE, "edge / empty views did not error")

cat("== error inside draw() is contained\n")
hicarta_plugin(id = "boom", draw = function(d, chr, vstart, vend, style) stop("kaboom"))
png(file.path(out_dir, "boom.png"), width = 600, height = 100)
r <- tryCatch({ plugin_draw(list(type = "plugin:boom", name = "b", path = "x", params = list()),
                            "I", 1, 1000, chrlen = 1e6); TRUE }, error = function(e) FALSE)
dev.off()
check(isTRUE(r), "draw() error becomes a message in the panel, not an R error")
png(file.path(out_dir, "missing.png"), width = 600, height = 100)
r <- tryCatch({ plugin_draw(list(type = "plugin:nope", name = "n", path = "x", params = list()),
                            "I", 1, 1000, chrlen = 1e6); TRUE }, error = function(e) FALSE)
dev.off()
check(isTRUE(r), "unknown plugin type draws a message")
load_plugins("plugins")

cat("== catalog with a plugin row\n")
if (requireNamespace("openxlsx", quietly = TRUE) && requireNamespace("readxl", quietly = TRUE)) {
  cat_df <- data.frame(id = 1:2, name = c("scores", "v4c of sample"),
                       path = c(csv, if (nzchar(hic_path)) hic_path else "x.hic"),
                       file_type = c("", "v4c"), set_anchor = c("", "1500000"),
                       stringsAsFactors = FALSE)
  xl <- file.path(out_dir, "cat.xlsx")
  openxlsx::write.xlsx(cat_df, xl)
  cat_r <- read_catalog(xl)
  check(identical(cat_r$file_type, c("table", "v4c")), "file_type: guessed 'table' from .csv, 'v4c' accepted")
  check(identical(catalog_set_value(cat_r, 2, "anchor", 1L), "1500000"), "set_anchor read via catalog_set_value")
  check(!length(cat_r$excluded %||% list()), "no row excluded")
} else cat("  skip (openxlsx / readxl not installed)\n")

cat("== session round trip\n")
if (requireNamespace("jsonlite", quietly = TRUE)) {
  js <- jsonlite::toJSON(list(tracks = list(list(path = csv, type = "plugin:table",
                                                 params = list(style = "line", value_col = "4")))),
                         auto_unbox = TRUE, null = "null", na = "null")
  back <- jsonlite::fromJSON(js, simplifyVector = FALSE)
  t <- back$tracks[[1]]
  pr <- { v <- t$params; if (is.list(v) && length(v) && !is.null(names(v))) v else list() }
  check(identical(pr$style, "line") && identical(pr$value_col, "4"), "params survive JSON")
}

cat("== virtual 4C on a real .hic\n")
if (nzchar(hic_path) && file.exists(hic_path)) {
  chroms <- hic_chroms(hic_path)
  keep <- chrom_is_real(chroms$name)
  cn <- chroms$name[keep][1]; cl <- chroms$length[keep][1]
  res_all <- hic_resolutions(hic_path)
  cat("   file:", basename(hic_path), " chr:", cn, " len:", cl,
      " resolutions:", paste(res_all, collapse = ","), " norms:",
      paste(hic_norms(hic_path), collapse = ","), "\n")
  v0 <- max(1, round(cl * 0.3)); v1 <- round(cl * 0.5)
  vspec <- list(id = 3, name = "virtual 4C", path = hic_path, type = "plugin:v4c",
                color = "#B2182B", height = 110, ymin = NA, ymax = 0,
                params = list(anchor = round((v0 + v1) / 2), norm = "NONE"))
  t0 <- Sys.time()
  d <- plugin_data(vspec, cn, v0, v1)
  dt <- as.numeric(Sys.time() - t0, units = "secs")
  check(is.data.frame(d) && nrow(d) > 10 && any(d$value > 0),
        sprintf("read %d bins at %s bp in %.2f s", nrow(d), d$res[1], dt))
  t0 <- Sys.time(); d2 <- plugin_data(vspec, cn, v0, v1)
  check(as.numeric(Sys.time() - t0, units = "secs") < dt / 2 + 0.01, "second read comes from the cache")
  # the anchor bin should be the (or near the) maximum of the profile
  ia <- which.min(abs((d$start + d$end) / 2 - vspec$params$anchor))
  check(d$value[ia] >= stats::quantile(d$value, 0.9), "anchor bin is among the strongest")
  png(file.path(out_dir, "v4c_screen.png"), width = 1200, height = 160)
  plugin_draw(vspec, cn, v0, v1, chrlen = cl); dev.off()
  png(file.path(out_dir, "v4c_print.png"), width = 1200, height = 160)
  plugin_draw(vspec, cn, v0, v1, chrlen = cl, mar = c(0.3, 4, 0.3, 0),
              frame = FALSE, yscale = "axis"); dev.off()
  vspec$params <- list(anchor = round((v0 + v1) / 2), norm = "NONE", log = "TRUE", window = 3, smooth = 3)
  png(file.path(out_dir, "v4c_log_w3.png"), width = 1200, height = 160)
  plugin_draw(vspec, cn, v0, v1, chrlen = cl); dev.off()
  check(file.exists(file.path(out_dir, "v4c_log_w3.png")), "v4c drew (screen / print / log+window)")
  # a view that runs past the chromosome end
  png(file.path(out_dir, "v4c_edge.png"), width = 1200, height = 160)
  plugin_draw(vspec, cn, round(cl * 0.9), round(cl * 1.2), chrlen = cl); dev.off()
  check(TRUE, "v4c view past the chromosome end did not error")
  ci <- track_chrom_info(hic_path, "plugin:v4c")
  check(!is.null(ci) && cn %in% names(ci), "track-only coordinate system from a v4c track (.hic header)")
} else cat("  skip (no .hic given)\n")

cat("\nPNG files in", out_dir, "\n")
if (length(fails)) { cat("\nFAILED:\n"); cat(paste(" -", fails), sep = "\n"); quit(status = 1) }
cat("\nALL OK\n")

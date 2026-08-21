#!/usr/bin/env Rscript
# ============================================================================
# test_hic_resolutions.R - the chromosome-aware resolution probe.
#
# A .hic header lists the resolutions the FILE was built with, globally. One
# chromosome's matrix can carry fewer zoom levels, and a normalization vector
# can be missing at some of them - reading there fails and the viewer shows a
# blank map. hic_chr_resolutions() / hic_resolutions_chr() answer per
# chromosome and normalization; the zoom ladder is built from their answer.
#
# The fixture below is a public S. pombe file whose chromosome I has NO 200 bp
# KR vector while II and III do - exactly the asymmetry the probe exists for.
#
# Run from the HiCarta folder (needs network access):
#   Rscript scripts/test_hic_resolutions.R
# ============================================================================

for (f in list.files("R", full.names = TRUE, pattern = "[.]R$"))
  if (!grepl("install_lib", f)) source(f)
options(hicarta.hic_engine = "native")

p <- paste0("https://uo-cgf.s3.us-west-2.amazonaws.com/P/020/wt_Db_MHM_mix3/",
            "wt_Db_MHM_mix3_KR.200bp.500bp.2kb.hic")
rd <- hic_reader(p)

# the header's global list
stopifnot(identical(sort(hic_meta(rd)$resolutions), c(200L, 500L, 2000L)))

# chr I: the matrix has all three, but KR has no 200 bp vector there
stopifnot(identical(hic_chr_resolutions(rd, "I"), c(200, 500, 2000)))
stopifnot(identical(hic_chr_resolutions(rd, "I", normalization = "KR"), c(500, 2000)))
stopifnot(identical(hic_chr_resolutions(rd, "II", normalization = "KR"), c(200, 500, 2000)))

# chr-prefix tolerance, and an unknown chromosome errors (callers fall back)
stopifnot(identical(hic_chr_resolutions(rd, "chrI", normalization = "KR"), c(500, 2000)))
stopifnot(inherits(tryCatch(hic_chr_resolutions(rd, "ZZ"), error = function(e) e), "error"))

# the path-level wrapper: same answer, and a fallback that never returns empty
stopifnot(identical(hic_resolutions_chr(p, "I", "KR"), c(500, 2000)))
stopifnot(length(hic_resolutions_chr(p, "ZZ", "KR")) == 3)   # header list

# read_hic_map() snaps the requested resolution per chromosome AND normalization
m <- read_hic_map(p, chr = "I", start = 1, end = 400000,
                  resolution = 200, normalization = "KR")
stopifnot(diff(parse_bin_labels(rownames(m))$start[1:2]) == 500,
          sum(m > 0, na.rm = TRUE) > 0)
m2 <- read_hic_map(p, chr = "II", start = 1, end = 400000,
                   resolution = 200, normalization = "KR")
stopifnot(diff(parse_bin_labels(rownames(m2))$start[1:2]) == 200,
          sum(m2 > 0, na.rm = TRUE) > 0)

# a single-resolution file is unaffected
q <- paste0("https://uo-cgf.s3.us-west-2.amazonaws.com/P/020/wt_Db_MHM_mix3/",
            "wt_Db_MHM_mix3_ICE.5kb.hic")
stopifnot(identical(hic_resolutions_chr(q, "II", "NONE"), 5000))

cat("resolution probe: all OK\n")

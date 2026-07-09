# ============================================================================
# juicer_menu.R  -  Parse a Juicer-style sample menu file.
#
# Format (see uo-cgf juicer_020.txt):
#   <id> = <parent>, <label>[, <url_or_path>]
#
#   * A line whose parent is "root" defines a SAMPLE (group) node.
#       001_wt_HiC = root, 001_wt_HiC
#   * A child line points at one .hic dataset (a resolution/normalization).
#       001_wt_HiC_1 = 001_wt_HiC, ICE.100kb, https://.../wt_ICE.100kb.hic
#
# parse_juicer_menu() returns a data.frame with one row per dataset (leaf):
#   sample_id, sample_label, dataset_id, dataset_label, url
# ============================================================================

parse_juicer_menu <- function(path_or_lines) {
  lines <- if (length(path_or_lines) == 1 && file.exists(path_or_lines)) {
    readLines(path_or_lines, warn = FALSE)
  } else {
    path_or_lines
  }
  lines <- trimws(lines)
  lines <- lines[nchar(lines) > 0 & !startsWith(lines, "#")]

  ids     <- character(0)
  parents <- character(0)
  labels  <- character(0)
  urls    <- character(0)

  for (ln in lines) {
    kv <- strsplit(ln, "=", fixed = TRUE)[[1]]
    if (length(kv) < 2) next
    id  <- trimws(kv[1])
    rhs <- trimws(paste(kv[-1], collapse = "="))
    parts <- trimws(strsplit(rhs, ",", fixed = TRUE)[[1]])
    parent <- parts[1]
    label  <- if (length(parts) >= 2) parts[2] else id
    url    <- if (length(parts) >= 3) paste(parts[-(1:2)], collapse = ",") else NA_character_
    ids     <- c(ids, id)
    parents <- c(parents, parent)
    labels  <- c(labels, label)
    urls    <- c(urls, url)
  }

  nodes <- data.frame(id = ids, parent = parents, label = labels,
                      url = urls, stringsAsFactors = FALSE)

  # sample (group) nodes have parent == "root"
  samples <- nodes[nodes$parent == "root", c("id", "label")]
  names(samples) <- c("sample_id", "sample_label")

  leaves <- nodes[!is.na(nodes$url) & nzchar(nodes$url), ]
  if (nrow(leaves) == 0) {
    return(data.frame(sample_id = character(0), sample_label = character(0),
                      dataset_id = character(0), dataset_label = character(0),
                      url = character(0)))
  }
  out <- merge(leaves, samples,
               by.x = "parent", by.y = "sample_id", all.x = TRUE)
  data.frame(
    sample_id     = out$parent,
    sample_label  = ifelse(is.na(out$sample_label), out$parent, out$sample_label),
    dataset_id    = out$id,
    dataset_label = out$label,
    url           = out$url,
    stringsAsFactors = FALSE
  )[order(out$id), ]
}

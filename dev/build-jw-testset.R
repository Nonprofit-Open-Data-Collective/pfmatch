#!/usr/bin/env Rscript
# ============================================================================
# An evaluation set for the Jaro-Winkler generic-head problem.
#
# The claim to test: JW >= 0.95 on names sharing a long generic head
# ("CONGREGATION ...", "FIRST BAPTIST CHURCH OF ...") does not mean the same
# organization, because the shared head dilutes the discriminating part.
#
# Two labelled sets, both cheap and both honest:
#
#   NEGATIVES -- pairs of DISTINCT BMF EINs, same state, whose name_keys score
#     JW >= 0.95. Different EIN = different organization, by construction. This
#     is the exact population the promotion floor would auto-accept if a grant
#     landed between them.
#
#   POSITIVES -- accepted grant->BMF matches from the YES tier whose ZIP5 agrees
#     exactly. The address corroborates the name independently, so these are
#     name matches we believe for a reason other than the name.
#
# A useful feature separates these. JW alone, by construction, cannot.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")
set.seed(41)

B   <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))
ref <- B$reference
setDT(ref)

hr(); say("NEGATIVES: distinct BMF EINs, same state, JW >= 0.95"); hr()
# block on (state, first token) to make the search tractable, then score within
ref[, tok1 := sub(" .*$", "", ifelse(is.na(name_key), "", name_key))]
ok <- ref[nzchar(tok1) & !is.na(state) & nzchar(state) & nchar(name_key) >= 8]
say("reference rows eligible: %s", format(nrow(ok), big.mark = ","))
grp <- ok[, .N, by = .(state, tok1)][N >= 2 & N <= 60]
say("blocks with 2-60 members: %s", format(nrow(grp), big.mark = ","))
grp <- grp[sample(.N, min(4000, .N))]
setkey(ok, state, tok1)

neg <- rbindlist(lapply(seq_len(nrow(grp)), function(i) {
  s <- ok[.(grp$state[i], grp$tok1[i])]
  if (nrow(s) < 2) return(NULL)
  cb <- utils::combn(nrow(s), 2)
  if (ncol(cb) > 200) cb <- cb[, sample(ncol(cb), 200), drop = FALSE]
  a <- s$name_key[cb[1, ]]; b <- s$name_key[cb[2, ]]
  jw <- 1 - stringdist::stringdist(a, b, method = "jw", p = 0.1)
  k <- which(jw >= 0.95 & a != b)
  if (!length(k)) return(NULL)
  data.table(a = a[k], b = b[k], jw = jw[k],
             ein_a = s$.ein[cb[1, k]], ein_b = s$.ein[cb[2, k]], label = 0L)
}), fill = TRUE)
neg <- neg[!duplicated(paste(pmin(a, b), pmax(a, b)))]
say("negatives collected: %s", format(nrow(neg), big.mark = ","))
say("examples:")
for (i in head(sample(nrow(neg)), 10))
  say("   %-38s | %-38s  jw=%.3f", substr(neg$a[i], 1, 38), substr(neg$b[i], 1, 38), neg$jw[i])

hr(); say("POSITIVES: YES matches with an exact ZIP5 agreement"); hr()
m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
st <- pf_status(m)
pr <- as.data.table(attr(m$result, "pairs"))
sel <- pr[paste(.id, .ein) %in% paste(st$grant_id[st$status == "YES"], st$ein[st$status == "YES"])]
sel <- sel[as.numeric(geo_zip5) == 1 & !is.na(name_key_x) & !is.na(name_key_y)]
sel[, jw := 1 - stringdist::stringdist(name_key_x, name_key_y, method = "jw", p = 0.1)]
pos <- sel[jw >= 0.95, .(a = name_key_x, b = name_key_y, jw, ein_a = NA_character_,
                         ein_b = .ein, label = 1L)]
pos <- pos[!duplicated(paste(a, b))]
say("positives collected: %s (ZIP5-confirmed, JW >= 0.95)", format(nrow(pos), big.mark = ","))

ts <- rbind(neg, pos, fill = TRUE)
fwrite(ts, file.path(PF, "data-dev", "JW-HEAD-TESTSET.csv"))
say("\nwrote data-dev/JW-HEAD-TESTSET.csv | %s negatives, %s positives",
    format(sum(ts$label == 0), big.mark = ","), format(sum(ts$label == 1), big.mark = ","))
say("JW on this set is uninformative by construction:")
say("  negatives median JW %.4f | positives median JW %.4f",
    stats::median(neg$jw), stats::median(pos$jw))

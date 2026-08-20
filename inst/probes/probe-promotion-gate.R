#!/usr/bin/env Rscript
# Two distinct failure modes surfaced. Check each on its own terms.
#   (a) generic-but-lexically-unique name  -> an IDF gate should catch it
#   (b) high JW on genuinely different names, carried by a shared generic
#       prefix ("CONGREGATION ...") -> nothing to do with the promotion floor
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

p <- readRDS(file.path(PF, "data-dev", "PROMOTION-PROBE.rds"))
B <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))
idf <- B$token_idf; sw <- npmatch::np_stopwords()
name_idf <- function(nm) {
  d <- npmatch::np_normalize(npmatch::np_query(
    data.frame(id = seq_along(nm), name = nm, state = "XX", stringsAsFactors = FALSE),
    c(.id = "id", name = "name", state = "state")))
  vapply(strsplit(ifelse(is.na(d$name_key), "", d$name_key), " ", fixed = TRUE),
         function(t) { t <- t[nzchar(t) & !(t %in% sw) & nchar(t) >= 2]
           if (!length(t)) return(0)
           w <- idf[t]; w[is.na(w)] <- max(idf, na.rm = TRUE); sum(w) }, numeric(1))
}
st <- p$on; dep <- st$grant_id %in% p$dep_ids
st$nidf <- name_idf(st$recip_name)

hr(); say("(a) THE 5 THAT AN IDF>=10 GATE WOULD DEMOTE -- are they correct?"); hr()
i <- which(dep & st$nidf < 10)
print(data.table(name = substr(st$recip_name[i], 1, 30), idf = round(st$nidf[i], 1),
                 qcity = substr(st$recip_city[i], 1, 15), qst = st$recip_state[i],
                 bmf = substr(st$bmf_name[i], 1, 30),
                 bcity = substr(st$bmf_city[i], 1, 15), bst = st$bmf_state[i]),
      row.names = FALSE)

hr(); say("(b) IS THE AGUDATH/ADAT ERROR A PROMOTION PROBLEM?"); hr()
prs <- list(c("CONGREGATION AGUDATH ISRAEL", "CONGREGATION ADAT ISRAEL"),
            c("AGUDATH ISRAEL", "ADAT ISRAEL"),
            c("FIRST BAPTIST CHURCH OF SALEM", "FIRST BAPTIST CHURCH OF SALINE"),
            c("BAPTIST SALEM", "BAPTIST SALINE"))
say("%-32s %-32s %6s", "A", "B", "JW")
for (q in prs)
  say("%-32s %-32s %6.3f", q[1], q[2],
      1 - stringdist::stringdist(q[1], q[2], method = "jw", p = 0.1))
say("")
say("Stripping the shared generic head collapses the score: the pair only clears")
say("the 0.95 promotion bar because 'CONGREGATION ' is 13 identical leading")
say("characters and Jaro-Winkler pays a prefix bonus on top of that.")
say("This is a comparator property, not a property of the floor -- the same pair")
say("would score 0.95+ with the floor switched off entirely.")

hr(); say("(c) HOW MANY PROMOTED PAIRS RIDE ON A SHARED GENERIC HEAD?"); hr()
pr <- as.data.table(attr(readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))$result, "pairs"))
sel <- pr[paste(.id, .ein) %in% paste(st$grant_id[dep], st$ein[dep])]
heads <- c("CONGREGATION", "FIRST", "SAINT", "TEMPLE", "CHURCH", "FRIENDS",
           "AMERICAN", "NATIONAL", "COMMUNITY", "UNITED")
sel[, head1 := sub(" .*$", "", toupper(ifelse(is.na(name_key_x), "", name_key_x)))]
say("promoted pairs whose FIRST token is a common institutional word: %d of %d (%.0f%%)",
    sum(sel$head1 %in% heads), nrow(sel), 100 * mean(sel$head1 %in% heads))
print(sort(table(sel$head1[sel$head1 %in% heads]), decreasing = TRUE))

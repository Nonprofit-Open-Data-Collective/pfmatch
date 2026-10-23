#!/usr/bin/env Rscript
# ============================================================================
# The six NO-residual pairs, scored by each candidate metric.
#
# Small, self-contained and corpus-free, so the mechanism is visible: these are
# the exact pairs from dev/NO-RESIDUAL-AUDIT.md where the reference holds the
# right name AND the right city and the pipeline still said NO. The production
# comparator is Jaro-Winkler floored at 0.85.
#
# Unweighted token measures are used here (no IDF) precisely so the numbers can
# be checked by hand; dev/compare-name-metrics.R runs the weighted versions
# against hard negatives, which is what actually decides anything.
# ============================================================================
suppressWarnings(suppressMessages(library(stringdist)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
say <- function(...) message(sprintf(...))

pairs <- rbind(
  c("MUSCULAR DYSTROPHY",                   "MUSCULAR DYSTROPHY ASSOCIATIONS OF AMERICA INC"),
  c("DANCE PLACE DC WHEEL PRODUCTIONS INC", "DC WHEEL PRODUCTIONS INC AKA DANCE PLACE"),
  c("The Salvation Army",                   "SALVATION ARMY BIRMINGHAM AREA COMMAND"),
  c("JUVENILE DIABETES RESEARCH FOUNDATION","JUVENILE DIABETES RESEARCH FOUNDATION GA CHAPTER"),
  c("Cong Mesilas Hachessed",               "CONGREGATION MESILAS HACHESED"),
  c("CASA OF NJ",                           "COURT APPOINTED SPECIAL ADVOCATES OF NEW JERSEY INC"),
  c("BOROUGHS COMMUNITY CENTER",            "BURROUGHS COMMUNITY CENTER INC"),
  c("LIONS EYE DOUNDATION OF CA & NV",      "LIONS EYE FOUNDATION OF CALIFORNIA NEVADA INC"))
colnames(pairs) <- c("filed", "reference")

nkey <- function(x) {
  nm <- npmatch:::.np_basic_clean(x)
  nm <- npmatch:::.np_replace_tokens(nm, npmatch:::.np_abbrev)
  npmatch:::.np_strip_lead_the(npmatch:::.np_strip_suffix(nm))
}
SW <- np_stopwords()
tk <- function(x) { v <- strsplit(x, " +")[[1]]; v[nchar(v) >= 2L & !(v %in% SW)] }

jw <- function(a, b) 1 - stringdist(a, b, method = "jw", p = 0.1)
m_tokjac <- function(a, b) { a <- tk(a); b <- tk(b)
  if (!length(a) || !length(b)) 0 else length(intersect(a,b))/length(union(a,b)) }
m_contain <- function(a, b) { a <- tk(a); b <- tk(b)
  if (!length(a) || !length(b)) 0 else length(intersect(a,b))/min(length(a),length(b)) }
m_monge <- function(a, b) { a <- tk(a); b <- tk(b)
  if (!length(a) || !length(b)) return(0)
  if (length(a) > length(b)) { t <- a; a <- b; b <- t }
  mean(vapply(a, function(x) max(jw(x, b)), 0)) }
m_acr <- function(a, b) { a <- tk(a); b <- tk(b)
  f <- function(p, q) if (length(p)==1L && nchar(p)>=2L && length(q)>=2L)
         as.numeric(identical(p, paste(substr(q,1,1), collapse=""))) else 0
  max(f(a,b), f(b,a)) }

say("")
say("%-26s %-30s %6s %6s %6s %6s %6s", "filed (key)", "reference (key)",
    "JW", "tokJac", "contn", "mongE", "acrny")
say("%s", strrep("-", 92))
for (i in seq_len(nrow(pairs))) {
  a <- nkey(pairs[i, 1]); b <- nkey(pairs[i, 2])
  say("%-26s %-30s %6.2f %6.2f %6.2f %6.2f %6.2f",
      substr(a, 1, 26), substr(b, 1, 30),
      jw(a, b), m_tokjac(a, b), m_contain(a, b), m_monge(a, b), m_acr(a, b))
}
say("%s", strrep("-", 92))
say("production accepts at JW >= 0.85; anything below is floored to 0.")

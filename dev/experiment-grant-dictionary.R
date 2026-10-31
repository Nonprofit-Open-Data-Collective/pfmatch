#!/usr/bin/env Rscript
# ============================================================================
# experiment-grant-dictionary.R -- match grants against GRANTS, not the BMF.
#
# THE HYPOTHESIS. Foundations write recipient names by a convention of their
# own; the BMF carries the registered legal name. So a grant that fails against
# the BMF might still match a grant that already cleared. Measured support, on
# the 312,306 cleared rows of the triangulation run
# (dev/EXP-HEAD-REFERENCE.log addendum):
#
#   hits another cleared GRANT rendering exactly   94.06%
#   hits its own BMF name exactly                  47.16%
#   grant-exact but NOT bmf-exact                  48.12%
#
# but on FUZZY distance the grant side is marginally WORSE (median 0.960 to the
# nearest other rendering against 0.967 to the BMF name). The advantage is in
# frequency, not similarity, so it should show up as exact-key recall on cases
# the BMF matcher could not clear. That is what this tests.
#
# THE TEST. Build a dictionary from the filer-written name and address of every
# cleared grant row, carrying the EIN it resolved to. Match the benchmark's own
# rows against it and cross-tabulate against their BMF-reference tier. The cells
# that matter are MAYBE -> YES and NO -> YES: cases the production reference
# could not clear that a grant-side dictionary can.
#
# WHAT THIS CANNOT ESTABLISH, and it has to be said before the numbers are read.
# Every EIN in the dictionary was assigned by this same pipeline, so resolving
# against it propagates the pipeline's own decisions, errors included. It is a
# RECALL device whose precision is inherited, not established. Two controls:
#   * ambiguity -- how many dictionary name keys carry more than one EIN. A bare
#     "THE ARC" key would collapse hundreds of unrelated local chapters, so the
#     dictionary keys on name AND address.
#   * agreement -- for every MAYBE/NO the dictionary clears, whether its EIN is
#     the one the BMF reference already held as its own top candidate. Agreement
#     means the answer was recoverable and the gate would not release it;
#     disagreement is a new claim and needs adjudication, not adoption.
#
# USAGE
#   PFMATCH_DIR=. Rscript dev/experiment-grant-dictionary.R
#   PF_DICT_STATS=production   use the BMF name_freq/token_idf instead of the
#                              dictionary's own (the IDF of ~100k filer names
#                              is not the IDF of 3.88M BMF names)
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 84))
nf  <- function(x) format(x, big.mark = ",")
pc  <- function(a, b) sprintf("%s (%.2f%%)", nf(a), 100 * a / b)
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }
STATS <- tolower(Sys.getenv("PF_DICT_STATS", "dictionary"))
BENCH <- file.path(PF, "dev", "BASELINE-2026-10C", "benchmark-1k-augmented.rds")

hr(); say("experiment-grant-dictionary   stats %s   %s", STATS, format(Sys.time())); hr()

## ---- 1. the benchmark, and its grant keys so the dictionary can exclude them
b <- as.data.table(readRDS(BENCH))
b[, ein9_full := e9(overall_ein)]
grants <- pf_read_grants(file.path(PF, "inputs"),
                         pattern = "^efv2_1k_grants_.*[.]csv$")
grants <- pf_recover_name_from_street(grants)
bkey <- unique(paste(sq(grants$OBJECTID), sq(grants$TABLE_ID), sep = "|"))
say("benchmark: %s grant rows, %s tiered rows", nf(nrow(grants)), nf(nrow(b)))
print(b[, .N, by = tier][order(-N)], row.names = FALSE)

## ---- 2. the dictionary: filer-written renderings of cleared grants ----------
g <- as.data.table(readRDS(file.path(PF, "data-dev", "TRI-V2-MATCH.rds"))$grants)
y <- g[status == "YES" & !is.na(ein) & nzchar(sq(ein))]
say("")
say("cleared rows available: %s over %s EINs", nf(nrow(y)), nf(uniqueN(e9(y$ein))))
y[, gkey := paste(sq(OBJECTID), sq(TABLE_ID), sep = "|")]
n_before <- nrow(y)
y <- y[!(gkey %chin% bkey)]
say("excluded %s rows that are the benchmark's own (circularity)",
    nf(n_before - nrow(y)))

# One row per distinct filer rendering + address + EIN. The address is part of
# the key on purpose: "THE ARC" alone maps to hundreds of unrelated chapters.
d <- unique(y[, .(ein = e9(ein), name = sq(recip_name), street = sq(recip_street),
                  city = sq(recip_city), state = sq(recip_state),
                  zip5 = sq(recip_zip5))])
d <- d[!is.na(ein) & nzchar(name)]
say("dictionary: %s distinct (rendering, address, EIN) rows over %s EINs",
    nf(nrow(d)), nf(uniqueN(d$ein)))

## ---- 3. ambiguity, before anything is matched ------------------------------
nrm <- function(x) trimws(gsub(" +", " ", gsub("[^A-Z0-9 ]", " ", toupper(sq(x)))))
d[, nk := nrm(name)]
amb_n <- d[, .(eins = uniqueN(ein)), by = nk]
amb_na <- d[, .(eins = uniqueN(ein)), by = .(nk, zip5)]
hr(); say("AMBIGUITY of the dictionary keys")
say("  distinct name keys                      %s", nf(nrow(amb_n)))
say("  name keys carrying >1 EIN               %s", pc(sum(amb_n$eins > 1), nrow(amb_n)))
say("  worst name key                          %s EINs", max(amb_n$eins))
say("  distinct (name, zip5) keys              %s", nf(nrow(amb_na)))
say("  (name, zip5) keys carrying >1 EIN       %s", pc(sum(amb_na$eins > 1), nrow(amb_na)))
say("  -> the address is what makes the key usable")
say("")
say("  the most ambiguous bare names:")
print(head(amb_n[order(-eins)], 8), row.names = FALSE)

## ---- 4. shape it as a reference npmatch can read ---------------------------
# np_reference() wants the BMF column names; the VALUES are grant-side text,
# which is the whole point of the experiment.
m <- npmatch::np_map_bmf()
raw <- data.table(ein = d$ein, org_name_join = d$name, dba_name = "",
                  org_addr_street = d$street, org_addr_city = d$city,
                  org_addr_state = d$state, org_addr_zip5 = d$zip5,
                  org_addr_zip4 = "")
setnames(raw, unname(m[c(".ein","name","dba","street","city","state","zip5","zip_plus4")]))
ref <- npmatch::np_normalize(npmatch::np_reference(as.data.frame(raw), m))
ref <- pf_add_recovery_keys(ref)
say("")
say("dictionary reference: %s rows, %s columns", nf(nrow(ref)), ncol(ref))

prod <- NULL
if (STATS == "production") {
  prod <- readRDS(file.path(PF, "data-dev", "REF-augmented.rds"))
  pf_check_reference(prod)
}
bundle <- list(
  reference  = ref,
  name_freq  = if (STATS == "production") prod$name_freq else npmatch::np_name_freq(ref$name_key),
  token_idf  = if (STATS == "production") prod$token_idf else npmatch::np_token_idf(ref$name_key),
  ref_index  = npmatch::np_ref_index(ref),
  normalizer = tryCatch(npmatch::np_normalize_signature(), error = function(e) NA_character_))
say("statistics: %s", STATS)

## ---- 5. match the benchmark against the dictionary -------------------------
PASSES <- c(pf_staged_passes("lean", concat = TRUE),
            pf_recovery_passes(state = TRUE))
t0 <- proc.time()[["elapsed"]]
mm <- pf_match_grants(grants, bundle, passes = PASSES, recover = TRUE,
                      verbose = FALSE)
el <- proc.time()[["elapsed"]] - t0
s <- as.data.table(as.data.frame(mm$result))
say("matched %s rows in %.1f s (%.4f s/row)", nf(nrow(s)), el,
    el / max(1, nrow(s)))

j <- merge(s[, .(.id, dict_tier = tier, dict_ein = e9(overall_ein),
                 dict_score = suppressWarnings(as.numeric(overall_score)),
                 dict_name_y = overall_name_y)],
           b[, .(.id, name_x, bmf_tier = tier, bmf_ein = ein9_full,
                 bmf_score = overall_score)],
           by = ".id", all.y = TRUE)
hr(); say("BMF-reference tier  x  grant-dictionary tier")
print(dcast(j, bmf_tier ~ dict_tier, value.var = ".id", fun.aggregate = length),
      row.names = FALSE)

## ---- 6. the cells that matter, with the agreement control ------------------
hr(); say("WHAT THE DICTIONARY RECOVERS")
for (ft in c("MAYBE", "NO")) {
  k <- j[bmf_tier == ft & dict_tier == "YES"]
  tot <- nrow(j[bmf_tier == ft])
  say("")
  say("  %s -> YES on the dictionary: %s of %s", ft, nf(nrow(k)), nf(tot))
  if (!nrow(k)) next
  agree <- k[!is.na(bmf_ein) & dict_ein == bmf_ein]
  say("    dictionary EIN == the BMF reference's own top candidate: %s",
      pc(nrow(agree), nrow(k)))
  say("      -> recoverable all along; the gate would not release it")
  say("    dictionary EIN differs, or the BMF had none: %s",
      nf(nrow(k) - nrow(agree)))
  say("      -> a new claim. Adjudicate; do not adopt.")
  say("    examples:")
  print(head(k[, .(name_x = substr(sq(name_x), 1, 34),
                   dict_name_y = substr(sq(dict_name_y), 1, 34),
                   dict_ein, bmf_ein, dict_score = round(dict_score, 3))], 8),
        row.names = FALSE)
}
say("")
say("  cost of the dictionary on cases the BMF already cleared:")
say("    BMF YES -> dictionary not YES : %s of %s",
    nf(nrow(j[bmf_tier == "YES" & (is.na(dict_tier) | dict_tier != "YES")])),
    nf(nrow(j[bmf_tier == "YES"])))
say("    BMF YES -> dictionary YES, DIFFERENT EIN: %s",
    nf(nrow(j[bmf_tier == "YES" & dict_tier == "YES" & !is.na(dict_ein) &
              !is.na(bmf_ein) & dict_ein != bmf_ein])))
out <- file.path(PF, "data-dev", sprintf("EXP-DICT-%s.rds", STATS))
saveRDS(list(join = j, ambiguity = amb_n, n_dict = nrow(ref)), out, compress = FALSE)
say("")
say("wrote %s", out)
hr(); say("done  %s", format(Sys.time()))

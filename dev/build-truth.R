#!/usr/bin/env Rscript
# ============================================================================
# Consolidate every hand adjudication into one ground-truth table.
#
# WHY THIS SHAPE. Almost every label this project has recorded answers "was the
# pipeline's pick right?" -- which cannot score a NEW configuration, because a
# new configuration picks a different candidate. Ground truth has to be the
# correct EIN, independent of any run. Getting that wrong is why ~700 existing
# adjudications cannot answer "is Jaro-Winkler better".
#
# So each row here is (grant, correct_ein) or (grant, why no EIN exists), plus a
# `wrong_ein` column for the cases where adjudication established that a
# specific EIN is NOT correct -- a negative constraint, which is weaker evidence
# but still usable for measuring false accepts.
#
# POPULATION. Labels are NOT portable between grant vintages: grant_id is
# positional, so the same id denotes a different grant in each population. Ids
# join at 96-97% across the two vintages and recipient names agree on 0%. Every
# row therefore carries a population fingerprint, and pf_evaluate() refuses to
# score a run from a different population. The ~500 August verdicts are on the
# archived GT population and are deliberately NOT loaded here
# (inputs/archive-gt/README.md).
#
# STABLE KEY. grant_id is positional and so breaks on re-extraction. truth_id is
# content-derived: OBJECTID + raw recipient name + raw address line 1 + amount,
# which is unique on 5,000 rows where OBJECTID alone collides 751 times (one
# filing reports up to 124 grants). Validate at full scale before relying on it
# beyond the samples.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(digest)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 84))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }

GPAT <- "^ef1k_grants_.*\\.csv$"
raw  <- pf_read_grants(file.path(PF, "inputs"), pattern = GPAT)
g    <- as.data.table(raw)
say("population: %s grant rows", format(nrow(g), big.mark = ","))

## ---- population fingerprint -------------------------------------------------
POP <- substr(digest::digest(sort(unique(sq(g$OBJECTID))), algo = "md5"), 1, 16)
say("population id: %s  (md5 of the sorted OBJECTID set)", POP)

## ---- stable content key -----------------------------------------------------
g[, truth_id := vapply(paste(sq(OBJECTID), sq(SIGOCPYRPNAM), sq(SIGOCPYRFAAL1),
                             sq(SIGOCPYAMOUN), sep = "\r"),
                       function(s) substr(digest::digest(s, algo = "xxhash64"), 1, 16),
                       character(1))]
stopifnot(!anyDuplicated(g$truth_id))
say("truth_id unique over %s rows: yes", format(nrow(g), big.mark = ","))
key <- g[, .(grant_id, truth_id, object_id = OBJECTID, recip_name)]

sim <- fread(file.path(PF, "data-dev", "TWO-TIER-SIMULATION.csv"), colClasses = "character")

mk <- function(id, verdict, correct_ein = NA_character_, wrong_ein = NA_character_,
               basis, confidence, source, note = "") {
  data.table(grant_id = id, verdict = verdict,
             correct_ein = e9(correct_ein), wrong_ein = e9(wrong_ein),
             basis = basis, confidence = confidence, source = source, note = note)
}
rows <- list()

## ---- 1. the NO-residual audit ----------------------------------------------
v <- fread(file.path(PF, "dev", "no-residual-verdicts.csv"), colClasses = "character")
rows[[1]] <- mk(v$id,
  verdict = fcase(
    v$verdict == "REAL-ORG",      "ORG_FOUND",
    v$verdict == "INDIVIDUAL",    "NO_ORG_INDIVIDUAL",
    v$verdict == "NOT-A-CHARITY", "NO_ORG_NOT_EXEMPT",
    v$verdict == "NO-OWN-EIN",    "NO_ORG_NOT_EXEMPT",
    v$verdict == "UNFINDABLE",    "NO_ORG_UNFINDABLE",
    default                     = "UNRESOLVED"),
  correct_ein = fifelse(v$verdict == "REAL-ORG", v$web_ein, NA_character_),
  basis = v$basis, confidence = fifelse(v$basis == "web", "high", "medium"),
  source = "no-residual-verdicts.csv", note = v$note)

## ---- 2. non-organisation strata of the same 100-case sample -----------------
s <- fread(file.path(PF, "data-dev", "AUDIT-NO-RESIDUAL-100.csv"), colClasses = "character")
s2 <- s[stratum != "organisation"]
rows[[2]] <- mk(s2$id,
  verdict = fcase(
    s2$stratum == "individual payee",      "NO_ORG_INDIVIDUAL",
    s2$stratum == "government body",       "NO_ORG_NOT_EXEMPT",
    default                              = "NO_ORG_UNFINDABLE"),
  basis = "inference", confidence = "medium",
  source = "AUDIT-NO-RESIDUAL-100.csv stratum",
  note = paste("stratified from the filed record:", s2$stratum))

## ---- 3. the EIN-disagreement census ----------------------------------------
e <- merge(fread(file.path(PF, "dev", "cascade-ein-verdicts.csv"), colClasses = "character"),
           sim[, .(id, ein_a, ein_b)], by = "id")
rows[[3]] <- mk(e$id,
  verdict = fifelse(e$winner %in% c("A", "B"), "ORG_FOUND", "UNRESOLVED"),
  correct_ein = fcase(e$winner == "A", e$ein_a, e$winner == "B", e$ein_b,
                      default = NA_character_),
  # the loser is an established NEGATIVE: adjudication says it is not correct
  wrong_ein = fcase(e$winner == "A", e$ein_b, e$winner == "B", e$ein_a,
                    default = NA_character_),
  basis = "reference", confidence = "medium",
  source = "cascade-ein-verdicts.csv", note = e$note)

## ---- 4. the cleared cell ----------------------------------------------------
cl <- merge(fread(file.path(PF, "dev", "cascade-cleared-verdicts.csv"), colClasses = "character"),
            sim[, .(id, ein_b)], by = "id")
rows[[4]] <- mk(cl$id,
  verdict = fifelse(cl$verdict == "CORRECT", "ORG_FOUND", "UNRESOLVED"),
  correct_ein = fifelse(cl$verdict == "CORRECT", cl$ein_b, NA_character_),
  wrong_ein   = fifelse(cl$verdict == "WRONG",   cl$ein_b, NA_character_),
  basis = "reference", confidence = "medium",
  source = "cascade-cleared-verdicts.csv", note = cl$note)

t <- rbindlist(rows, fill = TRUE)
say("")
say("raw labels gathered: %d", nrow(t))

## ---- de-duplicate, preferring the strongest basis ---------------------------
BASIS_RANK <- c(web = 1L, reference = 2L, inference = 3L)
t[, rank := BASIS_RANK[basis]][is.na(rank), rank := 9L]
setorder(t, grant_id, rank)
dups <- t[, .N, by = grant_id][N > 1L]
if (nrow(dups)) {
  say("grants labelled by more than one source: %d", nrow(dups))
  con <- merge(t, dups[, .(grant_id)], by = "grant_id")[
           , .(n_verdict = uniqueN(verdict),
               n_ein = uniqueN(correct_ein[!is.na(correct_ein)])), by = grant_id]
  say("  of those, CONFLICTING verdicts: %d | conflicting EINs: %d",
      sum(con$n_verdict > 1L), sum(con$n_ein > 1L))
}
t <- t[!duplicated(grant_id)]
t[, rank := NULL]

## ---- attach the stable key and the population ------------------------------
t <- merge(t, key, by = "grant_id", all.x = TRUE)
miss <- t[is.na(truth_id)]
if (nrow(miss)) say("WARNING: %d labels do not join the population -- dropped", nrow(miss))
t <- t[!is.na(truth_id)]
t[, population := POP]
setcolorder(t, c("truth_id", "grant_id", "population", "object_id", "recip_name",
                 "verdict", "correct_ein", "wrong_ein", "basis", "confidence",
                 "source", "note"))

hr(); say("PF-TRUTH"); hr()
print(t[, .N, by = verdict][order(-N)], row.names = FALSE)
say("")
say("  rows with a CORRECT ein (scoreable for recall) : %d", sum(!is.na(t$correct_ein)))
say("  rows with a WRONG ein   (negative constraint)  : %d", sum(!is.na(t$wrong_ein)))
say("  rows asserting NO org exists                   : %d",
    sum(grepl("^NO_ORG", t$verdict)))
say("  unresolved (carried for completeness)          : %d", sum(t$verdict == "UNRESOLVED"))
say("")
print(t[, .N, by = .(basis, confidence)][order(basis)], row.names = FALSE)

fwrite(t, file.path(PF, "data-dev", "PF-TRUTH.csv"))
hr()
say("wrote data-dev/PF-TRUTH.csv  (%d rows, population %s)", nrow(t), POP)
say("")
say("COVERAGE WARNING, by construction: every row here was drawn from a cell the")
say("then-current pipeline produced -- the MAYBE tier, the cleared cell, the NO")
say("residual. None is a random sample. So this table can measure RECOVERY of")
say("known failures and it cannot measure PRECISION on the YES mass, which is")
say("3,051 of 4,842 identities. That needs a fresh stratified sample.")

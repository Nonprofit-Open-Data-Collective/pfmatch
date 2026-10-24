#!/usr/bin/env Rscript
# ============================================================================
# relabel-truth-v2.R -- carry PF-TRUTH onto the lifted v2 population.
#
# WHY NOT JUST RE-RUN build-truth.R. That script consolidates the verdict files
# and keys them on `grant_id`, which is POSITIONAL. The lift drops the rows
# deduplication established were superseded, so every grant_id after the first
# dropped row denotes a different grant in the v2 sample than it did in the v1
# one. Re-running the consolidation against the new population would reattach
# all 177 adjudications to the wrong grants -- silently, and with entirely
# plausible-looking output.
#
# So the labels are TRANSLATED instead, through the explicit crosswalk written
# by dev/lift-sample-to-v2.R, and the translation is checked on the recipient
# name: the same adjudication must still be sitting on the same payee.
#
# Three things change in the output:
#   truth_id    the old 16-hex content hash becomes OBJECTID|TABLE_ID, the
#               published row key. The hash was only ever a stand-in for a
#               column the v1 build was discarding.
#   grant_id    renumbered to the v2 position.
#   population  the v2 population fingerprint, which is what pf_evaluate()
#               gates on.
#
# A label whose grant left the sample is DROPPED and reported, never carried
# over onto a neighbouring row.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 78))

PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
sq <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

TRIN  <- Sys.getenv("PF_TRUTH_IN",  "PF-TRUTH.csv")
TROUT <- Sys.getenv("PF_TRUTH_OUT", "PF-TRUTH-V2.csv")
GPAT  <- "^efv2_1k_grants_[0-9]+\\.csv$"

hr(); say("relabel-truth-v2  %s", format(Sys.time())); hr()

tr <- fread(file.path(PF, "data-dev", TRIN), colClasses = "character")
xw <- fread(file.path(PF, "data-dev", "LIFT-CROSSWALK-V2.csv"), colClasses = "character")
say("truth in    %-22s %4d rows, population %s", TRIN, nrow(tr), tr$population[1])
say("crosswalk   %-22s %4d rows", "LIFT-CROSSWALK-V2.csv", nrow(xw))

g2  <- as.data.table(pf_read_grants(file.path(PF, "inputs"), pattern = GPAT))
POP <- pf_population_id(g2)
say("population  v2 %s  (%s rows)", POP, format(nrow(g2), big.mark = ","))

## ---- translate ---------------------------------------------------------------
m <- merge(tr, xw[, .(grant_id_v1, grant_id_v2, truth_id_v2 = truth_id,
                      object_id_xw = object_id, recip_xw = recip_v2)],
           by.x = "grant_id", by.y = "grant_id_v1", all.x = TRUE, sort = FALSE)

kept <- m[!is.na(grant_id_v2)]
gone <- m[is.na(grant_id_v2)]

hr(); say("TRANSLATION")
say("  labels in           %4d", nrow(tr))
say("  carried over        %4d", nrow(kept))
say("  grant left the sample %2d", nrow(gone))

## ---- check it landed on the same payee ---------------------------------------
bad_oid <- kept[sq(object_id) != sq(object_id_xw)]
if (nrow(bad_oid))
  stop(nrow(bad_oid), " label(s) translated onto a different FILING. The ",
       "crosswalk is wrong -- do not use this output.", call. = FALSE)
norm <- function(x) gsub("[^A-Z0-9]", "", toupper(sq(x)))
bad_nm <- kept[nzchar(norm(recip_name)) & nzchar(norm(recip_xw)) &
               norm(recip_name) != norm(recip_xw)]
say("  same filing         %4d of %d   OK", nrow(kept) - nrow(bad_oid), nrow(kept))
say("  same recipient name %4d of %d%s", nrow(kept) - nrow(bad_nm), nrow(kept),
    if (nrow(bad_nm)) "   <- INSPECT" else "   OK")
if (nrow(bad_nm)) {
  print(bad_nm[, .(grant_id, recip_name, recip_xw)], row.names = FALSE)
  stop("recipient name disagrees across the translation; the join is wrong.",
       call. = FALSE)
}

if (nrow(gone)) {
  say(""); say("  dropped labels (their grant was a superseded filing):")
  for (j in seq_len(nrow(gone)))
    say("    %-8s %-13s %s", gone$grant_id[j], gone$verdict[j],
        substr(gone$recip_name[j], 1, 44))
  fwrite(gone[, .(grant_id, object_id, recip_name, verdict, correct_ein, source)],
         file.path(PF, "dev", "RELABEL-DROPPED-LABELS.csv"))
  say("  -> dev/RELABEL-DROPPED-LABELS.csv")
}

## ---- write -------------------------------------------------------------------
out <- kept[, .(truth_id = truth_id_v2, grant_id = grant_id_v2, population = POP,
                object_id, recip_name, verdict, correct_ein, wrong_ein,
                basis, confidence, source, note)]
setorder(out, grant_id)
fwrite(out, file.path(PF, "data-dev", TROUT))

hr(); say("wrote data-dev/%s  (%d rows, population %s)", TROUT, nrow(out), POP)
print(out[, .N, by = verdict][order(-N)], row.names = FALSE)
say("")
say("  with a CORRECT ein (scoreable for recall) : %d",
    sum(nzchar(sq(out$correct_ein))))
say("  with a WRONG ein   (negative constraint)  : %d",
    sum(nzchar(sq(out$wrong_ein))))
say("  asserting NO org exists                   : %d", sum(grepl("^NO_ORG", out$verdict)))
hr()

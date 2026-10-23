#!/usr/bin/env Rscript
# ============================================================================
# Score the four comparator arms against ground truth.
#
# Until now each arm had only a clear rate, which cannot separate recall from
# false accepts -- the reason every recommendation this session ended "the moved
# cells need adjudicating". pf_evaluate() scores all four against
# data-dev/PF-TRUTH.csv in one pass.
#
# Read the FALSE CLEARS column first. Those are truth rows where adjudication
# established that no organisation exists at all -- an individual payee, a
# government body, a payee with no exemption of its own. Any of them tiered YES
# is an unambiguous false accept, and unlike precision on the YES mass it needs
# no random sample to measure.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(4L)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 92))

# The population and the truth table must be chosen together: pf_evaluate()
# refuses to score a run whose population id differs from the table's.
GPAT  <- Sys.getenv("PF_GRANTS_PAT", "^ef1k_grants_.*\\.csv$")
TRIN  <- Sys.getenv("PF_TRUTH_IN",   "PF-TRUTH.csv")
AROUT <- Sys.getenv("PF_ARMS_OUT",   "ARMS-VS-TRUTH.csv")

truth <- fread(file.path(PF, "data-dev", TRIN), colClasses = "character")
say("truth: %d rows, population %s  (%s)", nrow(truth), truth$population[1], TRIN)

grants <- pf_recover_name_from_street(
  pf_read_grants(file.path(PF, "inputs"), pattern = GPAT))
POP <- pf_population_id(grants)
say("run population: %s  (match: %s)", POP, identical(POP, truth$population[1]))

ref <- readRDS(file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds"))
PASSES <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))

arms <- list(
  A = list(jw = NULL, sp = NULL, tag = "Jaro, no substring [CURRENT]"),
  B = list(jw = 0.1,  sp = NULL, tag = "Jaro-Winkler"),
  C = list(jw = NULL, sp = 0.90, tag = "Jaro + substring"),
  D = list(jw = 0.1,  sp = 0.90, tag = "Jaro-Winkler + substring"))

out <- list()
for (nm in names(arms)) {
  a <- arms[[nm]]
  m <- pf_match_grants(grants, ref, config = np_config(jw_p = a$jw, substring_p = a$sp),
                       passes = PASSES, recover = TRUE, verbose = FALSE)
  ev <- pf_evaluate(m$result, truth = truth, population = POP)
  s  <- ev$summary
  r  <- as.data.table(m$result)
  out[[nm]] <- cbind(data.table(arm = nm, tag = a$tag,
                                clear = 100 * mean(r$tier == "YES"),
                                surf  = 100 * mean(r$tier %in% c("YES", "MAYBE"))), s)
  say("  %s done", nm)
}
z <- rbindlist(out)

hr(); say("FOUR ARMS AGAINST GROUND TRUTH"); hr()
say("%-28s %6s %6s | %14s %14s | %12s", "arm", "YES", "Y+M",
    "recall YES", "recall Y+M", "false clears")
for (i in seq_len(nrow(z)))
  say("%-28s %5.1f%% %5.1f%% | %5d/%-3d %4.0f%% | %5d/%-3d %4.0f%% | %4d/%-3d %4.1f%%",
      z$tag[i], z$clear[i], z$surf[i],
      z$right_and_yes[i], z$recall_n[i], 100 * z$recall_yes[i],
      z$right_surfaced[i], z$recall_n[i], 100 * z$recall_surfaced[i],
      z$no_org_cleared[i], z$no_org_n[i], 100 * z$false_clear_rate[i])
hr()
say("recall  = of truth rows with a known correct EIN, how many the arm gets right")
say("false clears = of truth rows where NO organisation exists, how many went YES")
say("")
say("'picked an EIN adjudication ruled out', per arm:")
for (i in seq_len(nrow(z))) say("  %-28s %d", z$tag[i], z$ruled_out_yes[i])

fwrite(z, file.path(PF, "data-dev", AROUT))
hr(); say("wrote data-dev/%s", AROUT)

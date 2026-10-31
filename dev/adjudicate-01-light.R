#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-01-light.R -- tier 1: the cheap adjudicator.
#
# One Haiku request per case, candidate packet only, no tools, no web. This is
# the arm that could actually be afforded at 1,044 cases -- and at 50,000 --
# so the experiment's real question is not whether it is good but whether its
# errors are predictable enough to route around.
#
# WHAT IT IS ALLOWED TO SEE, and why that is the whole point.
#
# Exactly dev/LLM-REVIEW-INSTRUCTIONS.md and exactly the packet. No search, no
# outside knowledge invited, no second opinion. That is the npmatch-shaped task:
# decide between the candidates in front of you, or answer NONE. Stage 02 does
# the same task with a frontier model and the open web, and the gap between
# them is the measurement.
#
# The instruction set is read from disk rather than restated here, so the two
# tiers cannot drift apart and so an improvement to the instructions is picked
# up by both. Only the output contract is appended, and only because the file
# specifies a table where this needs one JSON object.
#
# Structured output (output_config.format) rather than a tool: there is nothing
# to call, and it guarantees the first text block parses, which removes
# "unparseable response" as a failure mode that could be mistaken for a model
# refusing to answer.
#
# NO temperature IS SET ANYWHERE. As of API version 2026-10-21 sending
# temperature, top_p or top_k returns a 400 on every model. Determinism is not
# available by that route; repeat runs under PF_ADJ_TAG are how run-to-run
# variance gets measured instead.
#
# OUTPUT  data-dev/ADJ-EXP-LIGHT<tag>.rds   one row per case, plus usage/cost
#
# USAGE
#   Rscript dev/adjudicate-01-light.R
#   PF_ADJ_LIMIT=5  Rscript dev/adjudicate-01-light.R      # smoke test
#   PF_ADJ_TAG=-r2  Rscript dev/adjudicate-01-light.R      # a second run
#   PF_ADJ_WORKERS=8 PF_ADJ_EFFORT_LIGHT=low Rscript dev/adjudicate-01-light.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
source(file.path(PF, "dev", "adjudicate-lib.R"))
DD <- file.path(PF, "data-dev")

LIMIT   <- as.integer(Sys.getenv("PF_ADJ_LIMIT", "0"))
WORKERS <- as.integer(Sys.getenv("PF_ADJ_WORKERS", "6"))
EFFORT  <- Sys.getenv("PF_ADJ_EFFORT_LIGHT", "medium")
TAG     <- Sys.getenv("PF_ADJ_TAG", "")
MODEL   <- ADJ_MODEL_LIGHT
# PF_ADJ_SET picks which frozen packet to adjudicate: "exp" is the 100-case
# experiment, "cal" the ~200-case calibration set from dev/adjudicate-05-calib-packet.R.
# Outputs take the same prefix, so the two sets' verdicts never overwrite each
# other and a scoring run cannot silently mix them.
SET     <- tolower(Sys.getenv("PF_ADJ_SET", "exp"))
stopifnot(SET %in% c("exp", "cal"))
PFX     <- if (SET == "cal") "ADJ-CAL" else "ADJ-EXP"
OUT     <- file.path(DD, sprintf("%s-LIGHT%s.rds", PFX, TAG))

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")

hr(); say("ADJUDICATION EXPERIMENT  stage 1: light adjudicator"); hr()
say("model=%s  effort=%s  workers=%d%s", MODEL, EFFORT, WORKERS,
    if (LIMIT > 0) sprintf("  LIMIT=%d (smoke test)", LIMIT) else "")

pkf <- file.path(DD, sprintf("%s-PACKET.rds", PFX))
if (!file.exists(pkf))
  stop(sprintf("%s absent. Run %s first.", basename(pkf),
       if (SET == "cal") "dev/adjudicate-05-calib-packet.R" else "dev/adjudicate-00-packet.R"),
       call. = FALSE)
pk    <- as.data.table(readRDS(pkf))
cases <- as.data.table(readRDS(file.path(DD, sprintf("%s-CASES.rds", PFX))))
setorder(cases, batch_order)
if (LIMIT > 0) cases <- head(cases, LIMIT)
say("%d cases, %d candidate rows", nrow(cases), nrow(pk[grant_id %in% cases$grant_id]))

## ---- the prompt ------------------------------------------------------------
instr <- paste(readLines(file.path(PF, "dev", "LLM-REVIEW-INSTRUCTIONS.md"),
                         warn = FALSE), collapse = "\n")
# Appended, not substituted: the file's decision procedure, trap list and
# worked examples are the calibrated part and are left exactly as written.
contract <- paste(
  "",
  "---",
  "",
  "## Output format for this run",
  "",
  "You are given ONE case. Reply with a single JSON object and no other text.",
  "Use exactly these keys:",
  "",
  "  grant_id        the case id, copied",
  "  verdict         MATCH | NONE | AMBIGUOUS",
  "  ein             the chosen 9-digit EIN if MATCH or AMBIGUOUS, else \"\"",
  "  confidence      high | medium | low",
  "  evidence_class  QUOTE | NTEE | INFER | NONE",
  "  evidence        <= 25 words, the facts that decided it. If evidence_class",
  "                  is QUOTE this must contain the quoted sentence.",
  "  runner_up_ein   a seriously considered second candidate, else \"\"",
  "",
  "Judge only from the case as given. You have no web access on this pass, so",
  "do not assert anything you cannot support from the packet; where the packet",
  "does not decide it, that is what NONE and AMBIGUOUS are for.",
  sep = "\n")
system_prompt <- paste0(instr, contract)
say("system prompt: %d characters (cached across the batch)", nchar(system_prompt))

schema <- adj_verdict_schema(deep = FALSE)

## ---- build and fire --------------------------------------------------------
reqs <- vector("list", nrow(cases))
for (i in seq_len(nrow(cases))) {
  cr <- cases[i]
  cd <- pk[grant_id == cr$grant_id][order(rank)]
  reqs[[i]] <- adj_request(
    model      = MODEL,
    system     = adj_system_cached(system_prompt),
    user       = adj_render_case(cr, cd),
    max_tokens = 2048,
    effort     = EFFORT,
    schema     = schema)
}
say("\nfiring %d requests ...", length(reqs))
t0    <- proc.time()[["elapsed"]]
resps <- adj_perform(reqs, workers = WORKERS)
el    <- proc.time()[["elapsed"]] - t0
say("  %.1f s elapsed (%.2f s/case wall)", el, el / length(reqs))

## ---- collect ---------------------------------------------------------------
rows <- vector("list", length(resps))
use  <- matrix(0, nrow = length(resps), ncol = 5,
               dimnames = list(NULL, c("input", "output", "cache_read",
                                       "cache_write", "web_search")))
fails <- character(0)
for (i in seq_along(resps)) {
  gid <- cases$grant_id[i]
  r   <- adj_body(resps[[i]])
  if (!isTRUE(r$ok)) {
    fails <- c(fails, sprintf("%s: HTTP %s %s", gid, r$status, r$error))
    rows[[i]] <- cbind(adj_verdict_row(NULL, gid, deep = FALSE),
                       data.frame(api_ok = FALSE, stop_reason = NA_character_,
                                  stringsAsFactors = FALSE))
    next
  }
  b   <- r$body
  use[i, ] <- adj_usage(b)
  v   <- adj_parse_json(adj_text(b))
  row <- adj_verdict_row(v, gid, deep = FALSE)
  rows[[i]] <- cbind(row, data.frame(
    api_ok      = TRUE,
    stop_reason = as.character(b$stop_reason %||% NA),
    stringsAsFactors = FALSE))
}
out <- as.data.table(rbindlist(rows, fill = TRUE))
out[, `:=`(tier = "light", model = MODEL, effort = EFFORT,
           in_tokens = use[, "input"], out_tokens = use[, "output"],
           cache_read = use[, "cache_read"], cache_write = use[, "cache_write"])]
out <- merge(cases[, .(grant_id, stratum, batch_order)], out, by = "grant_id")
setorder(out, batch_order)

## ---- read-out --------------------------------------------------------------
hr()
if (length(fails)) {
  say("API FAILURES: %d of %d", length(fails), nrow(out))
  for (f in head(fails, 10)) say("  %s", f)
  if (length(fails) > 10) say("  ... and %d more", length(fails) - 10)
}
ok <- out[api_ok == TRUE]
say("\nverdicts returned: %d of %d", nrow(ok), nrow(out))
unparsed <- ok[is.na(verdict)]
if (nrow(unparsed)) say("UNPARSED despite a 200: %d", nrow(unparsed))
print(table(verdict = ok$verdict, useNA = "ifany"))
say("")
print(table(confidence = ok$confidence, evidence_class = ok$evidence_class))

# dev/LLM-REVIEW-INSTRUCTIONS.md's own sanity check, applied to the run rather
# than left for a reader to apply: a reviewer answering MATCH to almost
# everything has stopped doing the task. 29% NONE is the hand-adjudicated
# reference distribution.
share <- function(v) 100 * mean(ok$verdict == v, na.rm = TRUE)
say("\nMATCH %.1f%%  NONE %.1f%%  AMBIGUOUS %.1f%%   (hand-adjudicated: 55 / 29 / 16)",
    share("MATCH"), share("NONE"), share("AMBIGUOUS"))
if (share("MATCH") > 85) say("  WARNING: a MATCH share this high means the NONE option is not being used.")

# A QUOTE verdict with no quotable string is the one output the instructions
# say to reject outright, so it is counted here rather than discovered later.
bad_q <- ok[evidence_class == "QUOTE" & (is.na(evidence) | nchar(evidence) < 15)]
if (nrow(bad_q)) say("\nQUOTE claimed with no quotable string: %d (instructions reject these)",
                     nrow(bad_q))

tin <- sum(out$in_tokens); tout <- sum(out$out_tokens)
cr  <- sum(out$cache_read); cw <- sum(out$cache_write)
cost <- adj_cost(MODEL, tin, tout, cr, cw)
say("\ntokens: %s in, %s out   cache: %s read, %s written",
    format(tin, big.mark = ","), format(tout, big.mark = ","),
    format(cr, big.mark = ","), format(cw, big.mark = ","))
say("cost: $%.4f over %d cases  ($%.6f/case)", cost, nrow(out), cost / nrow(out))
# The 1,044 projection is the experiment set's MAYBE tier. The calibration set
# is not a sample of that tier (see adjudicate-05-calib-packet.R, note 2), so
# projecting from it would be arithmetic on the wrong denominator.
if (SET == "exp")
  say("  projected for all 1,044 MAYBEs: $%.2f", cost / nrow(out) * 1044)
if (cr == 0 && nrow(out) > 1) {
  # Two different causes, and the distinction decides whether it is worth
  # acting on. With every request fired at once, none of them can read a cache
  # entry that a sibling has not finished writing -- that is a race, it costs
  # money on a 3-case smoke test and almost nothing on 100. A prefix under the
  # model's minimum cacheable length never caches at all. Writes tell them
  # apart: a write happened means the prefix IS cacheable.
  say("  note: 0 cache reads, %s written -- %s",
      format(cw, big.mark = ","),
      if (cw > 0) "prefix is cacheable; the batch fired before the first write landed"
      else "prefix is under this model's minimum cacheable length")
}

saveRDS(out, OUT)
say("\nwrote %s", OUT)
say("next: Rscript dev/adjudicate-02-deep.R")
hr()

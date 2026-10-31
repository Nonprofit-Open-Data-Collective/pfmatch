#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-02-deep.R -- tier 2: the reference standard.
#
# claude-opus-5-5 at high effort with adaptive thinking and the server-side
# web_search tool, on the same 100 cases and the same packet text as stage 01.
# This arm is not meant to be affordable. It is meant to be RIGHT, so that the
# cheap arm has something to be measured against.
#
# WHAT MAKES IT A REFERENCE STANDARD, AND WHAT STOPS IT BEING ONE.
#
# dev/ADJUDICATION-PLAN.md section 7 step 7 is explicit about why this pass has
# to exist: "candidate-only review survived independent verification on only
# ~5 of 12 checks; no accuracy claim should be made without this step." A
# reviewer confined to the packet can only decide which of five BMF rows looks
# most like the filed name. It cannot find out whether the organisation the
# foundation actually paid is in the packet at all -- and 29% of the time it is
# not. That question is answered outside the packet or not at all, which is
# what the search tool is for.
#
# It is still a model, so it is NOT ground truth. Stage 03 therefore scores
# BOTH tiers against the 32 hand-adjudicated cases, and only reports the deep
# arm as a standard for the other 68 to the extent it earns that on the 32.
# If the deep arm is itself poor on the calibration stratum, its agreement
# with the light arm says nothing about either, and the scoring stage says so.
#
# THE SEARCH IS THE POINT, SO IT IS INSTRUCTED AND RECORDED.
#
# The addendum below directs the model at the question the packet cannot
# answer -- who is this organisation, independently of the five rows offered --
# and makes it record what it found in `search_findings` plus a
# CONFIRMED/CONTRADICTED/INCONCLUSIVE/NOT_SEARCHED flag. That flag is the
# column stage 03 slices reliability by: light-vs-deep agreement on cases the
# deep arm confirmed externally means something different from agreement where
# it never searched.
#
# TWO API DETAILS THAT ARE NOT OPTIONAL HERE.
#
# 1. Forced tool use is rejected on claude-opus-5-5 -- tool_choice "any" and
#    "tool" both return 400. The verdict therefore comes back through a
#    strict-schema `submit_verdict` tool under tool_choice auto plus an
#    explicit instruction, and the code checks the call was actually made.
#    output_config.format is NOT used on this arm: web search results carry
#    citations and structured outputs 400 on citations.
# 2. A long search turn can come back with stop_reason "pause_turn" instead of
#    a finished answer. That is not an error and must not be read as a refusal:
#    the response content is appended and the request re-sent. The loop below
#    does that up to PF_ADJ_ROUNDS times.
#
# OUTPUT  data-dev/ADJ-EXP-DEEP<tag>.rds
#
# USAGE
#   Rscript dev/adjudicate-02-deep.R
#   PF_ADJ_LIMIT=3 Rscript dev/adjudicate-02-deep.R        # smoke test
#   PF_ADJ_EFFORT_DEEP=xhigh PF_ADJ_MAXSEARCH=8 Rscript dev/adjudicate-02-deep.R
#   PF_ADJ_NOSEARCH=1 Rscript dev/adjudicate-02-deep.R     # ablation: no web
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
source(file.path(PF, "dev", "adjudicate-lib.R"))
DD <- file.path(PF, "data-dev")

LIMIT     <- as.integer(Sys.getenv("PF_ADJ_LIMIT", "0"))
WORKERS   <- as.integer(Sys.getenv("PF_ADJ_WORKERS", "4"))
EFFORT    <- Sys.getenv("PF_ADJ_EFFORT_DEEP", "high")
# 6 was the first value tried and it was demonstrably binding: on G002887 the
# model used all six and reported "I couldn't get the sort names for the five
# candidate EINs because I hit the search limit" -- it knew what it still needed
# and was stopped from getting it. A cap that truncates the investigation makes
# the deep arm look indecisive for a reason that has nothing to do with the
# case, so it is raised. It is still a cap: searches are billed per use.
MAXSEARCH <- as.integer(Sys.getenv("PF_ADJ_MAXSEARCH", "12"))
ROUNDS    <- as.integer(Sys.getenv("PF_ADJ_ROUNDS", "4"))
NOSEARCH  <- nzchar(Sys.getenv("PF_ADJ_NOSEARCH"))
TAG       <- Sys.getenv("PF_ADJ_TAG", "")
MODEL     <- ADJ_MODEL_DEEP
OUT       <- file.path(DD, sprintf("ADJ-EXP-DEEP%s.rds", TAG))

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")

hr(); say("ADJUDICATION EXPERIMENT  stage 2: deep research adjudicator"); hr()
say("model=%s  effort=%s  search=%s  workers=%d%s", MODEL, EFFORT,
    if (NOSEARCH) "OFF (ablation)" else sprintf("max %d uses", MAXSEARCH), WORKERS,
    if (LIMIT > 0) sprintf("  LIMIT=%d (smoke test)", LIMIT) else "")

pkf <- file.path(DD, "ADJ-EXP-PACKET.rds")
if (!file.exists(pkf))
  stop("data-dev/ADJ-EXP-PACKET.rds absent. Run dev/adjudicate-00-packet.R first.",
       call. = FALSE)
pk    <- as.data.table(readRDS(pkf))
cases <- as.data.table(readRDS(file.path(DD, "ADJ-EXP-CASES.rds")))
setorder(cases, batch_order)
if (LIMIT > 0) cases <- head(cases, LIMIT)
say("%d cases", nrow(cases))

## ---- the prompt: stage 01's, plus the search mandate -----------------------
instr <- paste(readLines(file.path(PF, "dev", "LLM-REVIEW-INSTRUCTIONS.md"),
                         warn = FALSE), collapse = "\n")
addendum <- paste(
  "",
  "---",
  "",
  "## This pass has web search, and is expected to use it",
  "",
  "You are the verification pass. A previous reviewer saw this same packet with",
  "no outside information; your job is not to repeat that but to establish what",
  "is actually true and then decide.",
  "",
  "Search before you conclude, on essentially every case. What to look for:",
  "",
  "1. **Who the filed recipient is.** Search the name as filed together with the",
  "   city or state. You are trying to find the organisation's own website, its",
  "   IRS exemption record, or a directory entry (ProPublica Nonprofit Explorer,",
  "   GuideStar/Candid, Charity Navigator, a state registry).",
  "2. **Its EIN, from a source that states it.** This is the single most useful",
  "   fact you can bring back. An EIN found in a filing, a directory record or",
  "   an audited financial statement settles the case outright -- it either is",
  "   one of the candidates or it is not.",
  "3. **Whether a candidate is the same body or a related one.** This is where",
  "   the packet most often fails: a foundation arm, an auxiliary, a chapter, or",
  "   an unrelated organisation sharing a local token. Confirm the relationship",
  "   from a source, do not infer it from the name shape.",
  "4. **Whether the organisation existed under that name in the grant year.**",
  "   Mergers, renames and dissolutions explain a surprising number of these.",
  "",
  "Weigh what you find above the packet's own signals. `score` and `name_sim`",
  "are the output of the cascade that already failed to decide this case; they",
  "are not evidence about the world.",
  "",
  "A search that finds the organisation and shows its EIN is NOT among the",
  "candidates is a successful search and a confident `NONE`. Say so in",
  "`search_findings` and put the EIN you found there. That outcome is more",
  "valuable than a hedged MATCH, because it tells us the packet was the problem",
  "rather than the reviewer.",
  "",
  "If search returns nothing usable -- a generic name with no web presence, a",
  "defunct body -- set `search_confirmed` to INCONCLUSIVE and decide from the",
  "packet alone. Do not invent corroboration, and do not treat a plausible",
  "search result as confirmation of an EIN it does not actually state.",
  "",
  "## Output format for this run",
  "",
  "Do your searching, then call the `submit_verdict` tool exactly once. Put the",
  "verdict only in that call -- prose outside it is not read. The two extra",
  "fields:",
  "",
  "  ground_truth_name   the recipient's full legal name as your sources give",
  "                      it, or \"\" if search did not establish it",
  "  search_findings     what you found and where, <= 60 words. Include any EIN",
  "                      a source stated, whether or not it is a candidate.",
  "  search_confirmed    CONFIRMED      a source corroborated your verdict",
  "                      CONTRADICTED   sources point away from every candidate",
  "                      INCONCLUSIVE   searched, nothing decisive",
  "                      NOT_SEARCHED   no search was run for this case",
  sep = "\n")
system_prompt <- paste0(instr, addendum)
say("system prompt: %d characters", nchar(system_prompt))

## ---- tools -----------------------------------------------------------------
# web_search_20260209 is the dynamic-filtering variant and is the right one for
# claude-opus-5-5. It runs code execution internally, which is why
# code_execution is deliberately NOT declared alongside it: a second execution
# environment confuses the model.
tools <- list()
if (!NOSEARCH)
  tools <- c(tools, list(list(type = "web_search_20260209", name = "web_search",
                              max_uses = MAXSEARCH)))
tools <- c(tools, list(list(
  name = "submit_verdict",
  description = paste("Record the final adjudication for this case. Call this",
                      "exactly once, after any searching is finished."),
  input_schema = adj_verdict_schema(deep = TRUE),
  strict = TRUE)))

## ---- fire, continuing any paused turn --------------------------------------
# Each case carries its own message list because a paused turn has to be
# resumed with its own history. Finished cases drop out of the loop.
convos <- lapply(seq_len(nrow(cases)), function(i) {
  cr <- cases[i]
  cd <- pk[grant_id == cr$grant_id][order(rank)]
  list(grant_id = cr$grant_id,
       messages = list(list(role = "user", content = adj_render_case(cr, cd))),
       done = FALSE, body = NULL, rounds = 0L,
       usage = c(input = 0, output = 0, cache_read = 0, cache_write = 0, web_search = 0),
       error = NA_character_)
})

t0 <- proc.time()[["elapsed"]]
for (round in seq_len(ROUNDS)) {
  pending <- which(!vapply(convos, function(x) x$done, logical(1)))
  if (!length(pending)) break
  say("\nround %d: %d request%s ...", round, length(pending),
      if (length(pending) == 1L) "" else "s")
  reqs <- lapply(pending, function(i) adj_request(
    model = MODEL, system = adj_system_cached(system_prompt),
    messages = convos[[i]]$messages,
    max_tokens = 8192, effort = EFFORT, tools = tools,
    tool_choice = list(type = "auto"), timeout = 1200))
  resps <- adj_perform(reqs, workers = WORKERS)
  paused <- 0L
  for (j in seq_along(pending)) {
    i <- pending[j]
    r <- adj_body(resps[[j]])
    convos[[i]]$rounds <- round
    if (!isTRUE(r$ok)) {
      convos[[i]]$done  <- TRUE
      convos[[i]]$error <- sprintf("HTTP %s: %s", r$status, r$error)
      next
    }
    b <- r$body
    convos[[i]]$usage <- convos[[i]]$usage + adj_usage(b)
    convos[[i]]$body  <- b
    if (identical(b$stop_reason, "pause_turn")) {
      # Not a failure. Hand the partial turn back verbatim and let it finish.
      convos[[i]]$messages <- c(convos[[i]]$messages,
                                list(list(role = "assistant", content = b$content)))
      paused <- paused + 1L
    } else {
      convos[[i]]$done <- TRUE
    }
  }
  say("  %d finished, %d paused mid-turn", length(pending) - paused, paused)
}
el <- proc.time()[["elapsed"]] - t0
say("\n%.1f s elapsed (%.1f s/case wall)", el, el / nrow(cases))

unfinished <- sum(!vapply(convos, function(x) x$done, logical(1)))
if (unfinished)
  say("WARNING: %d case%s still paused after %d rounds -- raise PF_ADJ_ROUNDS",
      unfinished, if (unfinished == 1L) "" else "s", ROUNDS)

## ---- collect ---------------------------------------------------------------
rows <- lapply(convos, function(cv) {
  base <- data.frame(api_ok = is.na(cv$error), api_error = cv$error,
                     rounds = cv$rounds, stop_reason = NA_character_,
                     tool_called = FALSE, stringsAsFactors = FALSE)
  if (!is.na(cv$error) || is.null(cv$body))
    return(cbind(adj_verdict_row(NULL, cv$grant_id, deep = TRUE), base))
  v <- adj_tool_input(cv$body, "submit_verdict")
  base$stop_reason <- as.character(cv$body$stop_reason %||% NA)
  base$tool_called <- !is.null(v)
  # A model that answered in prose instead of calling the tool has still done
  # the work; recover the object rather than throw the case away, and record
  # that it came in the wrong channel.
  if (is.null(v)) v <- adj_parse_json(adj_text(cv$body))
  cbind(adj_verdict_row(v, cv$grant_id, deep = TRUE), base)
})
out <- as.data.table(rbindlist(rows, fill = TRUE))
um  <- do.call(rbind, lapply(convos, function(x) x$usage))
out[, `:=`(tier = "deep", model = MODEL, effort = EFFORT,
           searches = um[, "web_search"],
           in_tokens = um[, "input"], out_tokens = um[, "output"],
           cache_read = um[, "cache_read"], cache_write = um[, "cache_write"])]
out <- merge(cases[, .(grant_id, stratum, batch_order)], out, by = "grant_id")
setorder(out, batch_order)

## ---- read-out --------------------------------------------------------------
hr()
bad <- out[api_ok == FALSE]
if (nrow(bad)) {
  say("API FAILURES: %d of %d", nrow(bad), nrow(out))
  for (k in seq_len(min(10L, nrow(bad)))) say("  %s: %s", bad$grant_id[k], bad$api_error[k])
}
ok <- out[api_ok == TRUE]
say("\nverdicts returned: %d of %d  (tool call used on %d)",
    sum(!is.na(ok$verdict)), nrow(out), sum(ok$tool_called))
print(table(verdict = ok$verdict, useNA = "ifany"))
say("")
print(table(search_confirmed = ok$search_confirmed, useNA = "ifany"))
say("")
print(table(confidence = ok$confidence, evidence_class = ok$evidence_class))

say("\nsearches: %d total, %.1f/case, %d cases with none",
    sum(out$searches), mean(out$searches), sum(out$searches == 0))
say("ground-truth name established on %d of %d cases",
    sum(nzchar(ok$ground_truth_name) & !is.na(ok$ground_truth_name)), nrow(ok))

tin <- sum(out$in_tokens); tout <- sum(out$out_tokens)
cost <- adj_cost(MODEL, tin, tout, sum(out$cache_read), sum(out$cache_write))
say("\ntokens: %s in, %s out   cache: %s read",
    format(tin, big.mark = ","), format(tout, big.mark = ","),
    format(sum(out$cache_read), big.mark = ","))
say("token cost: $%.3f over %d cases ($%.4f/case, $%.2f projected for 1,044)",
    cost, nrow(out), cost / nrow(out), cost / nrow(out) * 1044)
say("  PLUS %d web searches, billed per search and NOT in that figure.",
    sum(out$searches))

saveRDS(out, OUT)
say("\nwrote %s", OUT)
say("next: Rscript dev/adjudicate-03-score.R")
hr()

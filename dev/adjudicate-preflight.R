#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-preflight.R -- prove the credentials and both request shapes
# against the live API before spending anything on a real batch.
#
# Four checks, each one a real request on a trivial prompt, costing well under
# a cent in total. They exist because every one of them has a failure mode that
# is silent or misleading if it is first hit in the middle of a 100-case run:
#
#   1  credentials        a 401 reads like a network problem in a parallel batch
#   2  light shape        structured output -- a rejected schema 400s every case
#   3  deep shape         web_search + a strict tool on claude-opus-5-5, which
#                         is the request most likely to be wrong, since forced
#                         tool_choice is rejected there and the model has to
#                         choose to call submit_verdict on its own
#   4  concurrency        two requests through req_perform_parallel, because a
#                         pool misconfiguration only shows up above one request
#
# Check 3 is the one to watch. If the model answers without calling the tool,
# the deep stage recovers the JSON from prose, but a persistent failure to call
# it means the instruction needs strengthening -- not that the run is broken.
#
# USAGE  Rscript dev/adjudicate-preflight.R
# ============================================================================
PF <- Sys.getenv("PFMATCH_DIR", ".")
source(file.path(PF, "dev", "adjudicate-lib.R"))

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
ok_n <- 0L; fail_n <- 0L
report <- function(lab, ok, detail = "") {
  if (ok) ok_n <<- ok_n + 1L else fail_n <<- fail_n + 1L
  say("  [%s] %s%s", if (ok) "PASS" else "FAIL", lab,
      if (nzchar(detail)) paste0("\n         ", detail) else "")
}

hr(); say("ADJUDICATION PREFLIGHT"); hr()

## ---- 1. credentials --------------------------------------------------------
say("\n1. credentials")
cred <- tryCatch(adj_credential(), error = function(e) {
  say("  [FAIL] %s", conditionMessage(e)); NULL })
if (is.null(cred)) quit(save = "no", status = 1L)
say("  scheme: %s  (%d chars, %s header)", cred$scheme, nchar(cred$value),
    if (identical(cred$scheme, "oauth")) "Authorization: Bearer" else "x-api-key")

r <- adj_body(req_perform(adj_request(
  model = ADJ_MODEL_LIGHT, system = "Reply with one word.",
  user = "Say OK.", max_tokens = 16)))
report(sprintf("%s reachable and authorised", ADJ_MODEL_LIGHT), isTRUE(r$ok),
       if (!isTRUE(r$ok)) sprintf("HTTP %s: %s", r$status, r$error) else
         sprintf("replied %s", trimws(adj_text(r$body))))
if (!isTRUE(r$ok)) { hr(); say("Stopping: no usable credential."); quit(save = "no", status = 1L) }

## ---- 2. the light shape ----------------------------------------------------
say("\n2. light-arm request shape (structured output)")
r <- adj_body(req_perform(adj_request(
  model  = ADJ_MODEL_LIGHT,
  system = adj_system_cached(paste(
    "You adjudicate grant recipients against candidate EINs.",
    "Reply with a single JSON object and nothing else.")),
  user   = paste("### CASE G000000\nGRANT AS FILED\n  recip_name: HAMMER MUSEUM",
                 "\n  recip_city: LOS ANGELES\n  recip_state: CA\n\nCANDIDATE 1",
                 "\n  ein: 951644048\n  cand_name: ARMAND HAMMER MUSEUM OF ART",
                 "\n  cand_city: LOS ANGELES\n  cand_state: CA"),
  max_tokens = 512, effort = "low", schema = adj_verdict_schema(deep = FALSE))))
if (!isTRUE(r$ok)) {
  report("structured output accepted", FALSE, sprintf("HTTP %s: %s", r$status, r$error))
} else {
  v <- adj_parse_json(adj_text(r$body))
  report("structured output accepted and parsed", !is.null(v))
  if (!is.null(v)) {
    row <- adj_verdict_row(v, "G000000", deep = FALSE)
    report("every light verdict field present",
           all(adj_verdict_cols(FALSE) %in% names(row)))
    say("         verdict=%s ein=%s conf=%s class=%s",
        row$verdict, row$ein, row$confidence, row$evidence_class)
    u <- adj_usage(r$body)
    say("         tokens %.0f in / %.0f out, cache written %.0f",
        u[["input"]], u[["output"]], u[["cache_write"]])
  }
}

## ---- 3. the deep shape -----------------------------------------------------
say("\n3. deep-arm request shape (web_search + strict tool on %s)", ADJ_MODEL_DEEP)
tools <- list(
  # 4, not 2: the point is to see search fire, and a cap low enough to truncate
  # the first look makes that ambiguous. Still well under stage 02's 12.
  list(type = "web_search_20260209", name = "web_search", max_uses = 4L),
  list(name = "submit_verdict",
       description = "Record the final adjudication. Call exactly once.",
       input_schema = adj_verdict_schema(deep = TRUE), strict = TRUE))
# The first version of this check used a two-line stub prompt at effort "low"
# and reported "web search actually ran: FAIL" -- the model answered from its
# own knowledge, which on the Hammer Museum is a perfectly sensible thing to
# do. That was a false alarm about the harness: with the real instruction file
# and effort "high", stage 02 searches 5+ times per case. A preflight whose
# configuration differs from the run it is clearing cannot clear it, so this
# now uses the same prompt and the same effort as stage 02, on a case chosen to
# be genuinely ambiguous rather than famous.
instr <- paste(readLines(file.path(PF, "dev", "LLM-REVIEW-INSTRUCTIONS.md"),
                         warn = FALSE), collapse = "\n")
deep_sys <- paste0(instr, "\n\n---\n\n## This pass has web search\n\n",
  "Search before you conclude, on essentially every case: find the recipient's\n",
  "own site, its IRS exemption record, or a directory entry, and its EIN from a\n",
  "source that states it. Then call submit_verdict exactly once, setting\n",
  "search_confirmed to CONFIRMED / CONTRADICTED / INCONCLUSIVE / NOT_SEARCHED.")
r <- adj_body(req_perform(adj_request(
  model  = ADJ_MODEL_DEEP,
  system = adj_system_cached(deep_sys),
  user   = paste("### CASE G000000\nGRANT AS FILED\n",
                 "  recip_name: UPLAND PTA\n  recip_city: UPLAND\n",
                 "  recip_state: CA\n  recip_zip5: 91784\n",
                 "  grant_purpose: GENERAL SUPPORT\n\nCANDIDATE 1\n",
                 "  ein: 956206643\n  cand_name: PTA CALIFORNIA CONGRESS OF PARENTS\n",
                 "  cand_city: UPLAND\n  cand_state: CA\n\nCANDIDATE 2\n",
                 "  ein: 330413984\n  cand_name: PTA CALIFORNIA CONGRESS OF PARENTS\n",
                 "  cand_city: UPLAND\n  cand_state: CA"),
  max_tokens = 8192, effort = "high", tools = tools,
  tool_choice = list(type = "auto"), timeout = 900)))
if (!isTRUE(r$ok)) {
  report("web_search + strict tool accepted", FALSE,
         sprintf("HTTP %s: %s", r$status, r$error))
} else {
  b <- r$body
  report("web_search + strict tool accepted", TRUE,
         sprintf("stop_reason=%s", b$stop_reason))
  types <- unique(vapply(b$content, function(x) x$type %||% "?", character(1)))
  say("         content blocks: %s", paste(types, collapse = ", "))
  u <- adj_usage(b)
  report("web search actually ran", u[["web_search"]] > 0,
         sprintf("%.0f search request(s)", u[["web_search"]]))
  v <- adj_tool_input(b, "submit_verdict")
  report("submit_verdict was called", !is.null(v),
         if (is.null(v)) "model answered in prose; stage 02 recovers this, but see the note above" else "")
  if (!is.null(v)) {
    row <- adj_verdict_row(v, "G000000", deep = TRUE)
    report("every deep verdict field present",
           all(adj_verdict_cols(TRUE) %in% names(row)))
    say("         verdict=%s ein=%s search_confirmed=%s", row$verdict, row$ein,
        row$search_confirmed)
    say("         ground_truth_name=%s", substr(row$ground_truth_name, 1, 60))
    say("         findings=%s", substr(row$search_findings, 1, 100))
  }
  # pause_turn is normal on a long search turn and stage 02 continues it. Noted
  # here so a preflight that shows it is not read as a failure.
  if (identical(b$stop_reason, "pause_turn"))
    say("         note: paused mid-turn. Expected on search; stage 02 resumes it.")
}

## ---- 4. concurrency --------------------------------------------------------
say("\n4. parallel transport")
reqs <- replicate(2L, adj_request(
  model = ADJ_MODEL_LIGHT, system = "Reply with one word.",
  user = "Say OK.", max_tokens = 16), simplify = FALSE)
rs <- adj_perform(reqs, workers = 2L, progress = FALSE)
got <- vapply(rs, function(x) isTRUE(adj_body(x)$ok), logical(1))
report("2 concurrent requests both returned", all(got),
       sprintf("%d of 2", sum(got)))

hr()
say("%d passed, %d failed", ok_n, fail_n)
if (fail_n == 0L) {
  say("\nShapes are good. Smoke-test the real packet next, which costs cents:")
  say("  PF_ADJ_LIMIT=3 Rscript dev/adjudicate-01-light.R")
  say("  PF_ADJ_LIMIT=2 Rscript dev/adjudicate-02-deep.R")
} else {
  say("\nFix the failures above before running a batch: the same request shape")
  say("would fail on all 100 cases and the cost would be spent regardless.")
}
hr()
quit(save = "no", status = if (fail_n == 0L) 0L else 1L)

#!/usr/bin/env Rscript
# ============================================================================
# label-shard.R -- run a model as a TRUTH LABELER over one dealt shard.
#
# dev/TRUTH-LABELING-PROTOCOL.md is the job description; this is the harness
# that does it. Until now no script in this repository ran a model as a truth
# labeler: dev/adjudicate-01-light.R and -02-deep.R run the ARMS, which is a
# different job on the same cases, and dev/deal-round-stage1.R only deals the
# files out. So the three things below are deliberate departures from the arm
# scripts rather than oversights, and each one is the protocol's doing.
#
# 1. NO PACKET. adj_render_case() renders the five-candidate packet, and
#    protocol section 1 is explicit that a labeler who decides from the packet
#    "is the deep arm under another name", which makes grading the deep arm
#    against it a measure of agreement between two instances of one procedure.
#    So the case text here is the identity AS FILED plus the cascade's single
#    pick -- the pick only because section 4 asks for `wrong_ein` when an EIN
#    is ruled out, "especially when it is the cascade's pick", which a labeler
#    cannot supply without being told what it was. Everything else the labeler
#    needs it has to go and find.
#
# 2. A DIFFERENT VERDICT SET. The arms answer pf_verdict_levels() --
#    MATCH / NONE / AMBIGUOUS, "what did a reviewer conclude from these five
#    candidates". A labeler answers pf_truth_levels() -- "what is the right
#    answer for this grant" -- so ORG_FOUND, the three NO_ORG reasons, and
#    UNRESOLVED. adj_verdict_schema() is the wrong schema here and is not used.
#
# 3. SEARCH IS NOT OPTIONAL. The deep arm treats web search as a tier; for a
#    labeler it is the job. A row that comes back basis = "web" with no
#    source_url is refused by pf_read_truth(), so it is refused here too,
#    before 92 of them reach a file.
#
# WHAT THE HARNESS FILLS AND WHAT THE MODEL FILLS. The model supplies the
# judgment: verdict, correct_ein, wrong_ein, basis, confidence, source_url,
# note. The harness supplies the provenance: grant_id, population, shard and
# labeler.
#
# truth_id IS LEFT BLANK, AND THAT IS NOT A GAP TO CLOSE LATER. The schema
# comment calls it "OBJECTID | TABLE_ID -- the published ef2 row key", which is
# a GRANT-ROW key: TRI-V2-MATCH's `grants` carries both columns over 596,539
# rows, against 91,008 identities in `status`. This round labels IDENTITIES --
# one row per PFI- id, covering every grant that identity received -- so there
# is no single OBJECTID|TABLE_ID for a label, and inventing one by picking a
# representative grant row would make a per-identity judgment look like a
# per-row one.
#
# Nothing is lost by it at this grain. truth_id exists because grant_id used to
# be positional and so could not survive a rebuild; since 2026-11-03 these ids
# are content-derived from the recipient's own normalized name and address
# (pf_identity_id()), which is the stability truth_id was there to supply. The
# dealt templates ship truth_id blank for the same reason, and pf_read_truth()
# keys on grant_id + population.
#
# OUTPUT  data-dev/round-stage1-labelled/shard-NN-truth-<labeler>.csv
#
# It does NOT write into data-dev/round-stage1/shard-NN-truth.csv. Those are
# the dealt templates; pf_write_shards() refuses to overwrite a part-written
# one for the same reason, and a shadow run must not be able to land on top of
# a real labeler's work by a mistyped shard number.
#
# USAGE
#   PF_LABEL_SHARD=1 PF_ADJ_LIMIT=3 Rscript dev/label-shard.R   # smoke test
#   PF_LABEL_SHARD=1 Rscript dev/label-shard.R                  # the roster model
#   PF_LABEL_SHARD=1 PF_LABEL_MODEL=claude-haiku-5-5 \
#     PF_LABEL_LABELER=claude-haiku-5-5/shadow-01 Rscript dev/label-shard.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
source(file.path(PF, "dev", "adjudicate-lib.R"))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
DD <- file.path(PF, "data-dev")

SHARD   <- as.integer(Sys.getenv("PF_LABEL_SHARD", "0"))
MODEL   <- Sys.getenv("PF_LABEL_MODEL", "claude-fable-5-1")
LABELER <- Sys.getenv("PF_LABEL_LABELER", "")
LIMIT   <- as.integer(Sys.getenv("PF_ADJ_LIMIT", "0"))
WORKERS <- as.integer(Sys.getenv("PF_ADJ_WORKERS", "4"))
EFFORT  <- Sys.getenv("PF_LABEL_EFFORT", "high")
MAXSEARCH <- as.integer(Sys.getenv("PF_ADJ_MAXSEARCH", "12"))
ROUNDS  <- as.integer(Sys.getenv("PF_ADJ_ROUNDS", "4"))
DIR     <- file.path(DD, "round-stage1")
KEY     <- file.path(DD, "round-stage1-key", "SHARD-KEY.csv")
OUTDIR  <- file.path(DD, "round-stage1-labelled")
RUN     <- file.path(DD, "TRI-V2-MATCH.rds")
IDCACHE <- file.path(DD, "ADJ-ROUND-STAGE1-TRUTHIDS.rds")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")

if (is.na(SHARD) || SHARD < 1L)
  stop("set PF_LABEL_SHARD to the shard to label.", call. = FALSE)

hr(); say("TRUTH LABELER  shard %02d", SHARD); hr()

## ---- the cases, and who the key says labels them ---------------------------
cf <- file.path(DIR, sprintf("shard-%02d-cases.csv", SHARD))
if (!file.exists(cf))
  stop(sprintf("%s does not exist. Deal the round first (dev/deal-round-stage1.R).",
               cf), call. = FALSE)
cases <- as.data.table(utils::read.csv(cf, colClasses = "character"))
key   <- as.data.table(utils::read.csv(KEY, colClasses = "character"))
# The population is on the TEMPLATE, not the key: pf_write_shards() pre-fills
# it there because it is what the labeler must not change, and SHARD-KEY.csv
# carries only the assignment. Read it from the template or not at all -- a
# label dealt without a fingerprint cannot be re-attached to any grant file.
tpl <- utils::read.csv(file.path(DIR, sprintf("shard-%02d-truth.csv", SHARD)),
                       colClasses = "character")
pop <- unique(tpl$population[nzchar(tpl$population)])
if (length(pop) != 1L)
  stop(sprintf("the shard-%02d template carries %d populations, not one.",
               SHARD, length(pop)), call. = FALSE)
ksh   <- key[as.integer(shard) == SHARD]
if (!nrow(ksh))
  stop(sprintf("the key deals no shard %d.", SHARD), call. = FALSE)

# The roster is the default labeler, so a run that forgets to name one is still
# attributable. An explicit PF_LABEL_LABELER overrides it, which is what a
# shadow run does -- and pf_read_truth() will then refuse the file against the
# key, correctly, because the key did not deal this shard to that name. A
# shadow run is scored directly rather than read back as part of the round.
roster <- unique(ksh$labeler)
roster <- roster[nzchar(roster)]
if (!nzchar(LABELER)) {
  if (!length(roster))
    stop(paste0("the key names no labeler for this shard and PF_LABEL_LABELER\n",
                "  is unset, so this run would produce rows nobody can attribute."),
         call. = FALSE)
  LABELER <- roster[1L]
}
shadow <- !identical(LABELER, if (length(roster)) roster[1L] else "")

if (LIMIT > 0) cases <- head(cases, LIMIT)
say("model=%s  effort=%s  search=max %d  workers=%d%s", MODEL, EFFORT,
    MAXSEARCH, WORKERS,
    if (LIMIT > 0) sprintf("  LIMIT=%d (smoke test)", LIMIT) else "")
say("labeler=%s%s", LABELER,
    if (shadow) "   <- SHADOW: not the key's roster for this shard" else "")
say("%d cases, population %s", nrow(cases), pop[1L])

## ---- truth_id: provenance, looked up rather than asked for -----------------
# OBJECTID | TABLE_ID is the published ef2 row key and the only stable handle
# on a grant row; grant_id is positional within a population. The run that the
# draw came from is 651 MB, so the map is built once and cached.
truth_ids <- NULL
say("truth_id: left blank, deliberately -- see the note above.")

## ---- the prompt: the review instructions, then the protocol ----------------
# Not a new prompt. TRUTH-LABELING-PROTOCOL.md says of LLM-REVIEW-INSTRUCTIONS
# "Read that file first", and declares itself an appendix to it -- so the two
# are concatenated in that order and neither is reworded here. adjudicate-lib's
# header warns against forking a prompt per tier because a wording difference
# confounds every disagreement the arms produce; the same applies across
# labelers, and more sharply, since the overlap is read as agreement.
instr <- paste(readLines(file.path(PF, "dev", "LLM-REVIEW-INSTRUCTIONS.md"),
                         warn = FALSE), collapse = "\n")
proto <- paste(readLines(file.path(PF, "dev", "TRUTH-LABELING-PROTOCOL.md"),
                         warn = FALSE), collapse = "\n")
system_prompt <- paste0(instr, "\n\n---\n\n", proto, "\n\n---\n\n", paste(
  "## How to return your answer",
  "",
  "Call `submit_truth` exactly once per case, after you have finished",
  "searching. Do not answer in prose.",
  "",
  "`correct_ein` is nine digits, no hyphen, and is required when the verdict is",
  "ORG_FOUND. Leave it an empty string otherwise. `wrong_ein` is an EIN you",
  "ruled OUT -- give it whenever you ruled one out, especially the pick shown",
  "to you. `source_url` is required when `basis` is \"web\" and must be a page",
  "you actually opened.",
  sep = "\n"))
say("system prompt: %s characters", format(nchar(system_prompt), big.mark = ","))

## ---- the case text: identity as filed, plus the pick -----------------------
render_case <- function(r) {
  paste(
    "# Case", r$grant_id,
    "",
    "## The recipient, exactly as the foundation filed it",
    "",
    adj_fld("name",  r$recip_name),
    adj_fld("city",  r$recip_city),
    adj_fld("state", r$recip_state),
    adj_fld("zip",   r$recip_zip5),
    adj_fld("grants in this population", r$n_grants),
    adj_fld("total dollars", r$dollars),
    adj_fld("purpose text present", r$purpose_band),
    "",
    "## What the matching cascade picked, which you are NOT bound by",
    "",
    "Shown only so that you can rule it out explicitly if it is wrong.",
    "It is one BMF row chosen by string similarity, not a candidate list,",
    "and it may well be the wrong organisation.",
    "",
    adj_fld("pass",  r$cascade_pass),
    adj_fld("EIN",   r$cascade_ein),
    adj_fld("BMF name",  r$cascade_name),
    adj_fld("BMF city",  r$cascade_city),
    adj_fld("BMF state", r$cascade_state),
    adj_fld("score", r$cascade_score),
    adj_fld("margin over the runner-up", r$cascade_margin),
    "",
    "## Your task",
    "",
    "Establish who actually received this grant, independently. Search.",
    "Then call submit_truth.",
    sep = "\n")
}

## ---- the tool --------------------------------------------------------------
lv <- pf_truth_levels()
truth_schema <- list(
  type = "object",
  properties = list(
    verdict = list(type = "string", enum = adj_array(lv$verdict),
                   description = "the right answer for this grant"),
    correct_ein = list(type = "string",
                       description = "9 digits, no hyphen; required when ORG_FOUND, else \"\""),
    wrong_ein = list(type = "string",
                     description = "an EIN you ruled OUT, or \"\""),
    basis = list(type = "string", enum = adj_array(lv$basis),
                 description = "web requires source_url"),
    confidence = list(type = "string", enum = adj_array(lv$confidence)),
    source_url = list(type = "string",
                      description = "a page you opened; required when basis is web"),
    note = list(type = "string", description = "one sentence on what decided it")),
  required = adj_array(c("verdict", "correct_ein", "wrong_ein", "basis",
                         "confidence", "source_url", "note")),
  additionalProperties = FALSE)

tools <- list(
  list(type = "web_search_20260209", name = "web_search", max_uses = MAXSEARCH),
  list(name = "submit_truth",
       description = paste("Record the established truth for this case. Call",
                           "exactly once, after searching is finished."),
       input_schema = truth_schema, strict = TRUE))

## ---- fire, continuing any paused turn --------------------------------------
convos <- lapply(seq_len(nrow(cases)), function(i) {
  list(grant_id = cases$grant_id[i],
       messages = list(list(role = "user", content = render_case(cases[i]))),
       done = FALSE, body = NULL, rounds = 0L,
       usage = c(input = 0, output = 0, cache_read = 0, cache_write = 0,
                 web_search = 0),
       short = 0, long = 0, error = NA_character_)
})

# Haiku prices a request by the size of its WHOLE prompt, and a web-search
# turn crosses the 100K step routinely, so the tier is a property of each
# REQUEST and cannot be recovered from a run total. adj_cost_tiered() wants the
# two usage sets, so they are accumulated as the rounds go rather than
# reconstructed afterwards.
zero <- c(input = 0, output = 0, cache_read = 0, cache_write = 0)
usage_short <- zero; usage_long <- zero

t0 <- proc.time()[["elapsed"]]
for (round in seq_len(ROUNDS)) {
  pending <- which(!vapply(convos, function(x) x$done, logical(1)))
  if (!length(pending)) break
  say("\nround %d: %d request%s ...", round, length(pending),
      if (length(pending) == 1L) "" else "s")
  reqs <- lapply(pending, function(i) adj_request(
    model = MODEL, system = adj_system_cached(system_prompt),
    messages = convos[[i]]$messages, max_tokens = 8192, effort = EFFORT,
    tools = tools, tool_choice = list(type = "auto"), timeout = 1200))
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
    u <- adj_usage(b)
    convos[[i]]$usage <- convos[[i]]$usage + u
    whole <- u[["input"]] + u[["cache_read"]] + u[["cache_write"]]
    if (whole > ADJ_LONG_PROMPT) {
      convos[[i]]$long <- convos[[i]]$long + 1L
      usage_long  <- usage_long  + u[names(zero)]
    } else {
      convos[[i]]$short <- convos[[i]]$short + 1L
      usage_short <- usage_short + u[names(zero)]
    }
    convos[[i]]$body <- b
    if (identical(b$stop_reason, "pause_turn")) {
      convos[[i]]$messages <- c(convos[[i]]$messages,
                                list(list(role = "assistant", content = b$content)))
      paused <- paused + 1L
    } else convos[[i]]$done <- TRUE
  }
  say("  %d finished, %d paused mid-turn", length(pending) - paused, paused)
}
el <- proc.time()[["elapsed"]] - t0
say("\n%.1f s elapsed (%.1f s/case wall)", el, el / max(1L, nrow(cases)))

unfinished <- sum(!vapply(convos, function(x) x$done, logical(1)))
if (unfinished)
  say("WARNING: %d case%s still paused after %d rounds -- raise PF_ADJ_ROUNDS",
      unfinished, if (unfinished == 1L) "" else "s", ROUNDS)

## ---- collect into the shard schema -----------------------------------------
blank <- function() list(verdict = "", correct_ein = "", wrong_ein = "",
                         basis = "", confidence = "", source_url = "", note = "")
rows <- lapply(convos, function(cv) {
  v <- if (!is.na(cv$error) || is.null(cv$body)) NULL else
    adj_tool_input(cv$body, "submit_truth")
  # A model that answered in prose has still done the work; recover it and
  # record that it arrived in the wrong channel rather than discarding a case.
  called <- !is.null(v)
  if (is.null(v) && !is.null(cv$body)) v <- adj_parse_json(adj_text(cv$body))
  if (is.null(v)) v <- blank()
  g <- function(k) { z <- v[[k]]; if (is.null(z) || !length(z)) "" else
                     trimws(as.character(z)[1L]) }
  ti <- if (is.null(truth_ids)) "" else {
    h <- truth_ids$truth_id[match(cv$grant_id, truth_ids$grant_id)]
    if (is.na(h)) "" else h
  }
  data.frame(truth_id = ti, grant_id = cv$grant_id, population = pop[1L],
             verdict = g("verdict"), correct_ein = gsub("[^0-9]", "", g("correct_ein")),
             wrong_ein = gsub("[^0-9]", "", g("wrong_ein")), basis = g("basis"),
             confidence = g("confidence"), labeler = LABELER, shard = SHARD,
             source_url = g("source_url"), note = g("note"),
             api_ok = is.na(cv$error), api_error = cv$error,
             tool_called = called, rounds = cv$rounds,
             searches = cv$usage[["web_search"]],
             in_tokens = cv$usage[["input"]], out_tokens = cv$usage[["output"]],
             cache_read = cv$usage[["cache_read"]],
             cache_write = cv$usage[["cache_write"]],
             req_short = cv$short, req_long = cv$long,
             stringsAsFactors = FALSE)
})
out <- as.data.table(rbindlist(rows, fill = TRUE))

## ---- refuse what pf_read_truth() would refuse, here instead of later -------
bad_web <- out[basis == "web" & !nzchar(source_url), grant_id]
bad_ein <- out[verdict == "ORG_FOUND" & !grepl("^[0-9]{9}$", correct_ein), grant_id]
if (length(bad_web) || length(bad_ein)) {
  say("")
  if (length(bad_web))
    say("%d row(s) claim basis=web with no source_url: %s", length(bad_web),
        paste(head(bad_web, 5), collapse = ", "))
  if (length(bad_ein))
    say("%d ORG_FOUND row(s) carry no 9-digit EIN: %s", length(bad_ein),
        paste(head(bad_ein, 5), collapse = ", "))
  say("These are what pf_read_truth() refuses. Blanked to `missing` rather")
  say("than written as labels, so the file reads back as a partial shard.")
  out[grant_id %in% c(bad_web, bad_ein),
      `:=`(verdict = "", correct_ein = "", basis = "", confidence = "")]
}

## ---- read-out --------------------------------------------------------------
hr()
nbad <- sum(!out$api_ok)
if (nbad) {
  say("API FAILURES: %d of %d", nbad, nrow(out))
  for (k in which(!out$api_ok)[seq_len(min(5L, nbad))])
    say("  %s: %s", out$grant_id[k], out$api_error[k])
}
ok <- out[nzchar(verdict)]
say("verdicts returned: %d of %d  (tool call used on %d)",
    nrow(ok), nrow(out), sum(out$tool_called))
if (nrow(ok)) {
  say(""); print(table(verdict = ok$verdict))
  say(""); print(table(basis = ok$basis, confidence = ok$confidence))
  say("\nsource_url given on %d of %d rows", sum(nzchar(ok$source_url)), nrow(ok))
  say("wrong_ein recorded on %d", sum(nzchar(ok$wrong_ein)))
}
say("\nsearches: %d total, %.1f/case, %d case(s) with none",
    sum(out$searches), mean(out$searches), sum(out$searches == 0))

cost <- adj_cost_tiered(MODEL, as.list(usage_short), as.list(usage_long))
if (is.na(cost) || !is.finite(cost))
  cost <- adj_cost(MODEL, sum(out$in_tokens), sum(out$out_tokens),
                   sum(out$cache_read), sum(out$cache_write))
say("\ntokens: %s in, %s out   cache: %s read, %s WRITTEN",
    format(sum(out$in_tokens), big.mark = ","),
    format(sum(out$out_tokens), big.mark = ","),
    format(sum(out$cache_read), big.mark = ","),
    format(sum(out$cache_write), big.mark = ","))
say("requests: %d short-prompt, %d long-prompt (haiku prices by whole prompt)",
    sum(out$req_short), sum(out$req_long))
say("token cost: $%.4f over %d cases ($%.6f/case)", cost, nrow(out),
    cost / max(1L, nrow(out)))
say("  projected for all %d cases of this shard: $%.2f", nrow(ksh),
    cost / max(1L, nrow(out)) * nrow(ksh))
say("  PLUS %d web searches, billed per search and NOT in that figure.",
    sum(out$searches))

## ---- write -----------------------------------------------------------------
if (!dir.exists(OUTDIR)) dir.create(OUTDIR, recursive = TRUE)
slug <- gsub("[^A-Za-z0-9._-]+", "-", LABELER)
stem <- sprintf("shard-%02d-truth-%s%s", SHARD, slug,
                if (LIMIT > 0) sprintf("-limit%d", LIMIT) else "")
pc <- file.path(OUTDIR, paste0(stem, ".csv"))
pr <- file.path(OUTDIR, paste0(stem, ".rds"))
utils::write.csv(out[, pf_shard_schema(), with = FALSE], pc,
                 row.names = FALSE, na = "")
saveRDS(out, pr)
say("\nwrote %s", pc)
say("      %s   (with usage and api columns)", pr)

## ---- validate the way the round will ---------------------------------------
# The point of writing the shard schema is that pf_read_truth() accepts it, so
# the run says whether it does rather than leaving that to be discovered later.
say("")
# A FRAME, not the path. pf_read_truth() takes a directory of
# shard-NN-truth.csv files, a frame, or a list of frames -- a single file path
# is read as a one-column frame and refused for every missing column, which is
# a confusing way to be told you passed the wrong thing. The file this writes
# is deliberately not named shard-NN-truth.csv either, so that a directory
# scan of the dealt round never picks up a labeller's output or a shadow run.
v <- tryCatch(
  pf_read_truth(as.data.frame(out[, pf_shard_schema(), with = FALSE]),
                key = if (shadow) NULL else key, population = pop[1L],
                verbose = TRUE),
  error = function(e) { say("pf_read_truth() REFUSES this file:");
                        say("  %s", conditionMessage(e)); NULL })
if (!is.null(v)) say("pf_read_truth() accepts it.")
if (shadow)
  say("read without the key: a shadow labeler is not on the key's roster.")
hr()

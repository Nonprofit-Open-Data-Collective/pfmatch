#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-lib.R -- Anthropic Messages API client and the shared case
# renderer. Sourced by dev/adjudicate-01-light.R and dev/adjudicate-02-deep.R.
# Not a script: sourcing it runs nothing.
#
# WHY RAW HTTP. There is no official Anthropic SDK for R. ellmer is installed
# and would work for the light tier, but the deep tier needs the server-side
# web_search tool, adaptive thinking and an effort level on the same request,
# and going through httr2 keeps all three visible in one place rather than
# hoping an abstraction passes them through. jsonlite + httr2 is also what the
# rest of this repo already depends on.
#
# WHY THE RENDERER IS HERE AND NOT IN EITHER TIER. The experiment's second
# question -- how reliable is the cheap adjudicator -- is only answerable if
# the two tiers differ in model and tools and in NOTHING ELSE. If each tier
# formatted its own prompt, any disagreement would be confounded by wording.
# `adj_render_case()` is called by both, and the light tier's prompt is the
# deep tier's prompt minus the search instruction. Do not fork it.
#
# PRICES are the published per-MTok rates, recorded here so a cost line can be
# printed without a second lookup. Web search is billed per search on top of
# tokens and is NOT in this table: the run logs the search count instead, and
# the cost line says so rather than quietly understating.
# ============================================================================
suppressWarnings(suppressMessages(library(httr2)))
suppressWarnings(suppressMessages(library(jsonlite)))

ADJ_API      <- "https://api.anthropic.com/v1/messages"
ADJ_VERSION  <- "2026-10-21"
ADJ_MODEL_LIGHT <- Sys.getenv("PF_ADJ_MODEL_LIGHT", "claude-haiku-5-5")
ADJ_MODEL_DEEP  <- Sys.getenv("PF_ADJ_MODEL_DEEP",  "claude-opus-5-5")

# $ per million tokens. FOUR rates, not two: usage.input_tokens is reported
# EXCLUSIVE of cached tokens, so charging only input+output silently drops the
# cache traffic entirely. On the deep arm that was 4.08M cache-read tokens
# against 298K billed input -- the cache reads were 93% of the input volume and
# were costing nothing in the arithmetic. Any projection built on that figure
# understates by ~25%.
#
# `cr` for Opus 5.5, Sonnet 5.5 and Fable 5.1 is the published cache-read rate.
# For the others it is the standard 0.1x of input, and `cw` is the standard
# 1.25x; both are marked `approx` so a projection knows which numbers are
# published and which are conventional.
ADJ_PRICES <- list(
  "claude-haiku-5-5"  = c(in_ =  0.10, out =  0.50, cr = 0.010, cw =  0.125, approx = 1),
  "claude-sonnet-5-5" = c(in_ =  2.00, out = 10.00, cr = 0.200, cw =  2.500, approx = 0),
  "claude-opus-5-5"   = c(in_ =  4.00, out = 20.00, cr = 0.200, cw =  5.000, approx = 0),
  "claude-opus-5"     = c(in_ =  5.00, out = 25.00, cr = 0.500, cw =  6.250, approx = 1),
  "claude-fable-5-1"  = c(in_ = 10.00, out = 50.00, cr = 0.250, cw = 12.500, approx = 0))

#' Resolve the API key, surviving a launcher that mislocates HOME
#'
#' R reads `.Renviron` from `HOME` at startup, and `HOME` is not the same thing
#' in every shell on Windows. Launched from PowerShell, R resolves it to
#' `C:/Users/<user>/Documents` and picks the file up; launched from Git Bash it
#' resolves to the POSIX-style home and finds NO `.Renviron` at all -- not even
#' the keys that were already working. Measured, both ways, on this machine.
#'
#' That failure is indistinguishable from a missing key, and it cost an hour of
#' misdiagnosis once. So rather than trust startup, re-read the candidate files
#' explicitly with readRenviron() before giving up. readRenviron() is the
#' idiomatic way to do this and only sets variables the file names.
#' A value that is present but is obviously not a key is worse than an absent
#' one: it produces a 401 on all 100 cases and reads like an auth outage. The
#' placeholder this repo's setup note tells people to paste over is the case
#' that actually happened, so it is rejected by name.
.adj_key_ok <- function(k)
  nzchar(k) && !grepl("^(PASTE|REPLACE|YOUR|sk-ant-\\.\\.\\.|xxx)", k, ignore.case = TRUE)

adj_key <- function() {
  k <- Sys.getenv("ANTHROPIC_API_KEY")
  if (.adj_key_ok(k)) return(k)
  placeholder <- nzchar(k)          # something is set, but it is not a key
  for (p in unique(c(
        Sys.getenv("R_ENVIRON_USER"),
        file.path(Sys.getenv("HOME"), ".Renviron"),
        file.path(Sys.getenv("USERPROFILE"), "Documents", ".Renviron"),
        file.path(Sys.getenv("USERPROFILE"), ".Renviron"),
        path.expand("~/.Renviron")))) {
    if (nzchar(p) && file.exists(p)) {
      try(readRenviron(p), silent = TRUE)
      k <- Sys.getenv("ANTHROPIC_API_KEY")
      if (.adj_key_ok(k)) {
        message(sprintf("note: key read from %s (not picked up at startup)", p))
        return(k)
      }
      if (nzchar(k)) placeholder <- TRUE
    }
  }
  hint <- if (placeholder)
    "ANTHROPIC_API_KEY is set but is still a placeholder, not a key." else
    "ANTHROPIC_API_KEY is not set, and no .Renviron on the usual paths defines it."
  stop(paste0(hint, "\n",
    "  Two ways to fix it, either is fine:\n\n",
    "  (a) An API key. Add to the .Renviron that already holds OPENAI_API_KEY:\n",
    "        ANTHROPIC_API_KEY=sk-ant-...\n",
    "      An `export` in the calling shell does NOT reach Rscript.\n\n",
    "  (b) No API key at all -- sign in with the Anthropic CLI:\n",
    "        npm install -g @anthropic-ai/ant   (once)\n",
    "        ant auth login\n",
    "      These scripts then pick up that profile automatically. See\n",
    "      adj_credential() for how.\n\n",
    "  If a .Renviron does define the key and this still fires, the launcher\n",
    "  is resolving HOME elsewhere -- run with R_ENVIRON_USER set to the\n",
    "  file's full path, or use PowerShell rather than Git Bash."),
    call. = FALSE)
}

#' The credential, from an API key or from an `ant auth login` profile
#'
#' An unset ANTHROPIC_API_KEY does not mean there is no credential. The
#' Anthropic CLI stores an OAuth profile under ~/.config/anthropic/ that the
#' official SDKs read automatically -- but this is raw HTTP from R, so there is
#' no SDK to do it, and the two credential types go in DIFFERENT headers:
#'
#'   API key : x-api-key: sk-ant-...
#'   OAuth   : Authorization: Bearer <short-lived token>
#'             anthropic-beta: oauth-2025-04-20      <- required, easily missed
#'
#' Preferring the API key matches the SDKs' own resolution order. The OAuth
#' token is short-lived, so it is fetched per call rather than cached; `ant`
#' refreshes it, and a batch that outlives one token still works because every
#' request asks again.
#'
#' @return list(scheme = "api_key"|"oauth", value = <secret>)
adj_credential <- function() {
  k <- Sys.getenv("ANTHROPIC_API_KEY")
  if (.adj_key_ok(k)) return(list(scheme = "api_key", value = k))
  ant <- Sys.which("ant")
  if (nzchar(ant)) {
    tok <- tryCatch(
      suppressWarnings(system2(ant, c("auth", "print-credentials", "--access-token"),
                               stdout = TRUE, stderr = FALSE)),
      error = function(e) character(0))
    tok <- trimws(paste(tok, collapse = ""))
    # --access-token is mandatory: the bare form prints a JSON blob, not a
    # token, and sending that as a bearer value fails with a confusing 401.
    if (nzchar(tok) && !grepl("^[{\\[]", tok))
      return(list(scheme = "oauth", value = tok))
  }
  adj_key()        # raises the combined, actionable error
}

## ---- one request -----------------------------------------------------------
# Returns a request object rather than performing it, so a batch of 100 can go
# through req_perform_parallel() with one definition.
#
# `thinking` is omitted entirely for the deep model. On claude-opus-5-5 that is
# equivalent to {"type":"adaptive"} -- thinking is always on and cannot be
# switched off; both {"type":"disabled"} and a budget_tokens field return 400.
# Depth is controlled by output_config.effort, whose default on this model is
# "medium", so the deep tier sets it explicitly.
adj_request <- function(model, system, user = NULL, max_tokens = 4096,
                        effort = NULL, thinking = NULL, tools = NULL,
                        schema = NULL, betas = NULL, timeout = 900,
                        messages = NULL, tool_choice = NULL) {
  if (is.null(messages))
    messages <- list(list(role = "user", content = user))
  body <- list(model = model, max_tokens = max_tokens,
               system = system, messages = messages)
  if (!is.null(tool_choice)) body$tool_choice <- tool_choice
  if (!is.null(effort))   body$output_config <- list(effort = effort)
  if (!is.null(thinking)) body$thinking <- thinking
  if (!is.null(tools))    body$tools <- tools
  if (!is.null(schema)) {
    body$output_config <- c(body$output_config,
                            list(format = list(type = "json_schema", schema = schema)))
  }
  # Built as a JSON string, not handed to req_body_json(): auto_unbox would
  # collapse a one-element `required` or `tools` array into a scalar and the
  # API would reject the schema. I() marks every array that must stay an array.
  json <- jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", digits = NA)
  cred <- adj_credential()
  hdr <- if (identical(cred$scheme, "oauth"))
    list(Authorization = paste("Bearer", cred$value),
         `anthropic-beta` = "oauth-2025-04-20") else
    list(`x-api-key` = cred$value)
  hdr$`anthropic-version` <- ADJ_VERSION
  hdr$`content-type` <- "application/json"
  # Betas accumulate: an OAuth credential already needs one, so append rather
  # than overwrite, or the auth beta silently disappears.
  if (length(betas))
    hdr$`anthropic-beta` <- paste(c(hdr$`anthropic-beta`, betas), collapse = ",")
  req <- request(ADJ_API) |>
    req_headers(!!!hdr) |>
    req_body_raw(json, type = "application/json") |>
    req_timeout(timeout) |>
    # Inspect the body of a 4xx instead of throwing: a schema or parameter
    # mistake has to be readable, and in a parallel batch one bad request must
    # not discard the other 99.
    req_error(is_error = function(resp) FALSE) |>
    req_retry(max_tries = 5, retry_on_failure = TRUE,
              is_transient = function(resp)
                resp_status(resp) %in% c(408L, 409L, 429L, 500L, 502L, 503L, 504L))
  req
}

adj_array <- function(x) I(as.character(x))

# The system prompt is byte-identical across all 100 requests in a tier, which
# is exactly the shape prompt caching is for: one write, then 99 reads at a
# fraction of the input price. Returned as a block list because cache_control
# attaches to a content block, not to a bare string.
#
# Caching is a cost optimisation and nothing else -- it cannot change a verdict,
# because the cached bytes are the same bytes. If usage.cache_read_input_tokens
# comes back 0 across a whole run, the prefix is under the model's minimum
# cacheable length and the only loss is money; the run is still valid.
adj_system_cached <- function(text) {
  list(list(type = "text", text = text,
            cache_control = list(type = "ephemeral")))
}

## ---- perform, with the failures kept ---------------------------------------
# on_error = "continue" so a batch returns what succeeded alongside what did
# not. A silently short result set would be read as a model declining to answer.
#' Perform a batch, keeping the failures
#'
#' on_error = "continue" so a batch returns what succeeded alongside what did
#' not. A silently short result set would be read as a model declining to answer.
#'
#' Progress is off by default: httr2's bar writes to stderr, and PowerShell
#' turns any stderr from a native command into a NativeCommandError, so the bar
#' makes a clean run look like it failed. Set PF_ADJ_PROGRESS=1 for an
#' interactive run where the bar is wanted.
adj_perform <- function(reqs, workers = 6L,
                        progress = nzchar(Sys.getenv("PF_ADJ_PROGRESS"))) {
  req_perform_parallel(reqs, on_error = "continue", progress = progress,
                       max_active = max(1L, as.integer(workers)))
}

adj_body <- function(resp) {
  if (inherits(resp, "error") || inherits(resp, "condition"))
    return(list(ok = FALSE, status = NA_integer_, error = conditionMessage(resp)))
  st <- resp_status(resp)
  b  <- tryCatch(resp_body_json(resp), error = function(e) NULL)
  if (st >= 400L || is.null(b))
    return(list(ok = FALSE, status = st,
                error = if (!is.null(b$error$message)) b$error$message
                        else paste("HTTP", st)))
  list(ok = TRUE, status = st, body = b)
}

## ---- reading a response ----------------------------------------------------
adj_text <- function(body) {
  tb <- Filter(function(b) identical(b$type, "text"), body$content)
  if (!length(tb)) return("")
  paste(vapply(tb, function(b) b$text %||% "", character(1)), collapse = "\n")
}

adj_tool_input <- function(body, name) {
  tu <- Filter(function(b) identical(b$type, "tool_use") && identical(b$name, name),
               body$content)
  if (!length(tu)) return(NULL)
  tu[[length(tu)]]$input          # the last call wins if the model revised
}

# The light tier gets JSON by output_config.format, which guarantees the first
# text block parses. The deep tier gets it from a strict tool. This falls back
# to a fenced or embedded object so a stray wrapper sentence does not cost a
# whole case.
adj_parse_json <- function(txt) {
  if (!nzchar(txt)) return(NULL)
  try_one <- function(s) tryCatch(jsonlite::fromJSON(s, simplifyVector = TRUE),
                                  error = function(e) NULL)
  out <- try_one(txt)
  if (!is.null(out)) return(out)
  fence <- regmatches(txt, regexpr("(?s)\\{.*\\}", txt, perl = TRUE))
  if (length(fence)) return(try_one(fence))
  NULL
}

adj_usage <- function(body) {
  u <- body$usage %||% list()
  ws <- u$server_tool_use$web_search_requests %||% 0L
  c(input       = as.numeric(u$input_tokens %||% 0),
    output      = as.numeric(u$output_tokens %||% 0),
    cache_read  = as.numeric(u$cache_read_input_tokens %||% 0),
    cache_write = as.numeric(u$cache_creation_input_tokens %||% 0),
    web_search  = as.numeric(ws))
}

#' Token cost of a run, cache traffic included
#'
#' `cache_read` and `cache_write` default to 0 so an old two-argument call
#' still returns its old answer rather than erroring -- but a caller that has
#' the cache figures and omits them gets an understatement, which is exactly
#' the bug this signature exists to stop. Web search is billed per use and is
#' not a token cost; it is reported as a count by the stages that use it.
adj_cost <- function(model, input, output, cache_read = 0, cache_write = 0) {
  p <- ADJ_PRICES[[model]]
  if (is.null(p)) return(NA_real_)
  (input / 1e6) * p[["in_"]] + (output / 1e6) * p[["out"]] +
  (cache_read / 1e6) * p[["cr"]] + (cache_write / 1e6) * p[["cw"]]
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

## ---- the shared case renderer ----------------------------------------------
# One case as markdown. Called by BOTH tiers with the same arguments, so the
# case text in a light request and a deep request is identical.
#
# Candidates are given in npmatch's own score order and labelled by rank,
# because dev/LLM-REVIEW-INSTRUCTIONS.md's last worked example turns on the
# reviewer being able to see that rank 1 is not always right. Hiding the rank
# would change the task.
#
# Empty fields are printed as "-" rather than dropped. A reviewer needs to be
# able to tell "the BMF has no mission text for this EIN" (no evidence) from
# "the field was not supplied" (a broken packet), and ~57% of candidates have
# no 990 text at all.
adj_sq <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  trimws(x)
}

adj_fld <- function(label, value, max_chars = 1200) {
  v <- adj_sq(value)
  if (!nzchar(v)) v <- "-"
  if (nchar(v) > max_chars) v <- paste0(substr(v, 1, max_chars), " [...truncated]")
  sprintf("%s: %s", label, v)
}

adj_render_case <- function(case_row, cand_rows) {
  cr <- as.list(case_row)
  L  <- c(
    sprintf("### CASE %s", cr$grant_id),
    "",
    "GRANT AS FILED",
    adj_fld("  recip_name", cr$recip_name),
    adj_fld("  recip_city", cr$recip_city),
    adj_fld("  recip_state", cr$recip_state),
    adj_fld("  recip_zip5", cr$recip_zip5),
    adj_fld("  grant_purpose", cand_rows$grant_purpose[1]),
    adj_fld("  grant_amount", cand_rows$grant_amount[1]),
    adj_fld("  grant_year", cand_rows$grant_year[1]),
    adj_fld("  recip_status_raw", cand_rows$recip_status_raw[1]),
    adj_fld("  recipient_type", cr$recipient_type),
    "",
    "FILING FOUNDATION",
    adj_fld("  fdn_name", cr$filer_name),
    adj_fld("  fdn_state", cand_rows$FDN_org_addr_state[1]),
    adj_fld("  fdn_ntee", paste(adj_sq(cand_rows$FDN_ntee_code_clean[1]),
                                adj_sq(cand_rows$FDN_ntee_code_definition[1]))),
    "")
  for (i in seq_len(nrow(cand_rows))) {
    r <- as.list(cand_rows[i, ])
    L <- c(L,
      sprintf("CANDIDATE %s  (rank %s of %d%s)", i, r$rank, nrow(cand_rows),
              if (identical(as.integer(r$is_top_pick), 1L)) ", npmatch top pick" else ""),
      adj_fld("  ein", r$ein),
      adj_fld("  cand_name", r$cand_name),
      # The BMF's own display name, which is NOT always the matched name. It
      # differs on 29% of this packet's candidate rows, and where it differs it
      # is frequently the field that decides the case: two candidates both
      # matched as "Wake Forest University" display as "Mortar Board" and "Psi
      # Chi The International Honor Society In Psychology" -- different
      # organisations the reference keyed under the university's name. Omitting
      # it made those cases look like unresolvable same-name ties.
      # Shown only when it actually differs, so it is a signal rather than a
      # duplicated line on the 71% of rows where it says nothing new.
      if (nzchar(adj_sq(r$CAND_org_name_display)) &&
          !identical(toupper(adj_sq(r$CAND_org_name_display)),
                     toupper(adj_sq(r$cand_name))))
        adj_fld("  cand_name_bmf_display", r$CAND_org_name_display) else NULL,
      adj_fld("  cand_city", r$cand_city),
      adj_fld("  cand_state", r$cand_state),
      adj_fld("  cand_zip5", r$cand_zip5),
      adj_fld("  cand_ntee", paste(adj_sq(r$CAND_ntee_code_clean),
                                   adj_sq(r$CAND_ntee_code_definition))),
      adj_fld("  cand_nteev2_subsector", r$CAND_nteev2_subsector),
      adj_fld("  cand_activity_text", r$CAND_activity_code_definitions),
      adj_fld("  cand_subsection", r$CAND_subsection_code),
      adj_fld("  cand_ruling_year", r$CAND_ruling_date),
      adj_fld("  cand_assets", r$CAND_asset_amount),
      adj_fld("  cand_revenue", r$CAND_revenue_amount),
      adj_fld("  cand_ntee_text", r$cand_ntee_text, 800),
      adj_fld("  cand_mission", r$cand_mission, 1500),
      adj_fld("  cand_prog", r$cand_prog, 2500),
      sprintf("  signals: score=%s name_sim=%s geo_zip5=%s geo_state=%s pass=%s",
              adj_sq(r$score), adj_sq(r$name_sim), adj_sq(r$geo_zip5),
              adj_sq(r$geo_state), adj_sq(r$pass)),
      "")
  }
  paste(L, collapse = "\n")
}

## ---- verdict schema, shared by both tiers ----------------------------------
# The fields of dev/LLM-REVIEW-INSTRUCTIONS.md's output table. The deep tier
# adds two search fields; everything else is identical so the two verdict sets
# are directly comparable row by row.
#
# No numerical or string length constraints: structured outputs reject
# minimum/maximum/minLength, and additionalProperties MUST be false on every
# object. Every property is in `required` -- the API requires that, so
# "not applicable" is the empty string, never an absent key.
adj_verdict_schema <- function(deep = FALSE) {
  props <- list(
    grant_id        = list(type = "string"),
    verdict         = list(type = "string", enum = adj_array(c("MATCH", "NONE", "AMBIGUOUS"))),
    ein             = list(type = "string"),
    confidence      = list(type = "string", enum = adj_array(c("high", "medium", "low"))),
    evidence_class  = list(type = "string", enum = adj_array(c("QUOTE", "NTEE", "INFER", "NONE"))),
    evidence        = list(type = "string"),
    runner_up_ein   = list(type = "string"))
  if (deep) {
    props$ground_truth_name <- list(type = "string")
    props$search_findings   <- list(type = "string")
    props$search_confirmed  <- list(type = "string",
      enum = adj_array(c("CONFIRMED", "CONTRADICTED", "INCONCLUSIVE", "NOT_SEARCHED")))
  }
  list(type = "object", properties = props,
       required = adj_array(names(props)), additionalProperties = FALSE)
}

adj_verdict_cols <- function(deep = FALSE)
  names(adj_verdict_schema(deep)$properties)

# Coerce one parsed verdict to a one-row data.frame with stable columns, so a
# model that omits or mistypes a field produces an NA rather than a crash or a
# silently shifted column.
adj_verdict_row <- function(v, grant_id, deep = FALSE) {
  cols <- adj_verdict_cols(deep)
  out <- as.list(setNames(rep(NA_character_, length(cols)), cols))
  if (!is.null(v) && length(v))
    for (nm in intersect(cols, names(v))) {
      x <- v[[nm]]
      out[[nm]] <- if (length(x) == 0L) NA_character_ else as.character(x)[1]
    }
  out$grant_id <- grant_id      # never trust the model to echo the key
  as.data.frame(out, stringsAsFactors = FALSE)
}

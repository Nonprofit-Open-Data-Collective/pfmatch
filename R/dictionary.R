# ============================================================================
# The grant-side dictionary: match grants against grants, after the BMF.
#
# Foundations write recipient names by a convention of their own and the BMF
# carries the registered legal name, so a grant that fails against the BMF can
# still match a grant that already cleared. Measured over the 312,306 cleared
# rows of the triangulation run (dev/EXP-HEAD-REFERENCE.log):
#
#   a cleared row hits another cleared GRANT rendering exactly   94.06%
#   ... hits its own BMF name exactly                            47.16%
#   ... grant-exact but NOT bmf-exact                            48.12%
#
# On FUZZY distance the grant side is marginally worse (median 0.960 to the
# nearest other rendering against 0.967 to the BMF name), so the advantage is
# in frequency, not similarity. It shows up as exact-key recall on cases the
# BMF matcher could not clear: 11.0% of the MAYBE tier and 1.4% of NO.
#
# THIS IS A SUPPLEMENT, NOT A REFERENCE. A dictionary built from one run holds
# the EINs that run resolved -- 31,721 against the BMF's ~1.9M -- and reproduces
# only 26.7% of the BMF's own YES rows. It runs AFTER the cascade, on what the
# cascade could not clear, and never instead of it. pf_recover_from_dictionary()
# enforces that by only ever looking at unresolved rows.
#
# EVERY EIN IN IT CAME FROM THE PIPELINE. Resolving against it propagates the
# pipeline's own decisions, errors included, so it is a recall device whose
# precision is inherited rather than established. That is what `accept` is for:
# the default takes only the cases where the dictionary and the BMF's own top
# candidate agree -- 40.9% of the recoveries, which were recoverable all along
# and which the margin gate would not release -- and queues the rest for
# adjudication instead of adopting them. The disagreements concentrate in the
# known affiliate failure (an organisation against its own foundation or alumni
# fund, a chapter network picking the wrong chapter;
# dev/AFFILIATION-FINDINGS.md), so the queue lands in work already underway.
#
# Promotion candidate: a dictionary of resolved query-side renderings is generic
# linkage machinery by dev/NPMATCH-PROMOTION-PLAN.md's own test -- it would be
# equally correct over SAM or USASpending. It is here because this is where it
# was first needed.
# ============================================================================

.pf_dict_nrm <- function(x) {
  x <- as.character(x); x[is.na(x)] <- ""
  trimws(gsub(" +", " ", gsub("[^A-Z0-9 ]", " ", toupper(x))))
}
.pf_dict_e9 <- function(v) {
  v <- gsub("[^0-9]", "", as.character(v))
  ifelse(nchar(v) == 9L, v, NA_character_)
}

#' Build a dictionary of resolved grant renderings
#'
#' Turns matched grant rows into a reference the cascade can run against, keyed
#' on the **filer-written** name and address rather than the BMF's. Use it with
#' [pf_recover_from_dictionary()].
#'
#' @section Why the address is not optional:
#' Keying on the name alone does not work, and the margin is not close.
#' Measured over 88,744 renderings: 727 of 63,310 bare name keys (1.15%) carry
#' more than one EIN, and the worst is `HABITAT FOR HUMANITY` with **39**.
#' `RONALD MCDONALD HOUSE` has 31, `BIG BROTHERS BIG SISTERS` 29. Adding ZIP5
#' takes that to **0 of 66,425**. Any `(name_key, zip5)` that still resolves to
#' more than one EIN is dropped rather than guessed at, and the count is
#' reported in the `ambiguous_dropped` attribute.
#'
#' @param grants Matched grant rows: the prepared recipient columns
#'   (`recip_name`, `recip_street`, `recip_city`, `recip_state`, `recip_zip5`)
#'   plus a tier and an EIN. A list carrying `$grants` is accepted, so the
#'   output of a run can be passed straight in.
#' @param keep Tiers to build from. `"YES"` only, by default: a dictionary
#'   seeded from MAYBE would propagate exactly the decisions in doubt.
#' @param exclude Optional grant keys to leave out — pass the keys of the rows
#'   you intend to match, or the dictionary answers them with themselves.
#' @param key_col Column holding the grant key, for `exclude`.
#' @param stats `"dictionary"` (default) computes the name and token statistics
#'   over the dictionary itself; supply a reference bundle to borrow its
#'   `name_freq` and `token_idf` instead. The IDF of ~90k filer renderings is
#'   not the IDF of 3.88M BMF names, and which one is right is an open question
#'   — the argument exists so the two are never confounded silently.
#' @param verbose Print what was built and what was dropped.
#' @return A reference bundle — `reference`, `name_freq`, `token_idf`,
#'   `ref_index`, `normalizer` — with attributes `n_eins`, `n_renderings`,
#'   `ambiguous_dropped` and `built_from`.
#' @seealso [pf_recover_from_dictionary()]
#' @export
pf_grant_dictionary <- function(grants, keep = "YES", exclude = NULL,
                                key_col = NULL, stats = "dictionary",
                                verbose = TRUE) {
  if (is.list(grants) && !is.null(grants$grants)) grants <- grants$grants
  g <- data.table::as.data.table(as.data.frame(grants))
  need <- c("recip_name", "recip_street", "recip_city", "recip_state",
            "recip_zip5", "status", "ein")
  miss <- setdiff(need, names(g))
  if (length(miss))
    stop("pf_grant_dictionary() needs column(s): ", paste(miss, collapse = ", "),
         call. = FALSE)
  say <- function(...) if (verbose) message(sprintf(...))
  n0 <- nrow(g)

  g <- g[as.character(get("status")) %in% keep]
  g[, ".ein9" := .pf_dict_e9(get("ein"))]
  g <- g[!is.na(get(".ein9"))]
  if (!is.null(exclude) && length(exclude)) {
    kc <- key_col %||% intersect(c("grant_id", "gkey"), names(g))[1]
    if (is.na(kc) || is.null(kc))
      stop("exclude= needs key_col to name the grant-key column.", call. = FALSE)
    before <- nrow(g)
    g <- g[!(as.character(get(kc)) %chin% as.character(exclude))]
    say("excluded %s rows named in `exclude`", format(before - nrow(g), big.mark = ","))
  }
  if (!nrow(g)) stop("no rows left to build a dictionary from.", call. = FALSE)

  d <- unique(g[, list(ein = get(".ein9"),
                       name = as.character(get("recip_name")),
                       street = as.character(get("recip_street")),
                       city = as.character(get("recip_city")),
                       state = as.character(get("recip_state")),
                       zip5 = as.character(get("recip_zip5")))])
  d <- d[nzchar(.pf_dict_nrm(d$name))]
  say("from %s rows: %s distinct (rendering, address, EIN) over %s EINs",
      format(n0, big.mark = ","), format(nrow(d), big.mark = ","),
      format(data.table::uniqueN(d$ein), big.mark = ","))

  # Drop any (name, zip5) that still carries two EINs. Measured at zero, and
  # kept as a guard: a silent collision here would attach one organisation's
  # EIN to another's grants, which is the one failure this must not have.
  d[, ".nk" := .pf_dict_nrm(name)]
  amb <- d[, list(.n_ein = data.table::uniqueN(ein)), by = c(".nk", "zip5")]
  bad <- amb[get(".n_ein") > 1L]
  n_drop <- 0L
  if (nrow(bad)) {
    key_bad <- paste(bad$.nk, bad$zip5, sep = "\r")
    n_drop <- sum(paste(d$.nk, d$zip5, sep = "\r") %chin% key_bad)
    d <- d[!(paste(get(".nk"), zip5, sep = "\r") %chin% key_bad)]
    say("dropped %s renderings on %s ambiguous (name, zip5) keys",
        format(n_drop, big.mark = ","), format(nrow(bad), big.mark = ","))
  } else {
    say("no ambiguous (name, zip5) keys")
  }
  d[, ".nk" := NULL]
  # np_reference() cannot canonicalize a zero-row frame, and a dictionary with
  # nothing in it is not a thing to hand onward anyway. Say which guard emptied
  # it rather than failing inside npmatch.
  if (!nrow(d))
    stop("the dictionary is empty: all ", format(n_drop, big.mark = ","),
         " rendering(s) were dropped on ambiguous (name, zip5) keys.\n",
         "  Every name in this input maps to more than one EIN at its ZIP, so ",
         "there is nothing safe to key on.", call. = FALSE)

  m <- npmatch::np_map_bmf()
  raw <- data.table::data.table(d$ein, d$name, "", d$street, d$city, d$state,
                                d$zip5, "")
  data.table::setnames(raw, unname(m[c(".ein", "name", "dba", "street", "city",
                                       "state", "zip5", "zip_plus4")]))
  ref <- npmatch::np_normalize(npmatch::np_reference(as.data.frame(raw), m))
  ref <- pf_add_recovery_keys(ref)

  borrow <- is.list(stats) && !is.null(stats$name_freq)
  out <- list(
    reference  = ref,
    name_freq  = if (borrow) stats$name_freq else npmatch::np_name_freq(ref$name_key),
    token_idf  = if (borrow) stats$token_idf else npmatch::np_token_idf(ref$name_key),
    ref_index  = npmatch::np_ref_index(ref),
    normalizer = tryCatch(npmatch::np_normalize_signature(),
                          error = function(e) NA_character_))
  attr(out, "n_eins") <- data.table::uniqueN(d$ein)
  attr(out, "n_renderings") <- nrow(d)
  attr(out, "ambiguous_dropped") <- n_drop
  attr(out, "built_from") <- sprintf("%s rows, tiers %s", format(n0, big.mark = ","),
                                     paste(keep, collapse = "/"))
  say("dictionary: %s renderings, %s EINs, statistics %s",
      format(nrow(ref), big.mark = ","), format(attr(out, "n_eins"), big.mark = ","),
      if (borrow) "borrowed" else "dictionary-native")
  out
}

#' Recover unresolved grants against a grant-side dictionary
#'
#' Runs the cascade over the rows a BMF run could not clear, against a
#' dictionary from [pf_grant_dictionary()], and applies an acceptance rule.
#'
#' @section The acceptance rule:
#' `accept = "agree"` (the default) promotes a row only when the dictionary's
#' EIN is the one the BMF run already held as its own top candidate. Those were
#' recoverable all along and the margin gate would not release them — 40.9% of
#' the recoveries measured on the benchmark. The rest are a *new claim* from a
#' reference whose labels this pipeline produced, so they go to the queue
#' attribute rather than into the status frame. `accept = "all"` promotes every
#' dictionary YES and is for measurement, not production; `accept = "none"`
#' annotates and promotes nothing.
#'
#' @param status Status frame from [pf_run_batches()] or [pf_match_grants()],
#'   carrying `grant_id`, `status` and `ein`.
#' @param dict A bundle from [pf_grant_dictionary()].
#' @param recipients The prepared recipient frame the run was matched from.
#' @param accept `"agree"`, `"all"` or `"none"`.
#' @param passes Pass list for the dictionary run.
#' @param verbose Print the recovery counts.
#' @return `status` with `dict_status`, `dict_ein`, `dict_score` and
#'   `dict_agrees` added, `status` and `ein` updated on accepted rows, and
#'   `recovered` flagging them. The non-accepted dictionary YES rows are on the
#'   `queue` attribute; `attr(, "counts")` carries the tally.
#' @seealso [pf_grant_dictionary()]
#' @export
pf_recover_from_dictionary <- function(status, dict, recipients,
                                       accept = c("agree", "all", "none"),
                                       passes = c(pf_staged_passes("lean", concat = TRUE),
                                                  pf_recovery_passes(state = TRUE)),
                                       verbose = TRUE) {
  accept <- match.arg(accept)
  say <- function(...) if (verbose) message(sprintf(...))
  s <- data.table::as.data.table(as.data.frame(status))
  r <- data.table::as.data.table(as.data.frame(recipients))
  if (is.null(s$grant_id) || is.null(s$status))
    stop("status needs `grant_id` and `status`.", call. = FALSE)
  if (is.null(r$grant_id))
    stop("recipients needs `grant_id`.", call. = FALSE)

  todo <- s[as.character(get("status")) != "YES"]$grant_id
  say("unresolved rows to retry: %s of %s", format(length(todo), big.mark = ","),
      format(nrow(s), big.mark = ","))
  if (!length(todo)) {
    data.table::setattr(s, "counts", c(retried = 0L, dict_yes = 0L, accepted = 0L))
    return(s)
  }
  sub <- r[as.character(get("grant_id")) %chin% as.character(todo)]
  if (!nrow(sub)) stop("none of the unresolved ids are in `recipients`.", call. = FALSE)

  m <- pf_match_grants(sub, dict, passes = passes, recover = TRUE,
                       verbose = FALSE, check_reference = "warn")
  d <- data.table::as.data.table(as.data.frame(m$result))
  idc <- if (!is.null(d$.id)) ".id" else "grant_id"
  d <- d[, list(grant_id = as.character(get(idc)),
                dict_status = as.character(get("tier")),
                dict_ein = .pf_dict_e9(get("overall_ein")),
                dict_score = suppressWarnings(as.numeric(get("overall_score"))))]

  s[, "grant_id" := as.character(get("grant_id"))]
  s <- merge(s, d, by = "grant_id", all.x = TRUE)
  s[, "dict_agrees" := !is.na(get("dict_ein")) & !is.na(.pf_dict_e9(get("ein"))) &
                        get("dict_ein") == .pf_dict_e9(get("ein"))]
  hit <- !is.na(s$dict_status) & s$dict_status == "YES" &
          as.character(s$status) != "YES"
  take <- .pf_dict_accept(hit, s$dict_agrees, accept)
  s[, "recovered" := take]
  if (any(take)) {
    s[take, "ein" := get("dict_ein")]
    s[take, "status" := "YES"]
  }
  cnt <- c(retried = length(todo), dict_yes = sum(hit),
           agreeing = sum(hit & s$dict_agrees), accepted = sum(take))
  say("dictionary cleared %s of them; %s agree with the BMF's own top candidate",
      format(cnt[["dict_yes"]], big.mark = ","),
      format(cnt[["agreeing"]], big.mark = ","))
  say("accepted %s under accept = \"%s\"", format(cnt[["accepted"]], big.mark = ","),
      accept)
  data.table::setattr(s, "queue", s[hit & !take])
  data.table::setattr(s, "counts", cnt)
  s
}

# The acceptance rule, apart from the plumbing so it can be tested without
# running a cascade. `hit` is a dictionary YES on a row the BMF left unresolved;
# `agrees` is whether the dictionary's EIN is the one the BMF already had as its
# top candidate. NA in `agrees` is a disagreement, not an agreement: a row the
# BMF could not name a candidate for has nothing to corroborate the dictionary.
.pf_dict_accept <- function(hit, agrees, accept = c("agree", "all", "none")) {
  accept <- match.arg(accept)
  hit <- !is.na(hit) & hit
  agrees <- !is.na(agrees) & agrees
  switch(accept,
         agree = hit & agrees,
         all   = hit,
         none  = rep(FALSE, length(hit)))
}

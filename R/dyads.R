#' Disclosed EIN dyads: substitutable pairs and merely related ones
#'
#' A grant reported to `EAGLE RANCH` may have been paid to `EAGLE RANCH
#' FOUNDATION`, and nothing in the name or the address decides which. The
#' cascade cannot resolve that and should not pretend to. This module builds the
#' table that lets it stop trying: one row per **disclosed pair of EINs**, drawn
#' from Schedule A Part I line 12g and Schedule R Part II.
#'
#' @section Dyads, not clusters — the one design decision that matters:
#' The obvious implementation is a transitive closure with a `cluster_id` per
#' component. Measured on the pooled 2009-2024 disclosures (566,653 pairs over
#' 174,496 EINs), that produces a single component holding **66,973 EINs across
#' 56 states** — 38% of every EIN in the graph — chaining The Reinvestment Fund
#' to the Jewish Community Federation of San Francisco to Glacial Ridge Hospital
#' Foundation. A match "verified" against a set that large is unfalsifiable.
#'
#' A same-city gate does not fix it: the largest same-city component is 407 EINs
#' in Phoenix, merging Florence Crittenton Services of Arizona, the Arizona
#' Medical Association Foundation and Arizona's Children Association.
#'
#' So this module emits **direct edges only**. Two EINs are in a dyad when one
#' filing names the other, and never because a third party names them both.
#' [pf_dyad_collapse()] enforces that by resolving groups only within the
#' candidates of a single grant. See `dev/CLUSTER-FINDINGS.md` §2.
#'
#' @section Substitutable versus related:
#' A Schedule R Part II edge means *related*, which is much weaker than
#' *interchangeable*. It links `Mayo Clinic Health System-Fairmont` to
#' `Mayo Clinic Health System-Lake City` — two different hospitals — and
#' `PLANNED PARENTHOOD GLOBAL` to `PLANNED PARENTHOOD ACTION FUND`, which is a
#' 501(c)(4) and cannot receive the same grant. Relaxing an error definition
#' across those edges launders real errors into passes.
#'
#' `dyad_class` therefore separates two things:
#' \describe{
#'   \item{`substitutable`}{The arm exists to fund this one body, or carries its
#'     name. Three conditions, all measured: see *Why exclusivity is the test*.}
#'   \item{`related`}{Every other disclosed edge. Useful for context and for
#'     flagging, never for relaxing a correctness test.}
#' }
#'
#' @section Why exclusivity is the test:
#' A first build classed every Schedule A edge as substitutable and produced an
#' EIN with **905 substitutable partners**: the *YMCA Retirement Fund*, a
#' 509(a)(3) that supports 907 local YMCAs. SparkJoy Foundation supports 408
#' unrelated Maine charities, Vitalyst Health Foundation 406, Ascension Health
#' 253. A grant reported to `Bangor YMCA` is not interchangeable with the
#' retirement fund, so **a bare Schedule A edge cannot license substitution** —
#' 43% of Schedule A edges come from a supporter with more than ten supportees.
#'
#' The mirror-image failure is the federated sibling: an identical name core
#' catches 337 chapters of `ALPHA LAMBDA DELTA`, 214 South Carolina Masonic
#' lodges, and 150-odd `VOLUNTEERS OF AMERICA` affiliates. Siblings are not
#' substitutes either — that is [pf_group_siblings()] territory, and a warning
#' rather than an invitation to merge.
#'
#' Both failures are the same measurement: **degree**. A body with an arm has
#' one to three of them; anything with fifty is a network. So `substitutable`
#' requires all three of
#' \enumerate{
#'   \item a Schedule A edge whose *supporter* names at most `max_fanout`
#'     organisations, **or** an identical name core in the same state;
#'   \item both parties sharing a subsection code — a 501(c)(3) and a
#'     501(c)(4) are not substitutes for a private foundation's grant, whatever
#'     Schedule R says about them being related;
#'   \item neither party exceeding `max_degree` substitutable partners once the
#'     first two conditions are applied.
#' }
#' At the defaults this yields 29,238 substitutable pairs with a **maximum
#' degree of 5 and no EIN above it**, against 129,645 pairs and a maximum of 905
#' for the naive rule, while retaining 89% of its reach into the MAYBE tier
#' (1,055 of 1,183 top-two pairs on the 50k run). The sweep is
#' `dev/sweep-dyad-rules.R`; the adjudicated 100 does not discriminate between
#' any of the six rules tried, so this is chosen on graph safety, not on labels.
#'
#' @section What it is worth:
#' On a 50,000-grant run, 14.9% of MAYBE grants have a directly disclosed top
#' two, rising to 24.4% inside the tie band, and collapsing dissolves the tie
#' entirely for 1,224 grants (22.2% of the MAYBE tie band). Where the edge fires
#' it is precise: 98.9% of linked top-two pairs share a content token and 54%
#' share an identical name core. Its increment over the disclosure-free name
#' rule in [pf_cluster_arms()] is 5.0% of the MAYBE tier — this is a
#' direction-and-confirmation feature, not a recall feature.
#'
#' Pooling fifteen years buys almost nothing over a single year (49% to 52% of
#' known arm pairs) because the ceiling is non-filing, not vintage. Pool for the
#' `n_years` stability signal, not for coverage.
#'
#' @name pf_dyads
NULL

.pf_DYAD_COLS <- c("ego_ein", "alter_ein", "tax_year", "ego_name", "alter_name",
                   "alter_state", "alter_city", "rel_type", "direction")

#' Default locations of the linkid dyad extracts
#'
#' The `dyad_` extracts carry `ego_ein` and `alter_ein` already normalised. The
#' `efile_` variants of the same tables mirror the raw e-file column names and
#' **do not carry the filer EIN at all** — only `OBJECTID` — so they cannot be
#' used here without a separate object-id to EIN index. Always use `dyad_`.
#'
#' @param dir Directory holding linkid's `out/full` output.
#' @return A named list of two file paths.
#' @export
pf_dyad_sources <- function(dir = "~/Documents/grants/linkid/out/full")
  list(supported = file.path(path.expand(dir), "dyad_supported_orgs.csv"),
       related   = file.path(path.expand(dir), "dyad_related_exempt_orgs.csv"))

#' Build the dyad table
#'
#' Reads the Schedule A and Schedule R dyad extracts, keeps rows where both ends
#' carry a usable EIN, symmetrises to one row per unordered pair, and classifies
#' each pair as `substitutable` or `related`.
#'
#' @param supported Path to `dyad_supported_orgs.csv`, or the table itself.
#'   `NULL` to skip Schedule A.
#' @param related Path to `dyad_related_exempt_orgs.csv`, or the table itself.
#'   `NULL` to skip Schedule R.
#' @param bmf Processed BMF (path or data frame). Supplies the names used for
#'   the name-core test and the subsection codes used to veto cross-subsection
#'   substitution. Strongly recommended; without it the filed names are used and
#'   no subsection veto is applied.
#' @param min_years Drop pairs disclosed in fewer than this many tax years. The
#'   default keeps everything; 2 removes 12% of pairs and is a reasonable
#'   setting if single-year disclosures look like data entry noise to you.
#' @param max_fanout A Schedule A edge licenses substitution only if the
#'   supporter names at most this many organisations. Above it the filer is a
#'   grantmaking supporting organisation, not an arm.
#' @param max_degree No EIN may end up with more than this many substitutable
#'   partners; edges touching one that does are demoted to `related`. This is
#'   what removes federated networks.
#' @param cache Path to cache the result as `.rds`. `NULL` to skip.
#' @param verbose Print progress.
#' @return A keyed `data.table` with `ein_a < ein_b` and columns `dyad_id`,
#'   `dyad_class`, `dyad_reason`, `src_a` (Schedule A seen), `src_r` (Schedule R
#'   seen), `sched_a_dir` (`a_supports_b` / `b_supports_a` / `NA`), `fan_out`,
#'   `n_years`, `first_year`, `last_year`, `same_state`, `same_city`, `name_a`,
#'   `name_b`, `in_bmf`. Deliberately **not** given an S3 class: it is a table
#'   people subset constantly, and a class would hijack the print method of
#'   every subset. Use [pf_dyad_summary()].
#' @seealso [pf_dyad_collapse()], [pf_dyad_annotate()], [pf_cluster_arms()]
#' @export
pf_build_dyads <- function(supported = pf_dyad_sources()$supported,
                           related   = pf_dyad_sources()$related,
                           bmf = NULL, min_years = 1L, max_fanout = 3L,
                           max_degree = 5L, cache = NULL, verbose = TRUE) {
  if (!is.null(cache) && file.exists(cache)) return(readRDS(cache))
  say <- function(...) if (verbose) cat(sprintf(...), "\n")

  rd <- function(p, tag) {
    if (is.null(p)) return(NULL)
    if (is.character(p) && length(p) == 1L) {
      if (!file.exists(p)) stop("no such file: ", p, call. = FALSE)
      p <- data.table::fread(p, colClasses = "character", showProgress = FALSE,
                             select = .pf_DYAD_COLS)
    }
    d <- data.table::as.data.table(p)
    miss <- setdiff(c("ego_ein", "alter_ein"), names(d))
    if (length(miss))
      stop("`", tag, "` lacks ", paste(miss, collapse = "/"),
           ". The efile_ variants do not carry the filer EIN; use the dyad_ ones.",
           call. = FALSE)
    d[, src := tag][]
  }

  d <- data.table::rbindlist(list(rd(supported, "SCHED_A"), rd(related, "SCHED_R")),
                             use.names = TRUE, fill = TRUE)
  if (!nrow(d)) stop("no dyad rows read", call. = FALSE)
  say("read %s disclosure rows", format(nrow(d), big.mark = ","))

  d[, c("a", "b", "year") := list(.pf_ein(ego_ein), .pf_ein(alter_ein),
                                  suppressWarnings(as.integer(tax_year)))]
  d <- d[!is.na(a) & !is.na(b) & a != b]
  say("  usable directed rows: %s", format(nrow(d), big.mark = ","))

  # Schedule A is the only source that states a direction: the filer is the
  # supporting organization and the alter is the one it supports.
  d[, sup_key := data.table::fifelse(src == "SCHED_A", paste(a, b), NA_character_)]
  supk <- unique(stats::na.omit(d$sup_key))

  d[, c("x", "y") := list(pmin(a, b), pmax(a, b))]
  z <- d[, list(src_a = any(src == "SCHED_A"), src_r = any(src == "SCHED_R"),
                n_years = data.table::uniqueN(year[!is.na(year)]),
                first_year = suppressWarnings(min(year, na.rm = TRUE)),
                last_year  = suppressWarnings(max(year, na.rm = TRUE)),
                filed_a = ego_name[1L], filed_b = alter_name[1L]),
        by = list(ein_a = x, ein_b = y)]
  z[!is.finite(first_year), first_year := NA_integer_]
  z[!is.finite(last_year),  last_year  := NA_integer_]
  if (min_years > 1L) {
    n0 <- nrow(z); z <- z[n_years >= min_years]
    say("  dropped %s pairs seen in fewer than %d years",
        format(n0 - nrow(z), big.mark = ","), min_years)
  }
  say("distinct unordered pairs: %s", format(nrow(z), big.mark = ","))

  z[, sched_a_dir := data.table::fifelse(
       paste(ein_a, ein_b) %chin% supk, "a_supports_b",
       data.table::fifelse(paste(ein_b, ein_a) %chin% supk, "b_supports_a",
                           NA_character_))]

  ## ------------------------------------------------------- BMF-derived fields
  nm_a <- z$filed_a; nm_b <- z$filed_b
  same_state <- rep(NA, nrow(z)); same_city <- rep(NA, nrow(z))
  sub_ok <- rep(TRUE, nrow(z))
  if (!is.null(bmf)) {
    if (is.character(bmf) && length(bmf) == 1L)
      bmf <- data.table::fread(bmf, colClasses = "character", showProgress = FALSE,
                               select = c("ein", "org_name_join", "org_addr_city",
                                          "org_addr_state", "subsection_code"))
    bm <- data.table::as.data.table(bmf)
    bm[, ein := .pf_ein(ein)]
    bm <- unique(bm[!is.na(ein)], by = "ein")
    i <- match(z$ein_a, bm$ein); j <- match(z$ein_b, bm$ein)
    gi <- function(k, f) if (f %in% names(bm)) bm[[f]][k] else rep(NA_character_, length(k))
    nm_a <- data.table::fifelse(is.na(gi(i, "org_name_join")), nm_a, gi(i, "org_name_join"))
    nm_b <- data.table::fifelse(is.na(gi(j, "org_name_join")), nm_b, gi(j, "org_name_join"))
    sa <- gi(i, "org_addr_state"); sb <- gi(j, "org_addr_state")
    ca <- gi(i, "org_addr_city");  cb <- gi(j, "org_addr_city")
    same_state <- !is.na(sa) & !is.na(sb) & sa == sb
    same_city  <- same_state & !is.na(ca) & !is.na(cb) & ca == cb
    # A 501(c)(3) and a 501(c)(4) are not substitutes for a private foundation's
    # grant, whatever Schedule R says about them being related.
    xa <- gi(i, "subsection_code"); xb <- gi(j, "subsection_code")
    known <- !is.na(xa) & !is.na(xb) & nzchar(xa) & nzchar(xb)
    sub_ok <- !known | xa == xb
    z[, in_bmf := !is.na(i) & !is.na(j)]
  } else {
    z[, in_bmf := NA]
  }
  z[, c("name_a", "name_b", "same_state", "same_city") :=
      list(nm_a, nm_b, same_state, same_city)]

  ## ------------------------------------------------------------ the class
  # 1. the exclusive-support test: how many bodies does this supporter support?
  sup_ein <- data.table::fifelse(is.na(z$sched_a_dir), NA_character_,
               data.table::fifelse(z$sched_a_dir == "a_supports_b",
                                   z$ein_a, z$ein_b))
  fo <- table(sup_ein[!is.na(sup_ein)])
  z[, fan_out := as.integer(fo[sup_ein])]
  by_sched_a <- !is.na(z$sched_a_dir) & !is.na(z$fan_out) & z$fan_out <= max_fanout

  # 2. the name test, which needs geography or it collects federated siblings
  core_a <- pf_arm_core(nm_a); core_b <- pf_arm_core(nm_b)
  same_core <- !is.na(core_a) & core_a == core_b & nchar(core_a) >= 8L &
               lengths(strsplit(core_a, " ")) >= 2L
  by_name <- same_core & (z$same_state %in% TRUE)

  z[, dyad_reason := data.table::fifelse(
       by_sched_a & by_name, "exclusive_support+same_name_core",
       data.table::fifelse(by_sched_a, "exclusive_support",
       data.table::fifelse(by_name, "same_name_core+same_state",
       data.table::fifelse(!is.na(sched_a_dir), "support_relation_not_exclusive",
       data.table::fifelse(same_core, "same_name_core_different_state",
                           "disclosed_related")))))]
  cls <- (by_sched_a | by_name) & sub_ok
  z[!cls & (by_sched_a | by_name), dyad_reason :=
      paste0(dyad_reason, "; demoted: subsection mismatch")]

  # 3. the degree cap, which is what removes federated networks
  if (max_degree > 0L && any(cls)) {
    s  <- z[cls]
    dg <- data.table::rbindlist(list(s[, list(e = ein_a)], s[, list(e = ein_b)]))[
            , list(n = .N), by = e]
    hub <- dg[n > max_degree]$e
    over <- cls & (z$ein_a %chin% hub | z$ein_b %chin% hub)
    z[over, dyad_reason := paste0(dyad_reason, "; demoted: degree > ", max_degree)]
    say("  demoted for degree > %d: %s pairs (federated networks)",
        max_degree, format(sum(over), big.mark = ","))
    cls <- cls & !over
  }
  z[, dyad_class := data.table::fifelse(cls, "substitutable", "related")]

  data.table::setorderv(z, c("ein_a", "ein_b"))
  z[, dyad_id := sprintf("PFD%08d", seq_len(.N))]
  z[, c("filed_a", "filed_b") := NULL]
  data.table::setcolorder(z, c("dyad_id", "ein_a", "ein_b", "dyad_class",
                               "dyad_reason", "src_a", "src_r", "sched_a_dir",
                               "fan_out", "n_years", "first_year", "last_year",
                               "same_state", "same_city", "name_a", "name_b"))
  data.table::setkeyv(z, c("ein_a", "ein_b"))
  say("  substitutable %s | related %s",
      format(sum(z$dyad_class == "substitutable"), big.mark = ","),
      format(sum(z$dyad_class == "related"), big.mark = ","))
  if (!is.null(cache)) {
    if (!dir.exists(dirname(cache))) dir.create(dirname(cache), recursive = TRUE)
    saveRDS(z, cache, compress = FALSE)
  }
  z[]
}

#' Summarise a dyad table
#'
#' Reports size, class split, and the degree distribution of the substitutable
#' subgraph — the last being the number that says whether the table is safe to
#' collapse on. A maximum substitutable degree above about ten means a federated
#' network has leaked in; see [pf_dyads].
#'
#' @param x Output of [pf_build_dyads()].
#' @return `x`, invisibly.
#' @export
pf_dyad_summary <- function(x) {
  cat(sprintf("dyads: %s pairs over %s EINs\n",
              format(nrow(x), big.mark = ","),
              format(length(unique(c(x$ein_a, x$ein_b))), big.mark = ",")))
  tb <- table(x$dyad_class)
  for (k in names(tb))
    cat(sprintf("  %-14s %9s (%4.1f%%)\n", k, format(tb[[k]], big.mark = ","),
                100 * tb[[k]] / nrow(x)))
  cat(sprintf("  Schedule A direction stated on %s\n",
              format(sum(!is.na(x$sched_a_dir)), big.mark = ",")))
  s <- x[x$dyad_class == "substitutable", ]
  if (nrow(s)) {
    e  <- c(s$ein_a, s$ein_b)
    dg <- tabulate(match(e, unique(e)))
    cat(sprintf("  substitutable subgraph: max degree %d, mean %.2f, %d EINs\n",
                max(dg), mean(dg), length(dg)))
  }
  invisible(x)
}

#' Look up the dyad class for pairs of EINs
#'
#' Vectorised and order-insensitive. Returns `NA` where no direct edge exists —
#' and only a direct edge counts, by design (see [pf_dyads]).
#'
#' @param dyads Output of [pf_build_dyads()].
#' @param a,b Character vectors of EINs, recycled to a common length.
#' @param what `"class"` (default) or `"id"`.
#' @return A character vector.
#' @export
pf_dyad_lookup <- function(dyads, a, b, what = c("class", "id")) {
  what <- match.arg(what)
  a <- .pf_ein(a); b <- .pf_ein(b)
  n <- max(length(a), length(b))
  a <- rep_len(a, n); b <- rep_len(b, n)
  i <- .pf_dyad_match(dyads, a, b)
  out <- if (what == "class") dyads$dyad_class[i] else dyads$dyad_id[i]
  out[is.na(a) | is.na(b) | a == b] <- NA_character_
  out
}

# The pasted key over the whole dyad table is the expensive part of a lookup and
# does not change between calls, so cache it on the table by reference.
.pf_dyad_match <- function(dyads, a, b) {
  k <- attr(dyads, "pf_key")
  if (is.null(k) || length(k) != nrow(dyads)) {
    k <- paste(dyads$ein_a, dyads$ein_b)
    data.table::setattr(dyads, "pf_key", k)
  }
  match(paste(pmin(a, b), pmax(a, b)), k)
}

#' Dyad collapse settings
#'
#' @param tie_band Candidates within this much of the top score are in
#'   contention. Matches npmatch's `np_config()$tie_band`.
#' @param max_band Cap on how many candidates per grant enter the collapse, by
#'   score. This is a hard requirement, not a tuning knob: pairing is quadratic,
#'   and a token-blocked query can put **thousands** of equal-scoring candidates
#'   inside the band — one grant with 2,000 of them is two million comparisons,
#'   which is what hung the first run of `dev/test-dyad-cascade.R`. Nothing below
#'   the top handful can affect the selection anyway. Counts of what the cap
#'   drops are reported by [pf_dyad_collapse()].
#' @param use Which dyad classes may be collapsed. The default is
#'   `"substitutable"` only; `c("substitutable", "related")` is available for
#'   measurement but see [pf_dyads] for why it should not be shipped.
#' @param policy Which member to report when a dyad is collapsed.
#'   \describe{
#'     \item{`"query"`}{**Default.** Follow the grant record's own name: report
#'       the arm when the recorded recipient name carries a support marker, the
#'       operating entity when it does not. The funder wrote a name down, and it
#'       is evidence on *every* case rather than on the 15 that were adjudicated.}
#'     \item{`"operating"`}{Always the non-arm member. This was the previous
#'       default and it **contradicts the source document on 134 of the 155**
#'       collapsed grants whose recorded name carries a support marker (86%) —
#'       reporting `CRAIG HOSPITAL` for a grant written as `CRAIG HOSPITAL
#'       FOUNDATION`.}
#'     \item{`"arm"`}{Always the support arm. The mirror error: it reports an arm
#'       on 41% of grants whose recorded name has no marker at all.}
#'     \item{`"top"`}{Whatever the cascade ranked first. Promotes least, because
#'       it keeps the arm and inherits the `affiliate_suffix` soft veto — see
#'       *Why the policies differ*.}
#'   }
#'   On 15 adjudicated arm pairs the flat operating rule scored 60% against the
#'   cascade's 27%; that 60% has a 32-84% interval and is not settled.
#'   `pf_arm_order()` implements the purpose-conditional alternative.
#'
#' @section Why the policies differ:
#' On the 50k run, `operating` promotes 629 MAYBE grants to YES, `top` 388 and
#' `arm` 253 — and `top` cannot lose on score, since it keeps the highest-scoring
#' member by construction. The gap is the **soft veto**. Of the 241 grants where
#' `operating` and `top` land on different tiers, `top` keeps an arm in **240**,
#' `operating` in **none**, and the query carries a support marker in **none**.
#' That is exactly the `affiliate_suffix` trigger — candidate ends in a support
#' token, query does not — so `top` inherits a veto that `operating` escapes.
#' The policies are not trading accuracy for score; one of them is standing on a
#' veto.
#' @param keep_soft_veto Carry a soft veto from a merged-away member onto the
#'   surviving representative, so the grant stays in review. A soft veto is
#'   npmatch's "do not auto-accept this" signal, and `affiliate_suffix` is the
#'   operating-arm problem in veto form — it fires on exactly the `X FOUNDATION`
#'   candidate when the grant says `X`. Without this, dropping the arm drops the
#'   veto with it. Measured on the 50k run: **71 of 700 promotions** came from
#'   that path, every one of them a case where the cascade ranked the arm first
#'   and the policy overrode both the score and the veto. `FALSE` restores the
#'   older behaviour and recovers those 71 auto-accepts, at the cost of resting
#'   them on a rule validated at 60% on 15 cases.
#' @return A list.
#' @export
pf_dyad_config <- function(tie_band = 0.05, max_band = 25L,
                           use = "substitutable",
                           policy = c("query", "operating", "arm", "top"),
                           keep_soft_veto = TRUE) {
  # Inf is a legitimate way to say "no cap"; as.integer() would turn it into NA.
  max_band <- if (is.finite(max_band)) as.integer(max_band) else Inf
  list(tie_band = tie_band, max_band = max_band, use = use,
       policy = match.arg(policy), keep_soft_veto = keep_soft_veto)
}

#' Attach dyad context to a match result
#'
#' Adds `dyad_id`, `dyad_class` and `dyad_alt_ein` to every result row whose
#' chosen EIN has a disclosed partner among that grant's own candidates. Makes
#' no selection changes — use it when you want funder-to-recipient rollups to be
#' correct regardless of which member the cascade picked, which is the use this
#' data unambiguously supports.
#'
#' @param x A `pf_match` from [pf_match_grants()].
#' @param dyads Output of [pf_build_dyads()].
#' @param config Output of [pf_dyad_config()].
#' @return `x` with three columns added to `x$result`.
#' @export
pf_dyad_annotate <- function(x, dyads, config = pf_dyad_config()) {
  stopifnot(inherits(x, "pf_match"))
  res <- as.data.frame(x$result)
  res$dyad_id <- NA_character_; res$dyad_class <- NA_character_
  res$dyad_alt_ein <- NA_character_; res$dyad_alt_name <- NA_character_
  cand <- .pf_dyad_band(x, config)
  if (!nrow(cand)) return(structure(
    .pf_setresult(x, .pf_reclass(res, x$result)), class = "pf_match"))
  pick <- .pf_ein(res$overall_ein)
  cand[, pick_ein := pick[match(.id, res$.id)]]
  hit <- cand[!is.na(pick_ein) & ein != pick_ein]
  if (!nrow(hit)) return(structure(
    .pf_setresult(x, .pf_reclass(res, x$result)), class = "pf_match"))
  hit[, cls := pf_dyad_lookup(dyads, pick_ein, ein)]
  hit[, did := pf_dyad_lookup(dyads, pick_ein, ein, "id")]
  hit <- hit[!is.na(cls)]
  if (!nrow(hit)) return(structure(
    .pf_setresult(x, .pf_reclass(res, x$result)), class = "pf_match"))
  # A chosen EIN may have more than one disclosed partner in the list. Report a
  # substitutable partner ahead of a merely related one, then the higher score.
  hit[, .pri := data.table::fifelse(cls == "substitutable", 0L, 1L)]
  data.table::setorderv(hit, c(".id", ".pri", "score"), c(1L, 1L, -1L))
  hit <- hit[!duplicated(hit$.id)]
  i <- match(hit$.id, res$.id)
  res$dyad_id[i] <- hit$did; res$dyad_class[i] <- hit$cls
  res$dyad_alt_ein[i] <- hit$ein; res$dyad_alt_name[i] <- hit$name_y
  message(sprintf("pf_dyad_annotate: %d results carry a dyad partner (%s)",
                  nrow(hit), paste(sprintf("%s=%d", names(table(hit$cls)),
                                           table(hit$cls)), collapse = " ")))
  structure(.pf_setresult(x, .pf_reclass(res, x$result)),
            class = "pf_match")
}

#' Collapse substitutable candidates before selection
#'
#' For every grant whose tie band holds two or more candidates joined by a
#' disclosed dyad, merges them into one and re-picks by `config$policy` instead
#' of by score. **Scores are not modified**, so the YES / MAYBE / NO thresholds
#' keep their meaning; what changes is which member of a merged pair is reported
#' and how many distinct bodies remain in contention.
#'
#' Grouping is resolved **within one grant's candidate list only**. A dyad
#' between two candidates merges them; a dyad from a candidate to some third EIN
#' that is not a candidate here does nothing. That restriction is what keeps this
#' from becoming the 67,000-EIN transitive closure described in [pf_dyads].
#'
#' @section Collapse before selection, not after:
#' With `rescore = TRUE` (the default) the losing members of each merged group
#' are **removed from the scored pair set and the selection is re-run**. That is
#' the whole point: `np_tier()` demotes a YES to MAYBE whenever the margin to the
#' runner-up is below `min_margin`, and when the runner-up is the same body that
#' demotion is spurious. Rewriting the pick after the fact leaves the tier where
#' it was and measures nothing. `rescore = FALSE` keeps the old post-hoc
#' behaviour for comparison.
#'
#' @param x A `pf_match` from [pf_match_grants()].
#' @param dyads Output of [pf_build_dyads()].
#' @param config Output of [pf_dyad_config()].
#' @param np_config The `npmatch` config used to re-select. Defaults to the one
#'   stored on `x`, falling back to `npmatch::np_config()`.
#' @param rescore Re-run selection and tiering on the reduced pair set. See
#'   *Collapse before selection*.
#' @return `x` with the selection recomputed, plus `dyad_collapsed`, `dyad_id`,
#'   `dyad_from_ein`, `dyad_n_before` and `dyad_n_after` recording every merge —
#'   including merges that left the pick unchanged, which are the majority and
#'   are still the point.
#' @export
pf_dyad_collapse <- function(x, dyads, config = pf_dyad_config(),
                             np_config = NULL, rescore = TRUE) {
  stopifnot(inherits(x, "pf_match"))
  res <- as.data.frame(x$result)
  res$dyad_collapsed <- FALSE
  res$dyad_id <- NA_character_; res$dyad_from_ein <- NA_character_
  res$dyad_n_before <- NA_integer_; res$dyad_n_after <- NA_integer_
  done <- function() structure(
    .pf_setresult(x, .pf_reclass(res, x$result)), class = "pf_match")

  cand <- .pf_dyad_band(x, config, report = TRUE)
  if (!nrow(cand)) return(done())

  # Row identity is carried in a column, not in position: `cand` is re-sorted
  # below and every later reference resolves through `.rowid`.
  cand[, .rowid := .I]

  # every within-grant candidate pair joined by a usable dyad
  ed <- cand[, {
    if (.N < 2L) NULL else {
      cb <- utils::combn(.N, 2L)
      list(i = .rowid[cb[1L, ]], j = .rowid[cb[2L, ]])
    }
  }, by = .id]
  if (!nrow(ed)) return(done())
  ed[, cls := pf_dyad_lookup(dyads, cand$ein[i], cand$ein[j])]
  ed[, did := pf_dyad_lookup(dyads, cand$ein[i], cand$ein[j], "id")]
  ed <- ed[cls %chin% config$use]
  if (!nrow(ed)) return(done())

  # union-find over candidate row ids, so a group can never leave the grant
  parent <- seq_len(nrow(cand))
  find <- function(k) { while (parent[k] != k) { parent[k] <<- parent[parent[k]]; k <- parent[k] }; k }
  for (r in seq_len(nrow(ed))) {
    ri <- find(ed$i[r]); rj <- find(ed$j[r]); if (ri != rj) parent[rj] <- ri
  }
  cand[, grp := vapply(.rowid, find, 1L)]
  cand[, n_before := .N, by = .id]
  cand[, n_after  := data.table::uniqueN(grp), by = .id]
  cand[, arm := pf_is_arm(name_y)]
  cand[, gsz := .N, by = list(.id, grp)]

  # pick a representative inside each merged group by the stated policy
  # The grant record's OWN name is evidence about which member was meant, and it
  # is available on every case rather than on the 15 that were adjudicated. When
  # a funder writes "CRAIG HOSPITAL FOUNDATION", reporting CRAIG HOSPITAL
  # contradicts the source document. Measured on the 50k run, policy="operating"
  # does exactly that on 134 of the 155 collapsed grants whose recorded name
  # carries a support marker (86%).
  qn <- if (!is.null(x$grants$recip_name) && !is.null(x$grants$grant_id))
          x$grants$recip_name[match(cand$.id, x$grants$grant_id)] else NA_character_
  cand[, q_arm := if (all(is.na(qn))) NA else pf_is_arm(qn)]

  rep_of <- function(rowid, arm, score, want_arm) {
    if (length(rowid) == 1L) return(rowid[1L])
    o <- switch(config$policy,
                # follow the query when it says which member it means, and fall
                # back to the operating entity when it is silent
                query     = if (isTRUE(want_arm)) order(!arm, -score)
                            else order(arm, -score),
                operating = order(arm, -score),
                arm       = order(!arm, -score),
                top       = order(-score))
    rowid[o[1L]]
  }
  keep <- cand[gsz > 1L, list(rep = rep_of(.rowid, arm, score, q_arm[1L])),
               by = list(.id, grp)]
  if (!nrow(keep)) return(done())

  # the group containing the candidate the cascade currently ranks first
  ord  <- cand[order(.id, -score)]
  topr <- ord[!duplicated(ord$.id), list(.id, grp, top_row = .rowid,
                                         n_before, n_after)]
  win  <- merge(topr, keep, by = c(".id", "grp"))[rep != top_row]
  merged_ids <- unique(keep$.id)

  # one dyad id per grant, for the audit trail
  edk <- ed[!duplicated(ed$.id), list(.id, did)]

  mi <- match(merged_ids, res$.id)
  nb <- topr[match(merged_ids, topr$.id)]
  ok <- !is.na(mi)
  res$dyad_collapsed[mi[ok]] <- TRUE
  res$dyad_n_before[mi[ok]]  <- nb$n_before[ok]
  res$dyad_n_after[mi[ok]]   <- nb$n_after[ok]
  res$dyad_id[mi[ok]]        <- edk$did[match(merged_ids[ok], edk$.id)]

  # the losing members of every merged group, keyed for removal
  losers <- cand[gsz > 1L][!(.rowid %in% keep$rep)]
  drop_key <- paste(losers$.id, losers$.ein)

  if (!rescore) {
    if (nrow(win)) {
      wi <- match(win$.id, res$.id)
      r  <- match(win$rep, cand$.rowid)
      res$dyad_from_ein[wi]  <- res$overall_ein[wi]
      res$overall_ein[wi]    <- cand$.ein[r]
      res$overall_name_y[wi] <- cand$name_y[r]
      res$overall_score[wi]  <- cand$score[r]
    }
    message(sprintf(
      "pf_dyad_collapse: %d grants merged (%d candidates -> %d groups), %d picks changed",
      length(merged_ids), sum(nb$n_before), sum(nb$n_after), nrow(win)))
    return(done())
  }

  ## ------------------------------------------- collapse before re-selecting
  if (is.null(np_config))
    np_config <- if (!is.null(x$config)) x$config else npmatch::np_config()
  pr0  <- attr(x$result, "pairs")
  pr0df <- as.data.frame(pr0)
  pk0   <- paste(pr0df$.id, pr0df$.ein)
  keep_rows <- !(pk0 %chin% drop_key)
  pr1  <- pr0[keep_rows, , drop = FALSE]
  for (a in setdiff(names(attributes(pr0)), c("names", "row.names", "class")))
    attr(pr1, a) <- attr(pr0, a)
  class(pr1) <- class(pr0)

  # A soft veto on a DROPPED member would otherwise vanish with it, and a soft
  # veto is npmatch's "do not auto-accept this" signal. Measured on the 50k run,
  # 71 of 700 promotions came from exactly this: the cascade ranked the ARM
  # first, `affiliate_suffix` soft-vetoed it, and the policy overrode both. Those
  # promotions rest on the ordering policy alone -- 60% on 15 adjudicated cases
  # -- against a score and a veto that both said otherwise. Carry the veto onto
  # the representative so the grant stays in review.
  # Only a veto that was actually HOLDING the grant counts, and "holding" has a
  # precise meaning: the veto sat on the candidate np_select() had ALREADY
  # chosen, so the grant was in MAYBE because of it. Two weaker predicates were
  # tried on the 50k run and both were wrong:
  #
  #   any dropped member vetoed  -> 700 promotions fall to 249. In 380 of those
  #     the cascade had already picked the un-vetoed operating entity; the veto
  #     was about a candidate that was never going to be reported.
  #   top of the band vetoed     -> falls to 394, and 6 still leak. The band's
  #     top row is not the pick: np_select() resolves ties through
  #     .np_overall_summary(), not by raw max score.
  #
  # So read the pick off the pre-collapse result rather than reconstructing it.
  if (isTRUE(config$keep_soft_veto) && !is.null(pr0df$veto_soft) &&
      !is.null(res$overall_veto_soft)) {
    held <- res$.id[res$overall_veto_soft %in% TRUE]
    pick_key <- paste(res$.id, res$overall_ein)[res$overall_veto_soft %in% TRUE]
    sv <- (pr0df$veto_soft %in% TRUE) & (pr0df$.id %chin% held) &
          (pk0 %chin% pick_key)
    if (any(sv & !keep_rows)) {
      # Carry the ORIGINAL reason across, not just a flag: the vetoed candidate
      # is about to leave the pair set, so this is the only remaining record of
      # why the grant is being held.
      lost <- pr0df[sv & !keep_rows, , drop = FALSE]
      why  <- if (!is.null(lost$veto_soft_reason)) lost$veto_soft_reason
              else rep(NA_character_, nrow(lost))
      first_why <- tapply(why, lost$.id, function(v) {
        v <- v[!is.na(v)]; if (length(v)) v[1L] else NA_character_
      })
      dropped_sv <- names(first_why)
      pr1df <- as.data.frame(pr1)
      hit <- pr1df$.id %chin% dropped_sv
      if (any(hit)) {
        pr1$veto_soft[hit] <- TRUE
        if (!is.null(pr1$veto_soft_reason)) {
          inherited <- unname(first_why[pr1df$.id[hit]])
          pr1$veto_soft_reason[hit] <- ifelse(
            is.na(pr1df$veto_soft_reason[hit]),
            paste0("dyad_collapse: inherited from a merged member",
                   ifelse(is.na(inherited), "", paste0(" (", inherited, ")"))),
            pr1df$veto_soft_reason[hit])
        }
      }
    }
  }

  new <- npmatch::np_tier(npmatch::np_select(pr1, np_config), np_config)
  new <- as.data.frame(new)
  # carry the audit columns onto the re-selected result
  j <- match(new$.id, res$.id)
  for (col in c("dyad_collapsed", "dyad_id", "dyad_n_before", "dyad_n_after"))
    new[[col]] <- res[[col]][j]
  new$dyad_collapsed[is.na(new$dyad_collapsed)] <- FALSE
  new$dyad_from_ein <- NA_character_
  was <- res$overall_ein[j]
  chg <- !is.na(j) & new$dyad_collapsed &
         !is.na(was) & !is.na(new$overall_ein) & new$overall_ein != was
  chg[is.na(chg)] <- FALSE
  new$dyad_from_ein[chg] <- was[chg]

  before <- table(factor(res$tier[j], levels = c("YES", "MAYBE", "NO")))
  after  <- table(factor(new$tier,    levels = c("YES", "MAYBE", "NO")))
  message(sprintf(
    "pf_dyad_collapse: %d grants merged (%d candidates -> %d groups), %d rows dropped, %d picks changed",
    length(merged_ids), sum(nb$n_before, na.rm = TRUE), sum(nb$n_after, na.rm = TRUE),
    sum(!keep_rows), sum(chg, na.rm = TRUE)))
  message(sprintf("  tiers: %s", paste(sprintf("%s %d->%d", names(before),
                                               as.integer(before), as.integer(after)),
                                       collapse = "  ")))
  # `pairs` must be attached AFTER .pf_reclass(), not before: .pf_reclass copies
  # every attribute off the OLD result, so setting it first means the reduced
  # pair set is silently overwritten by the full one. The tiers would still be
  # right -- they are computed from pr1 above -- but the returned object would
  # carry candidates that were merged away, and pf_candidate_frame() builds the
  # review sheet from this attribute, so a reviewer would be shown a contender
  # the collapse had already resolved.
  out <- .pf_reclass(new, x$result)
  attr(out, "pairs") <- pr1
  structure(.pf_setresult(x, out), class = "pf_match")
}

# The contending candidates for every grant with 2+ inside the tie band, capped
# at config$max_band by score. The cap is load-bearing: see pf_dyad_config().
.pf_dyad_band <- function(x, config, report = FALSE) {
  pr <- data.table::as.data.table(attr(x$result, "pairs"))
  if (!nrow(pr)) return(pr)
  if (!is.null(pr$veto)) pr <- pr[!(pr$veto %in% TRUE)]
  pr[, ein := .pf_ein(.ein)]
  pr <- pr[!is.na(ein)]
  pr <- unique(pr, by = c(".id", "ein"))
  pr[, .top := max(score), by = .id]
  pr <- pr[score >= .top - config$tie_band]
  cap <- config$max_band
  if (!is.null(cap) && is.finite(cap)) {
    if (report) {
      big <- pr[, list(n = .N), by = .id][n > cap]
      if (nrow(big))
        message(sprintf(
          "pf_dyad_collapse: %d grants have more than %d candidates in the band (max %d); capped by score",
          nrow(big), cap, max(big$n)))
    }
    data.table::setorder(pr, .id, -score)
    pr <- pr[, utils::head(.SD, cap), by = .id]
  }
  pr[, if (.N >= 2L) .SD, by = .id]
}

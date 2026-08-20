#' Affiliated organizations: operating entities and their fundraising arms
#'
#' The single largest identified failure mode in the MAYBE tier is a candidate
#' list holding both an operating organization and its own fundraising arm —
#' `EAGLE RANCH` and `EAGLE RANCH FOUNDATION`, `KANSAS FOOD BANK WAREHOUSE` and
#' `KANSAS FOOD BANK FOUNDATION`. Two real EINs, one body, and nothing in the
#' name or the address separates them. Measured on 15 adjudicated cases the
#' cascade ranks the correct member first **27%** of the time — worse than
#' chance, because the arm's name is usually the longer, more distinctive
#' string and so scores better.
#'
#' This module treats the pair as one entity. It builds an EIN-to-EIN link
#' table from three independent disclosures, groups co-located same-core
#' candidates under a joint id, and orders the members by a stated policy rather
#' than by a name score.
#'
#' @section The three sources, and what each actually covers:
#' \describe{
#'   \item{Schedule A Part I line 12 (`SA-P01-T01`)}{A 509(a)(3) supporting
#'     organization lists the organizations it supports, by name and EIN. This
#'     is the only source that states **direction**, and on 276 pairs it agrees
#'     with the name heuristic (the `... FOUNDATION` row is the supporter) 271
#'     times. It exists only for full-990 filers that are supporting
#'     organizations, and the supported-org EIN is blank on 49% of rows.}
#'   \item{Schedule R Part II (`SR-P02-T01`)}{Related tax-exempt organizations.
#'     Undirected in practice but far better populated — the related EIN is
#'     present on 97% of rows — and it covers pairs Schedule A never sees,
#'     because it does not require 509(a)(3) status.}
#'   \item{BMF group exemption}{**Not** the right tool for this relation. The
#'     `affiliation_code` and `group_exemption_number` fields describe group
#'     *rulings* — Lions Clubs, PTAs, BSA councils — i.e. federated siblings,
#'     not parent/arm pairs. `0000` means no group ruling and covers 1.52M of
#'     1.92M BMF rows; treating it as a match key produces a spurious 74% link
#'     rate. Use it for the sibling case only, via [pf_group_siblings()].}
#' }
#'
#' On 927 name-detected pairs drawn from the MAYBE tier, Schedule A links 30%,
#' Schedule R 46%, and either 49%. Restricted to pairs in the same city those
#' rise to 39% / 60% / 64% — the monotone rise being the evidence that the
#' geography gate removes false pairs rather than real ones. The residual is
#' mostly non-filing: for 64% of unlinked pairs neither party files a schedule
#' at all, which is what you would expect of public universities, school
#' districts and 990-EZ filers.
#'
#' @name pf_affiliation
NULL

.pf_ARM_TAIL <- paste0("(FOUNDATION|FOUND|ENDOWMENT|FUND|TRUST|AUXILIARY|GUILD|",
                       "BOOSTERS|BOOSTER CLUB|ALUMNI ASSOCIATION|ASSOCIATES|PARTNERS)")
.pf_ARM_HEAD <- "(FRIENDS OF( THE)?|SUPPORTERS OF|ASSOCIATES OF)"
.pf_LEGAL    <- "( INC| INCORPORATED| CORP| CORPORATION| CO| LTD| LLC)"

.pf_aff_norm <- function(x) {
  x <- toupper(as.character(x)); x[is.na(x)] <- ""
  x <- gsub("[^A-Z0-9 ]", " ", x)
  x <- gsub("\\bTHE\\b", " ", x)
  trimws(gsub(" +", " ", x))
}

#' Is this name a fundraising or support arm?
#'
#' Detects the arm by name shape alone: a trailing support marker (`FOUNDATION`,
#' `ENDOWMENT`, `AUXILIARY`, `ALUMNI ASSOCIATION`, ...) or a leading one
#' (`FRIENDS OF`). Checked against Schedule A, the shape is right 271 times in
#' 276 — the five exceptions are bodies legally named `... FOUNDATION` that are
#' themselves the operating entity and are supported by a differently-named arm.
#'
#' @param x Character vector of organization names.
#' @return Logical vector.
#' @seealso [pf_arm_core()], [pf_cluster_arms()]
#' @export
pf_is_arm <- function(x) {
  n <- .pf_aff_norm(x)
  grepl(paste0(" ", .pf_ARM_TAIL, "$"), n) | grepl(paste0("^", .pf_ARM_HEAD, " "), n)
}

#' The shared core of an organization name
#'
#' Strips legal suffixes and any arm marker, so that `FRIENDS OF THE RACINE
#' PUBLIC LIBRARY` and `RACINE PUBLIC LIBRARY` reduce to the same string. Two
#' candidates sharing a core are *candidates* for being one body; geography
#' decides it (see [pf_cluster_arms()]).
#'
#' @param x Character vector of organization names.
#' @return Character vector of cores.
#' @export
pf_arm_core <- function(x) {
  n <- .pf_aff_norm(x)
  n <- trimws(gsub(paste0(.pf_LEGAL, "+$"), "", n))
  n <- sub(paste0("^", .pf_ARM_HEAD, " "), "", n)
  n <- sub(paste0(" ", .pf_ARM_TAIL, "$"), "", n)
  trimws(gsub(" +", " ", n))
}

#' Build the EIN-to-EIN affiliation link table
#'
#' Reads the Schedule A and Schedule R e-file tables and returns one row per
#' disclosed relationship. Both tables are available per tax year from the NCCS
#' e-file catalogue; 2022 is the development vintage.
#'
#' @param sched_a Path to `SA-P01-T01-PUBLIC-CHARITY-STATUS-<year>.CSV`, or the
#'   table itself. `NULL` to skip.
#' @param sched_r Path to `SR-P02-T01-ID-RLTD-TAX-EXEMPED-ORGS-<year>.CSV`, or
#'   the table itself. `NULL` to skip.
#' @param cache Path to cache the result as `.rds`. `NULL` to skip.
#' @return A `data.table` with `a`, `b`, `src` (`SCHED_A` / `SCHED_R`) and `rel`
#'   (`a_supports_b` / `a_related_b`), plus an `undirected` attribute holding the
#'   symmetrised form for lookup.
#' @export
pf_build_affiliation_links <- function(sched_a = NULL, sched_r = NULL, cache = NULL) {
  if (!is.null(cache) && file.exists(cache)) return(readRDS(cache))
  rd <- function(p, cols) {
    if (is.null(p)) return(NULL)
    if (is.character(p) && length(p) == 1L)
      p <- data.table::fread(p, colClasses = "character", showProgress = FALSE,
                             select = cols)
    data.table::as.data.table(p)
  }
  out <- list()
  a <- rd(sched_a, c("ORG_EIN", "SA_01_PCSTAT_ORG_EIN"))
  if (!is.null(a)) {
    a[, c("a", "b") := list(.pf_ein(ORG_EIN), .pf_ein(SA_01_PCSTAT_ORG_EIN))]
    out$a <- unique(a[!is.na(a) & !is.na(b) & a != b,
                      list(a, b, src = "SCHED_A", rel = "a_supports_b")])
  }
  r <- rd(sched_r, c("ORG_EIN", "SR_02_RLTD_ORG_EIN"))
  if (!is.null(r)) {
    r[, c("a", "b") := list(.pf_ein(ORG_EIN), .pf_ein(SR_02_RLTD_ORG_EIN))]
    out$r <- unique(r[!is.na(a) & !is.na(b) & a != b,
                      list(a, b, src = "SCHED_R", rel = "a_related_b")])
  }
  links <- data.table::rbindlist(out, use.names = TRUE)
  und <- unique(data.table::rbindlist(list(
    links[, list(x = a, y = b, src, rel)],
    links[, list(x = b, y = a, src,
                 rel = data.table::fifelse(rel == "a_supports_b", "b_supports_a",
                                           "a_related_b"))])))
  data.table::setkeyv(und, c("x", "y"))
  attr(links, "undirected") <- und
  if (!is.null(cache)) saveRDS(links, cache, compress = FALSE)
  links[]
}

#' Group a candidate list into operating/arm clusters
#'
#' For each query, finds candidate pairs that share a name core, sit in the same
#' state, and split into one arm and one non-arm. Each such pair gets a
#' `joint_id`; the disclosure sources, when supplied, are attached as evidence.
#'
#' Roughly **13%** of MAYBE grants contain such a pair. Collapsing the pair
#' removes the runner-up from the tie band, which converts
#' `MAYBE-because-two-candidates-tie` into a single-body decision.
#'
#' @param cand A candidate frame, one row per query/candidate pair, with columns
#'   named by `id`, `ein`, `name` and `state`.
#' @param id,ein,name,state Column names in `cand`.
#' @param links Optional output of [pf_build_affiliation_links()].
#' @param require_city Optional column name; when given, the pair must also
#'   agree on it. Tighter, and disclosure rates are higher on the subset, but it
#'   drops arms that use a lockbox or a separate mailing address.
#' @return A `data.table`, one row per detected cluster, with `joint_id`, the
#'   two EINs and names, their ranks in the candidate list, `evidence`
#'   (`SCHED_A` / `SCHED_R` / `NAME_GEO_ONLY`) and `direction`.
#' @seealso [pf_arm_order()] for choosing between the members.
#' @export
pf_cluster_arms <- function(cand, id = "id", ein = "ein", name = "name",
                            state = "state", links = NULL, require_city = NULL) {
  d <- data.table::as.data.table(cand)
  d <- data.table::data.table(
    .id  = as.character(d[[id]]), .ein = .pf_ein(d[[ein]]),
    .nm  = as.character(d[[name]]), .st = as.character(d[[state]]),
    .city = if (is.null(require_city)) NA_character_ else as.character(d[[require_city]]))
  d[, .rank := seq_len(.N), by = .id]
  d[, c("arm", "core") := list(pf_is_arm(.nm), pf_arm_core(.nm))]
  d <- d[nchar(core) >= 8L & lengths(strsplit(core, " ")) >= 2L]

  g <- d[, list(n_arm = sum(arm), n_op = sum(!arm),
                arm_ein = .ein[arm][1], op_ein = .ein[!arm][1],
                arm_name = .nm[arm][1],  op_name = .nm[!arm][1],
                arm_rank = .rank[arm][1], op_rank = .rank[!arm][1],
                arm_st = .st[arm][1], op_st = .st[!arm][1],
                arm_city = .city[arm][1], op_city = .city[!arm][1]),
         by = list(.id, core)]
  g <- g[n_arm >= 1L & n_op >= 1L & !is.na(arm_ein) & !is.na(op_ein) &
         !is.na(arm_st) & !is.na(op_st) & arm_st == op_st]
  if (!is.null(require_city))
    g <- g[!is.na(arm_city) & arm_city == op_city]
  if (!nrow(g)) return(g[0])

  g[, evidence := "NAME_GEO_ONLY"][, direction := "undirected"]
  if (!is.null(links)) {
    L <- data.table::as.data.table(links)
    fwd <- paste(g$arm_ein, g$op_ein) %in% paste(L[src == "SCHED_A"]$a, L[src == "SCHED_A"]$b)
    rev <- paste(g$op_ein, g$arm_ein) %in% paste(L[src == "SCHED_A"]$a, L[src == "SCHED_A"]$b)
    srr <- paste(g$arm_ein, g$op_ein) %in% paste(L[src == "SCHED_R"]$a, L[src == "SCHED_R"]$b) |
           paste(g$op_ein, g$arm_ein) %in% paste(L[src == "SCHED_R"]$a, L[src == "SCHED_R"]$b)
    g[, evidence := data.table::fifelse(fwd | rev, "SCHED_A",
                     data.table::fifelse(srr, "SCHED_R", "NAME_GEO_ONLY"))]
    g[, direction := data.table::fifelse(fwd, "arm_supports_op",
                      data.table::fifelse(rev, "op_supports_arm", "undirected"))]
  }
  g[, joint_id := paste0("PFJ", formatC(.GRP, width = 7, flag = "0")),
    by = list(pmin(arm_ein, op_ein), pmax(arm_ein, op_ein))]
  data.table::setnames(g, ".id", "id")
  g[]
}


#' Schedule A Part I public-charity status flags
#'
#' The Part I checkbox is a status the filer declares about itself, which makes
#' it stronger evidence than anything inferred from a name. Two boxes matter
#' here:
#'
#' \describe{
#'   \item{Line 5 (`govt_college`)}{170(b)(1)(A)(iv) - "operated for the benefit
#'     of a college or university owned or operated by a governmental unit". This
#'     is the state university foundation, and it identifies the population where
#'     no affiliation disclosure can ever exist, because the parent is a
#'     government agency rather than a related nonprofit. 2,105 EINs nationally
#'     in 2022; of the MAYBE-tier arms that tick it, 92% could not be linked to a
#'     parent by Schedule A, Schedule R or the BMF.}
#'   \item{Line 12 (`support_org`)}{509(a)(3). The box whose accompanying table
#'     feeds [pf_build_affiliation_links()].}
#' }
#'
#' Line 4 (`med_research`) is included for completeness and is close to useless
#' for this purpose: it covers medical *research* organizations operated in
#' conjunction with a hospital, only 384 filers nationally, and none of the 927
#' arm pairs measured. Hospital arms tick line 12 or line 7 instead.
#'
#' @param sched_a_p1 Path to `SA-P01-T00-PUBLIC-CHARITY-STATUS-<year>.CSV`, or
#'   the table itself.
#' @return A `data.table` keyed by `ein` with logical `govt_college`,
#'   `support_org`, `med_research`, `hospital`, `pub_support`, plus
#'   `hospital_name` where line 4 named one.
#' @export
pf_schedule_a_status <- function(sched_a_p1) {
  cols <- c("ORG_EIN", "SA_01_PCSTAT_COLLEGE_BEN_X", "SA_01_PCSTAT_SUPPORT_ORG_X",
            "SA_01_PCSTAT_MEDICAL_RSRCH_X", "SA_01_PCSTAT_HOSPITAL_X",
            "SA_01_PCSTAT_PUB_SUPPORT_X", "SA_01_PCSTAT_HOSPITAL_NAME_L1")
  d <- sched_a_p1
  if (is.character(d) && length(d) == 1L)
    d <- data.table::fread(d, colClasses = "character", showProgress = FALSE,
                           select = cols)
  d <- data.table::as.data.table(d)
  data.table::setnames(d, cols, c("ein", "govt_college", "support_org",
                                  "med_research", "hospital", "pub_support",
                                  "hospital_name"), skip_absent = TRUE)
  tx <- function(v) !is.na(v) & toupper(trimws(v)) %in% c("X", "1", "TRUE", "Y")
  for (j in c("govt_college", "support_org", "med_research", "hospital",
              "pub_support"))
    if (j %in% names(d)) data.table::set(d, j = j, value = tx(d[[j]]))
  d[, ein := .pf_ein(ein)]
  d <- unique(d[!is.na(ein)], by = "ein")
  data.table::setkeyv(d, "ein")
  d[]
}

#' Order the members of an operating/arm cluster
#'
#' Returns the two EINs in best-guess order. The default policy is **operating
#' entity first**, switching to the arm when the grant purpose names a
#' restricted gift — a scholarship, an endowment, a capital campaign — because
#' those are legally the arm's job.
#'
#' @section What is and is not established:
#' On 15 adjudicated cases containing a co-located arm pair, the operating
#' entity was the recipient 9 times (60%, 95% CI 32–84%) and the arm 6 times.
#' The purpose-conditional rule scores 67%, the flat rule 60%, and **the current
#' cascade ranks the correct member first only 27% of the time**. The last of
#' those is the finding that justifies acting: the existing behaviour is
#' anti-correlated with the answer, and either policy is a large improvement.
#' The 60-versus-67 gap is one case wide and settles nothing — only one
#' adjudicated case had a restricted-gift purpose. Do not read the conditional
#' rule as validated; it is the hypothesis a larger labelling round should test.
#'
#' @param cluster Output of [pf_cluster_arms()].
#' @param purpose Character vector of grant purposes, aligned to `cluster` rows.
#' @param policy `"purpose"` (default) or `"operating"` for the flat rule.
#' @param sa_status Optional output of [pf_schedule_a_status()]. When given, any arm ticking Schedule A line 5 is ordered first regardless of purpose.
#' @return `cluster` with `first_ein`, `second_ein` and `order_reason` added.
#' @export
pf_arm_order <- function(cluster, purpose = NULL, policy = c("purpose", "operating"), sa_status = NULL) {
  policy <- match.arg(policy)
  g <- data.table::copy(data.table::as.data.table(cluster))
  restricted <- rep(FALSE, nrow(g))
  if (policy == "purpose" && !is.null(purpose))
    restricted <- grepl(paste0("scholarship|endowment|endowed|annual fund|",
                               "capital campaign|bequest|memorial fund"),
                        purpose, ignore.case = TRUE)
  # A line-5 arm's parent is a governmental unit, which cannot itself hold the
  # charitable gift. This is a legal fact, not a preference, so it overrides the
  # purpose rule in both directions.
  govt <- rep(FALSE, nrow(g))
  if (!is.null(sa_status)) {
    s <- data.table::as.data.table(sa_status)
    govt <- g$arm_ein %in% s[govt_college == TRUE]$ein
  }
  restricted <- restricted | govt
  g[, first_ein  := data.table::fifelse(restricted, arm_ein, op_ein)]
  g[, second_ein := data.table::fifelse(restricted, op_ein, arm_ein)]
  g[, order_reason := data.table::fifelse(restricted,
      "purpose names a restricted gift; the arm administers those",
      "default: the operating entity receives unrestricted support")]
  g[govt, order_reason := paste("Schedule A line 5: the parent is a governmental",
                                "unit and cannot hold the gift; the arm did")]
  g[]
}

#' Federated siblings from the BMF group exemption
#'
#' The other clustering case, and a genuinely different one: chapters under a
#' single group ruling — Lions Clubs, PTAs, BSA councils, Knights of Columbus.
#' Here `group_exemption_number` *is* the right key, provided the `0000`
#' sentinel is excluded. Siblings are not substitutes for one another, so a
#' cluster here is a warning that the candidate list holds several
#' interchangeable-looking chapters, not an invitation to collapse them.
#'
#' @param bmf The processed BMF (path or data frame).
#' @param eins Optional character vector of EINs to restrict to.
#' @return A `data.table` of `ein`, `group_exemption_number`, `affiliation_code`
#'   and `n_members`, for group numbers other than the `0000` sentinel.
#' @export
pf_group_siblings <- function(bmf, eins = NULL) {
  if (is.character(bmf) && length(bmf) == 1L)
    bmf <- data.table::fread(bmf, colClasses = "character", showProgress = FALSE,
                             select = c("ein", "group_exemption_number",
                                        "affiliation_code"))
  b <- data.table::as.data.table(bmf)
  b[, ein := .pf_ein(ein)]
  b <- b[!is.na(ein) & !is.na(group_exemption_number) &
         nzchar(group_exemption_number) & !grepl("^0+$", group_exemption_number)]
  if (!is.null(eins)) b <- b[ein %in% .pf_ein(eins)]
  b[, n_members := .N, by = group_exemption_number]
  unique(b[, list(ein, group_exemption_number, affiliation_code, n_members)])
}

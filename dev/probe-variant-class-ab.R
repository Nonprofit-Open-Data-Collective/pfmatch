#!/usr/bin/env Rscript
# ============================================================================
# probe-variant-class-ab.R -- decompose the augmented reference's "+43 YES".
#
# dev/REF-PERFORMANCE.md records the augmented reference gaining +43 YES / +10
# MAYBE over the plain BMF on 1,000 identities. That is a NET figure, and
# matchdb/dev/PLAN.md 6a argues it hides two opposing effects:
#
#   gained   an alias row matches a grant the legal name could not
#   lost     np_name_freq() is a raw COUNT, so adding 2M alias rows pushes
#            names past distinct_name_maxfreq (3) and silently switches OFF
#            the distinctive-name promotion that was carrying them
#
# And matchdb/dev/PLAN.md 6b argues a third effect is mixed in: pf_bmf_augment()
# writes aliases into org_name_join, the column np_map_bmf() maps to `name`, so
# a cloned alias row reads as name_ver_y == "MAIN" and is eligible for a
# promotion whose stated justification is "this exact LEGAL name is rare".
#
# Three arms, same 1k query throughout:
#
#   A  plain unified BMF
#   B  augmented unified BMF                    (what ships today)
#   C  augmented, promotion gated to legal rows (the proposed fix)
#
# Arm C needs no npmatch change. distinct_name_main_only already gates the
# promotion on name_ver_y == "MAIN"; marking alias rows as anything else
# disables it for exactly those rows, which IS variant-class gating. The gate is
# applied inside a wrapper around .np_hier_score() on a local copy of `pairs`,
# so npmatch's own scoring logic is used unmodified and nothing leaks.
#
# MEASUREMENT ONLY. Nothing here changes a shipped default.
#
#   PF_AB_ARM=A|B|C  Rscript dev/probe-variant-class-ab.R
#   PF_AB_ARM=cmp    Rscript dev/probe-variant-class-ab.R   (after all three)
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)

PF  <- Sys.getenv("PFMATCH_DIR", ".")
ARM <- Sys.getenv("PF_AB_ARM", "A")
DD  <- file.path(PF, "data-dev")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")

suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

# Four arms, not three. REF-PERFORMANCE.md's "+43 YES" compares the MONTHLY
# ACTIVE BMF against the augmented unified reference -- so it spans two
# independent changes at once, the inactive-EIN tranche AND the Schedule I
# aliases, and reports them as one number. Arm D lets the two be separated.
#
#   D  monthly active BMF          1,924,822
#   A  unified (active+inactive)   3,687,435   D->A = the inactive tranche
#   B  augmented unified           3,880,431   A->B = the aliases
#   C  augmented, legal-gated      3,880,431   B->C = the promotion fix
#
# Inactive EINs are ~1.76M of the growth; aliases only ~193k. The published
# figure is dominated by a tranche that has nothing to do with aliases.
#
# NOTE the row counts do not match REF-PERFORMANCE.md, which benchmarked an
# augmented reference of 3,891,187 rows. REF-augmented.rds holds 3,880,431 and
# resolves (by row count, at 100% EIN alignment) to BMF-AUGMENTED-unified-fixed.csv
# -- a DIFFERENT artifact from the 3,891,187-row geocoded CSV that produced the
# published number. Three near-identically named augmented CSVs sit in data-dev/
# and the reference bundle records which one it came from nowhere. This probe
# therefore resolves provenance empirically and refuses to run if nothing
# matches; D->B here will not reproduce "+43" exactly, and that is the finding,
# not a defect.
#
REF_D <- file.path(DD, "BMF-REFERENCE-BUNDLE.rds")  # monthly active, verified 1,924,822
REF_A <- file.path(DD, "REF-unified.rds")     # plain unified
REF_B <- file.path(DD, "REF-augmented.rds")   # unified + Schedule I aliases
OUT   <- file.path(DD, sprintf("AB-ARM-%s.rds", ARM))

# ---------------------------------------------------------------------------
# Which augmented CSV produced REF-augmented.rds? Three candidates sit in
# data-dev/ with different row counts and near-identical names -- the exact
# filename-as-provenance problem matchdb exists to end. Resolve it by row count
# rather than by guessing, and refuse to continue if nothing matches.
# ---------------------------------------------------------------------------
.resolve_aug_csv <- function(n_ref) {
  cands <- list.files(DD, pattern = "^BMF-AUGMENTED-.*\\.csv$", full.names = TRUE)
  for (f in cands) {
    n <- as.integer(system2("wc", c("-l", shQuote(f)), stdout = TRUE) |>
                      sub(pattern = " .*$", replacement = "")) - 1L
    say("    %-58s %s rows", basename(f), format(n, big.mark = ","))
    if (identical(n, n_ref)) return(f)
  }
  stop("no augmented CSV matches the reference's ", n_ref, " rows", call. = FALSE)
}

.variant_class <- function(ref) {
  say("  resolving augmented-CSV provenance by row count ...")
  csv <- .resolve_aug_csv(nrow(ref))
  say("  -> %s", basename(csv))
  d <- fread(csv, select = c("ein", "row_source"), colClasses = "character",
             showProgress = FALSE)
  if (nrow(d) != nrow(ref)) stop("row count drifted between count and read")
  # positional alignment is the whole assumption; verify it rather than trust it
  agree <- mean(gsub("[^0-9]", "", d$ein) == gsub("[^0-9]", "", ref$.ein))
  say("  EIN alignment reference vs CSV: %.4f%%", 100 * agree)
  if (agree < 0.9999) stop("reference and CSV rows are not positionally aligned")
  vc <- ifelse(d$row_source == "bmf", "legal", "observed")
  say("  variant classes: %s", paste(sprintf("%s=%s", names(table(vc)),
      format(as.integer(table(vc)), big.mark = ",")), collapse = "  "))
  vc
}

# ---------------------------------------------------------------------------
# Run one arm and reduce it to a compact per-identity frame. The full result
# carries its candidate pairs as an attribute and serializes to ~242 MB
# (dev/DETERMINISM-FINDINGS.md); only the joined summary is kept.
# ---------------------------------------------------------------------------
run_arm <- function(arm) {
  grants <- pf_read_grants(file.path(PF, "inputs"), pattern = "^1k_grants_.*\\.csv$")
  grants <- pf_recover_name_from_street(grants)

  refpath <- switch(arm, D = REF_D, A = REF_A, REF_B)
  say("loading %s ...", basename(refpath))
  t0 <- proc.time()[["elapsed"]]
  ref <- readRDS(refpath)
  say("  %s rows in %.1f s", format(nrow(ref$reference), big.mark = ","),
      proc.time()[["elapsed"]] - t0)

  vc <- if (arm %in% c("A", "D")) rep("legal", nrow(ref$reference))
        else .variant_class(ref$reference)

  if (arm == "C") {
    # Gate the distinctive-name promotion to legal rows, using npmatch's own
    # logic: distinct_name_main_only already requires name_ver_y == "MAIN".
    orig <- npmatch:::.np_hier_score
    patched <- function(pairs, config) {
      iy <- pairs$.y
      if (!is.null(iy)) {
        nonlegal <- !is.na(iy) & vc[iy] != "legal"
        pairs$name_ver_y[nonlegal] <- "OBSERVED"   # local copy; does not leak
      }
      orig(pairs, config)
    }
    assignInNamespace(".np_hier_score", patched, ns = "npmatch")
    say("  ARM C: promotion gated to variant_class == 'legal'")
  }

  passes <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
  say("matching (%d passes) ...", length(passes))
  t0 <- proc.time()[["elapsed"]]
  m <- pf_match_grants(grants, ref, passes = passes, recover = TRUE, verbose = FALSE)
  say("  matched in %.1f s", proc.time()[["elapsed"]] - t0)

  res <- as.data.frame(m$result)
  prs <- as.data.frame(attr(m$result, "pairs"))
  # winning pair per identity, to recover .y / name_freq / name_idf
  k_res <- paste(res$.id, res$overall_ein)
  k_prs <- paste(prs$.id, prs$.ein)
  j <- match(k_res, k_prs)
  out <- data.frame(
    .id            = res$.id,
    tier           = as.character(res$tier),
    ein            = res$overall_ein,
    decision_score = res$decision_score,
    overall_score  = res$overall_score,
    name_ver_y     = res$name_ver_y %||% NA_character_,
    pass           = res$pass,
    y              = prs$.y[j],
    name_freq      = prs$name_freq[j],
    name_idf       = prs$name_idf[j],
    name_score     = prs$name_key[j],
    geo_state      = prs$geo_state[j] %||% NA_real_,
    stringsAsFactors = FALSE)
  out$variant_class <- ifelse(is.na(out$y), NA_character_, vc[out$y])
  out
}
`%||%` <- function(a, b) if (is.null(a)) b else a

if (ARM %in% c("A", "B", "C", "D")) {
  hr(); say("ARM %s", ARM); hr()
  out <- run_arm(ARM)
  saveRDS(out, OUT, compress = FALSE)
  say("wrote %s (%d identities, %.1f MB)", basename(OUT), nrow(out),
      file.size(OUT) / 1e6)
  print(table(out$tier, useNA = "ifany"))
  if (ARM %in% c("B", "C")) print(table(out$tier, out$variant_class, useNA = "ifany"))
  quit(save = "no")
}

# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------
need <- file.path(DD, sprintf("AB-ARM-%s.rds", c("A", "B", "C", "D")))
if (!all(file.exists(need)))
  stop("missing arms: ", paste(basename(need[!file.exists(need)]), collapse = ", "))
A <- readRDS(need[1]); B <- readRDS(need[2])
C <- readRDS(need[3]); D <- readRDS(need[4])

# The arms do NOT share an identity set. The tiered result carries one row per
# identity that drew at least one candidate, and a larger reference draws
# candidates for more of them: 4,733 identities on the monthly BMF against
# 4,774 on the unified. Align on the union and treat an absent identity as
# NONE -- no candidate was ever generated, which is a stronger "not matched"
# than a scored NO. Every comparison below is YES vs not-YES, so the two behave
# identically; keeping them distinct just stops NONE being read as a rejection.
ids <- sort(unique(c(A$.id, B$.id, C$.id, D$.id)))
align <- function(d) {
  i <- match(ids, d$.id)
  out <- d[i, , drop = FALSE]
  out$.id <- ids
  out$tier[is.na(i)] <- "NONE"
  rownames(out) <- NULL
  out
}
say("identity universe: %d (A %d, B %d, C %d, D %d)",
    length(ids), nrow(A), nrow(B), nrow(C), nrow(D))
A <- align(A); B <- align(B); C <- align(C); D <- align(D)

MAXFREQ <- npmatch::np_config()$distinct_name_maxfreq
hr(); say("VARIANT-CLASS A/B  |  %d identities  |  distinct_name_maxfreq = %d",
          nrow(A), MAXFREQ); hr()

tt <- function(x, lbl) {
  t <- table(factor(x$tier, c("YES", "MAYBE", "NO", "NONE")))
  say("  %-34s YES %5d   MAYBE %5d   NO %5d   NONE %4d", lbl,
      t[["YES"]], t[["MAYBE"]], t[["NO"]], t[["NONE"]])
  t
}
tD <- tt(D, "D  monthly active BMF")
tA <- tt(A, "A  unified (active + inactive)")
tB <- tt(B, "B  augmented unified")
tC <- tt(C, "C  augmented, legal-gated")

say("")
say("  the published figure decomposes into three steps, not one:")
say("    D -> A  inactive EIN tranche     %+5d YES  %+5d MAYBE",
    tA[["YES"]] - tD[["YES"]], tA[["MAYBE"]] - tD[["MAYBE"]])
say("    A -> B  Schedule I aliases       %+5d YES  %+5d MAYBE",
    tB[["YES"]] - tA[["YES"]], tB[["MAYBE"]] - tA[["MAYBE"]])
say("    B -> C  legal-gated promotion    %+5d YES  %+5d MAYBE",
    tC[["YES"]] - tB[["YES"]], tC[["MAYBE"]] - tB[["MAYBE"]])
say("    ------------------------------------------------------")
say("    D -> B  as reported in REF-PERFORMANCE.md   %+5d YES  %+5d MAYBE",
    tB[["YES"]] - tD[["YES"]], tB[["MAYBE"]] - tD[["MAYBE"]])

hr(); say("the decomposition"); hr()

yesA <- A$tier == "YES"; yesB <- B$tier == "YES"; yesC <- C$tier == "YES"

# (1) YES gained: not YES in A, YES in B, won on an alias row
gained_alias <- !yesA & yesB & B$variant_class == "observed"
gained_legal <- !yesA & yesB & B$variant_class == "legal"
say("  1. YES gained, won on an ALIAS row          %5d", sum(gained_alias, na.rm = TRUE))
say("     YES gained, won on a LEGAL row           %5d  (blocking/geo side-effects)",
    sum(gained_legal, na.rm = TRUE))

# (2) YES lost: YES in A, not YES in B. Attribute to name_freq inflation where
#     the A-side winner was promotion-eligible and the B-side one is not.
lost <- yesA & !yesB
elig <- function(d) !is.na(d$name_freq) & d$name_freq <= MAXFREQ &
                    !is.na(d$name_score) & d$name_score >= 0.95
lost_freq <- lost & elig(A) & !elig(B)
say("  2. YES lost overall                         %5d", sum(lost, na.rm = TRUE))
say("     ... attributable to name_freq inflation  %5d", sum(lost_freq, na.rm = TRUE))
say("     ... other                                %5d",
    sum(lost & !lost_freq, na.rm = TRUE))

say("")
say("  so the net %+d = %+d gained(alias) %+d gained(legal) %+d lost",
    tB[["YES"]] - tA[["YES"]], sum(gained_alias, na.rm = TRUE),
    sum(gained_legal, na.rm = TRUE), -sum(lost, na.rm = TRUE))

hr(); say("6b: what legal-gating the promotion costs"); hr()
demoted <- yesB & !yesC
say("  3. YES in B, not YES in C                   %5d", sum(demoted, na.rm = TRUE))
say("     ... of which won on an ALIAS row         %5d",
    sum(demoted & B$variant_class == "observed", na.rm = TRUE))
say("     ... of which won on a LEGAL row          %5d  (should be 0)",
    sum(demoted & B$variant_class == "legal", na.rm = TRUE))
# Eligibility is not dependence. A pair meeting the promotion predicate can be
# YES on its own merits -- the promotion only FLOORS the score, so it is a no-op
# whenever the raw score already cleared the tier. In arm C no alias row can be
# promoted at all, so every alias YES here cleared YES without the floor. The
# count is the size of that population, not a failure.
say("  4. alias YES in C meeting the predicate     %5d", sum(
    yesC & C$variant_class == "observed" & C$name_freq <= MAXFREQ &
    C$name_score >= 0.95, na.rm = TRUE))
say("     ... none of which was promoted (arm C excludes alias rows), so these")
say("     cleared YES unaided -- eligibility overstates dependence by ~18x")

say("")
say("  net alias contribution after gating: %+d YES",
    sum(gained_alias, na.rm = TRUE) - sum(demoted & B$variant_class == "observed",
                                          na.rm = TRUE))

hr(); say("promotion-eligible winners by arm and variant class"); hr()
for (nm in c("A", "B", "C")) {
  d <- get(nm)
  e <- elig(d) & d$tier == "YES"
  say("  %s  promotion-eligible YES: %5d   (alias %4d / legal %4d)", nm,
      sum(e, na.rm = TRUE),
      sum(e & d$variant_class == "observed", na.rm = TRUE),
      sum(e & d$variant_class == "legal", na.rm = TRUE))
}

hr()
say("Write-up: dev/VARIANT-CLASS-AB.md")

#!/usr/bin/env Rscript
# ============================================================================
# probe-refit-1k.R -- one 1,000-grant file, profiled end to end, after the
# cascade refinements of 2026-08-21.
#
# WHY THIS RUN EXISTS
#
# BASELINE-2026-08 gates the cascade with `dyads = NULL`: build-baseline.R calls
# pf_match_grants() directly, and pf_match_grants() has no `dyads` argument. But
# the last two code commits changed *only* the dyad path:
#
#   0b28fd7  keep_soft_veto, and the modifyList() bug that silently discarded
#            the collapse's reduced `pairs` attribute
#   046a7b5  the default collapse policy moved "operating" -> "query"
#
# Both were measured by re-scoring a saved 50k pair set offline. Neither has run
# through the wired path -- pf_prepare -> pf_link -> pf_run_batches ->
# pf_dyad_collapse -> pf_status -> pf_propagate_matches -- at all. This run does
# that, on 1k, and profiles the cost of the assets Phase 1 will use.
#
# SECTIONS
#   1  prepare + dedup                       (identity collapse on this sample)
#   2  cascade cost per reference            (active, augmented; 11 passes)
#   3  dyad policy matrix                    (4 configs on ONE scored match)
#   4  the wired path                        (pf_link, fresh checkpoints)
#   5  the stale-checkpoint trap             (documented hazard, never tested)
#   6  extrapolation + findings table
#
#   PF_REFIT=profile  (default)  everything above, inputs/1k_grants_01.csv
#   PF_REFIT=gate                5-file no-dyad run diffed against the freeze
#   PF_REF=active|augmented|both (default both) which references section 2 uses
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)

MODE  <- Sys.getenv("PF_REFIT", "profile")
WHICH <- Sys.getenv("PF_REF", "both")
DD    <- file.path(PF, "data-dev")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function(t = NULL) { cat(strrep("=", 78), "\n")
                            if (!is.null(t)) { cat(t, "\n"); cat(strrep("=", 78), "\n") } }
tick <- function() proc.time()[["elapsed"]]
mem  <- function() sprintf("%.1f GB", sum(gc()[, "max used"] * c(8, 8)) / 1e9)

# Findings accumulate here. `ok = NA` means "reported, not asserted".
FIND <- list()
note <- function(check, ok, detail) {
  FIND[[length(FIND) + 1L]] <<- data.frame(check = check, ok = ok, detail = detail,
                                           stringsAsFactors = FALSE)
  say("  [%s] %-42s %s", if (is.na(ok)) "..." else if (ok) " OK" else "FAIL", check, detail)
}

PASSES <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
NPCFG  <- npmatch::np_config()
FULL_N <- 12559051

## ===========================================================================
## GATE MODE -- does HEAD still reproduce the frozen baseline?
## ===========================================================================
if (MODE == "gate") {
  hr("GATE: 5-file, no dyads, vs BASELINE-2026-08/benchmark-1k-active.rds")
  base <- readRDS(file.path(PF, "dev", "BASELINE-2026-08", "benchmark-1k-active.rds"))
  g <- pf_read_grants(file.path(PF, "inputs"), pattern = "^1k_grants_.*[.]csv$")
  g <- pf_recover_name_from_street(g)
  ref <- readRDS(file.path(DD, "REF-active.rds"))
  t0 <- tick()
  m <- pf_match_grants(g, ref, passes = PASSES, recover = TRUE, verbose = FALSE)
  say("matched %d identities in %.0f s", nrow(as.data.frame(m$result)), tick() - t0)
  res <- as.data.frame(m$result); res <- res[order(res$.id), , drop = FALSE]
  rownames(res) <- NULL
  for (a in c("pairs", "config", "profile", "stages")) attr(res, a) <- NULL
  b <- base; for (a in c("config", "profile", "stages")) attr(b, a) <- NULL
  cols <- intersect(names(b), names(res))
  same <- vapply(cols, function(cn) identical(b[[cn]], res[[cn]]), logical(1))
  say("rows: baseline %d, now %d", nrow(b), nrow(res))
  say("columns identical: %d / %d", sum(same), length(cols))
  if (any(!same)) say("  DIFFER: %s", paste(cols[!same], collapse = ", "))
  quit(save = "no")
}

## ===========================================================================
## 1  PREPARE
## ===========================================================================
hr("1  PREPARE -- inputs/1k_grants_01.csv")
t_prep <- tick()
prep <- pf_prepare(file.path(PF, "inputs"), pattern = "^1k_grants_01[.]csv$",
                   dedup = "fuzzy", verbose = TRUE)
t_prep <- tick() - t_prep
NG <- nrow(prep$grants); NI <- nrow(prep$recipients)
say("")
note("prepare completes", TRUE, sprintf("%d rows -> %d identities (%.3fx) in %.1f s",
                                        NG, NI, sum(prep$grants$in_scope) / NI, t_prep))

## ===========================================================================
## 2  CASCADE COST PER REFERENCE
## ===========================================================================
hr("2  CASCADE COST -- 11 passes, all threads")
REFS <- list(active = "REF-active.rds", augmented = "REF-augmented.rds")
if (WHICH != "both") REFS <- REFS[WHICH]
COST <- list(); MATCHF <- list()
for (rn in names(REFS)) {
  p <- file.path(DD, REFS[[rn]])
  t0 <- tick(); ref <- readRDS(p); t_load <- tick() - t0
  nref <- nrow(ref$reference)
  say("%s: %s rows loaded in %.0f s (%.1f GB file)", rn, format(nref, big.mark = ","),
      t_load, file.size(p) / 1e9)
  t0 <- tick()
  m <- pf_match_grants(prep$recipients, ref, config = NPCFG, passes = PASSES,
                       recover = TRUE, verbose = FALSE)
  t_match <- tick() - t0
  m <- pf_drop_self_matches(m, verbose = FALSE)
  res <- as.data.frame(m$result)
  npair <- nrow(as.data.frame(attr(m$result, "pairs")))
  tb <- table(factor(as.character(res$tier), c("YES", "MAYBE", "NO")))
  s1k <- 1000 * t_match / NI
  say("  match %.0f s | %.0f s per 1,000 identities | %s pairs | YES %d MAYBE %d NO %d",
      t_match, s1k, format(npair, big.mark = ","), tb[["YES"]], tb[["MAYBE"]], tb[["NO"]])
  say("  peak memory %s", mem())
  COST[[rn]] <- data.frame(ref = rn, ref_rows = nref, load_s = t_load,
                           match_s = t_match, s_per_1k = s1k, pairs = npair,
                           yes = tb[["YES"]], maybe = tb[["MAYBE"]], no = tb[["NO"]])
  f <- file.path(tempdir(), sprintf("refit-match-%s.rds", rn))
  saveRDS(m, f, compress = FALSE)
  MATCHF[[rn]] <- f
  say("  scored match cached at %.0f MB (this is the 194 MB pairs finding, at 1k)",
      file.size(f) / 1e6)
  rm(ref, m); invisible(gc())
}
COST <- rbindlist(COST)
say("")
# the frozen cost table, dev/DEVELOPMENT-PLAN.md Phase 1
REFCOST <- c(active = 149, augmented = 279)
for (rn in COST$ref) {
  d <- 100 * (COST$s_per_1k[COST$ref == rn] / REFCOST[[rn]] - 1)
  note(sprintf("cost stable vs plan (%s)", rn), abs(d) < 35,
       sprintf("%.0f s/1k now vs %d s/1k on record (%+.0f%%)",
               COST$s_per_1k[COST$ref == rn], REFCOST[[rn]], d))
}

## ===========================================================================
## 3  DYAD POLICY MATRIX -- four configs against ONE scored match
## ===========================================================================
hr("3  DYAD POLICY MATRIX")
DYADS <- readRDS(file.path(DD, "PF-DYADS-UNIFIED.rds"))
say("dyads: %s pairs, %s substitutable", format(nrow(DYADS), big.mark = ","),
    format(sum(DYADS$dyad_class == "substitutable"), big.mark = ","))
RB <- if ("active" %in% names(MATCHF)) "active" else names(MATCHF)[1]
say("collapsing against the %s reference", RB)

CFGS <- list(
  `query/keepveto`     = pf_dyad_config(policy = "query"),      # shipping default
  `operating/keepveto` = pf_dyad_config(policy = "operating"),  # pre-046a7b5
  `query/NOveto`       = pf_dyad_config(policy = "query", keep_soft_veto = FALSE),
  `top/keepveto`       = pf_dyad_config(policy = "top"))

base <- readRDS(MATCHF[[RB]])
bres <- as.data.frame(base$result)
bpair <- nrow(as.data.frame(attr(base$result, "pairs")))
btier <- as.character(bres$tier); names(btier) <- bres$.id
bein  <- bres$overall_ein;        names(bein)  <- bres$.id
bveto <- bres$overall_veto_soft %in% TRUE; names(bveto) <- bres$.id
qname <- prep$recipients$recip_name[match(bres$.id, prep$recipients$grant_id)]
names(qname) <- bres$.id
rm(base); invisible(gc())

ARMS <- list()
for (cn in names(CFGS)) {
  x <- readRDS(MATCHF[[RB]])
  t0 <- tick()
  o <- suppressMessages(pf_dyad_collapse(x, DYADS, CFGS[[cn]], np_config = NPCFG))
  t_coll <- tick() - t0
  r <- as.data.frame(o$result)
  np <- nrow(as.data.frame(attr(o$result, "pairs")))
  tb <- table(factor(as.character(r$tier), c("YES", "MAYBE", "NO")))
  mv <- data.frame(id = r$.id, from = btier[r$.id], to = as.character(r$tier),
                   e0 = bein[r$.id], e1 = r$overall_ein,
                   coll = r$dyad_collapsed %in% TRUE,
                   veto0 = bveto[r$.id], nm = r$overall_name_y,
                   q = qname[r$.id], npairs = np, stringsAsFactors = FALSE)
  ARMS[[cn]] <- mv
  say("%-20s %5.1f s | collapsed %4d | YES %4d MAYBE %4d NO %4d | M->Y %3d | pairs %s",
      cn, t_coll, sum(mv$coll), tb[["YES"]], tb[["MAYBE"]], tb[["NO"]],
      sum(mv$from == "MAYBE" & mv$to == "YES"), format(np, big.mark = ","))
  rm(x, o); invisible(gc())
}
say("")

D <- ARMS[["query/keepveto"]]
# --- invariant 1: nothing is pushed into NO -------------------------------
into_no <- sum(D$from != "NO" & D$to == "NO")
note("collapse never demotes to NO", into_no == 0, sprintf("%d demotions", into_no))
# --- invariant 2: every tier change is on a collapsed identity -------------
off <- sum(D$from != D$to & !D$coll)
note("tier changes only on collapsed rows", off == 0, sprintf("%d off-target", off))
# --- invariant 3 (0b28fd7): the pairs attribute really shrinks --------------
npq <- D$npairs[1]
note("reduced pair set survives (modifyList fix)", npq < bpair,
     sprintf("%s -> %s pairs (-%.2f%%)", format(bpair, big.mark = ","),
             format(npq, big.mark = ","), 100 * (1 - npq / bpair)))
# --- invariant 4 (0b28fd7): no promotion where the baseline pick was vetoed -
expo <- sum(D$from == "MAYBE" & D$to == "YES" & D$veto0 & D$e0 != D$e1, na.rm = TRUE)
note("soft-veto exposure = 0 (keep_soft_veto)", expo == 0,
     sprintf("%d promotions overrode a veto and changed the pick", expo))
Dnv <- ARMS[["query/NOveto"]]
exnv <- sum(Dnv$from == "MAYBE" & Dnv$to == "YES" & Dnv$veto0 & Dnv$e0 != Dnv$e1, na.rm = TRUE)
note("the guard binds on this sample", NA,
     sprintf("keep_soft_veto=FALSE exposes %d (if 0, this sample cannot test it)", exnv))
# --- invariant 5 (046a7b5): query switches only where the GRANT names an arm -
O <- ARMS[["operating/keepveto"]]
cm <- merge(D[, c("id", "e1", "nm", "q")], O[, c("id", "e1", "nm")], by = "id",
            suffixes = c("_q", "_o"))
ch <- cm[!is.na(cm$e1_q) & !is.na(cm$e1_o) & cm$e1_q != cm$e1_o, , drop = FALSE]
bad <- if (nrow(ch)) sum(!pf_is_arm(ch$q)) else 0L
note("query policy switches are arm-named grants", bad == 0,
     sprintf("%d EIN switches vs operating, %d not arm-named", nrow(ch), bad))
if (nrow(ch)) {
  say("")
  print(head(data.frame(grant = substr(ch$q, 1, 34), was = substr(ch$nm_o, 1, 26),
                        now = substr(ch$nm_q, 1, 26)), 12), row.names = FALSE)
  say("")
}
tierdiff <- sum(D$to != O$to[match(D$id, O$id)])
note("policy is EIN-only, not tier-moving", NA, sprintf("%d tier differences", tierdiff))

## ===========================================================================
## 4  THE WIRED PATH
## ===========================================================================
hr("4  WIRED PATH -- pf_link with dyads, fresh checkpoints")
CK <- file.path(DD, "batches-refit1k")
unlink(CK, recursive = TRUE)
ref <- readRDS(file.path(DD, REFS[[RB]]))
t0 <- tick()
lk <- pf_link(prep, ref, dir = CK, batch_size = 400L, passes = PASSES,
              config = NPCFG, dyads = DYADS,
              dyad_config = pf_dyad_config(policy = "query"), verbose = TRUE)
t_link <- tick() - t0
st <- lk$status
say("")
note("pf_link completes with dyads wired", TRUE,
     sprintf("%.0f s, %d batches, %d identities", t_link,
             length(list.files(CK, pattern = "^batch-")), nrow(st)))

# --- the documented status contract ---------------------------------------
promised <- c("dyad_collapsed", "dyad_id", "dyad_alt_ein", "dyad_class")
missing  <- setdiff(promised, names(st))
note("status carries the documented dyad columns", length(missing) == 0,
     if (length(missing)) sprintf("MISSING %s; present %s",
        paste(missing, collapse = ", "),
        paste(grep("^dyad", names(st), value = TRUE), collapse = ", ")) else "all four")

# --- pf_status() reads the REDUCED pairs; did geo survive the collapse? ----
coll <- st$dyad_collapsed %in% TRUE
scored <- st$status %in% c("YES", "MAYBE")
gna <- function(i) if (!any(i)) NA_real_ else mean(is.na(st$bmf_state[i]))
note("geo columns survive the reduced pair set", NA,
     sprintf("bmf_state NA: %.1f%% collapsed vs %.1f%% not (scored rows)",
             100 * gna(coll & scored), 100 * gna(!coll & scored)))

# --- propagation reconciles ------------------------------------------------
tb <- table(factor(lk$grants$status, pf_status_levels()))
note("grant rows reconcile to the input", sum(tb) == NG,
     sprintf("%d rows: YES %d MAYBE %d NO %d OOS %d", sum(tb), tb[["YES"]],
             tb[["MAYBE"]], tb[["NO"]], tb[["OOS"]]))
note("collapse fires on the wired path", NA,
     sprintf("%d identities (%.1f%%)", sum(coll), 100 * mean(coll)))

# --- checkpoint footprint, for shard sizing --------------------------------
# Two components with different scaling: the status rows grow per identity, the
# run stamp is a fixed cost per BATCH. Extrapolating the total per identity from
# 400-row batches would multiply the stamp by 62x its real production count.
ckf  <- list.files(CK, full.names = TRUE)
cksz <- sum(file.size(ckf))
stmp <- length(serialize(attr(readRDS(ckf[1]), "pf_stamp"), NULL))
rowsz <- (cksz - stmp * length(ckf)) / nrow(st)
nb_full <- ceiling(FULL_N / 25000)
note("checkpoint footprint", NA,
     sprintf("%.1f MB over %d batches (stamp %.0f KB each) -> %.1f GB at 12.56M / batch_size 25k",
             cksz / 1e6, length(ckf), stmp / 1e3,
             (rowsz * FULL_N + stmp * nb_full) / 1e9))

## ===========================================================================
## 5  THE STALE-CHECKPOINT TRAP
## ===========================================================================
hr("5  STALE CHECKPOINTS -- documented hazard, never tested")
say("re-running the SAME dir with policy='operating'. Before the checkpoint")
say("stamp this returned the cached answer and the changed config never ran.")
trap <- tryCatch({
  lk2 <- suppressMessages(pf_link(prep, ref, dir = CK, batch_size = 400L,
                                 passes = PASSES, config = NPCFG, dyads = DYADS,
                                 dyad_config = pf_dyad_config(policy = "operating"),
                                 verbose = FALSE))
  list(err = NA_character_, same = identical(lk2$status$ein, st$ein))
}, error = function(e) list(err = conditionMessage(e), same = NA))
note("config change is refused, not silently ignored",
     !is.na(trap$err) && grepl("different settings", trap$err),
     if (is.na(trap$err))
       sprintf("no error; EINs %s the first run",
               if (isTRUE(trap$same)) "IDENTICAL to" else "differ from")
     else sub("\n.*$", "", trap$err))
# and the escape hatch still works: resume = FALSE recomputes under the new config
lk3 <- suppressMessages(pf_link(prep, ref, dir = CK, batch_size = 400L,
                               passes = PASSES, config = NPCFG, dyads = DYADS,
                               dyad_config = pf_dyad_config(policy = "operating"),
                               resume = FALSE, verbose = FALSE))
note("resume = FALSE recomputes under the new config", NA,
     sprintf("%d EINs differ from the query-policy run",
             sum(lk3$status$ein != st$ein, na.rm = TRUE)))
rm(ref); invisible(gc())

## ===========================================================================
## 6  EXTRAPOLATION AND FINDINGS
## ===========================================================================
hr("6  EXTRAPOLATION TO 12,559,051 GRANTS")
dedup <- sum(prep$grants$in_scope) / NI
say("dedup on this sample .......... %.3fx (the full file repeats grantees far more)", dedup)
say("")
say("%-12s %10s %12s %12s %12s", "reference", "s per 1k", "no dedup", "at 1.8x", "12 shards")
for (i in seq_len(nrow(COST))) {
  h <- FULL_N / 1000 * COST$s_per_1k[i] / 3600
  say("%-12s %10.0f %10.0f h %10.0f h %10.0f h", COST$ref[i], COST$s_per_1k[i],
      h, h / 1.8, h / 1.8 / 12)
}
say("")
say("Budget on record: 117 h. Phase 1 target config is augmented + 11 passes.")

hr("FINDINGS")
FIND <- rbindlist(FIND)
for (i in seq_len(nrow(FIND)))
  say("[%s] %-42s %s", if (is.na(FIND$ok[i])) "..." else if (FIND$ok[i]) " OK" else "FAIL",
      FIND$check[i], FIND$detail[i])
say("")
say("%d checks: %d pass, %d FAIL, %d reported", nrow(FIND), sum(FIND$ok %in% TRUE),
    sum(FIND$ok %in% FALSE), sum(is.na(FIND$ok)))
fwrite(FIND, file.path(DD, "REFIT-1K-FINDINGS.csv"))
fwrite(COST, file.path(DD, "REFIT-1K-COST.csv"))
fwrite(rbindlist(lapply(names(ARMS), function(n) data.frame(arm = n, ARMS[[n]]))),
       file.path(DD, "REFIT-1K-ARMS.csv"))
say("wrote data-dev/REFIT-1K-{FINDINGS,COST,ARMS}.csv")

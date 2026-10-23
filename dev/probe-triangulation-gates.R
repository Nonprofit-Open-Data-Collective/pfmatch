#!/usr/bin/env Rscript
# ============================================================================
# Does gating rescue address-based triangulation?
#
# dev/probe-triangulation.R found the population is large: 1,263 eligible
# addresses yielding 4,294 silver labels, 2,853 of them informative (a label the
# run does not already assert). But eyeballing 12 showed roughly half are wrong,
# in two distinct ways:
#
#   FALSE GROUPING  "Walmart" inherits an anchor because something else files at
#                   the same street+zip. "MAGNOLIA SCHOOL INC" (FL ein) inherits
#                   a Louisiana anchor.
#   WRONG ANCHOR    "Homes for our Troops" own pick 54-2143612 is right and the
#                   anchor 06-0813354 is wrong -- the sibling was correct and
#                   the YES was not.
#
# And the genuine wins are obvious: "THE MET" x4 and "MET MUSEUM MEMBERSHIP"
# all inherit 13-1624086, the Metropolitan Museum of Art, which is right.
#
# So the question is not whether the signal exists but whether it can be
# separated from the noise by gates that do NOT use the name comparator (the
# thing under test). Candidate gates, each independent of name similarity:
#
#   same filer        a funder paying the same grantee repeatedly is far
#                     stronger evidence of identity than a shared building
#   anchor strength   the anchoring YES must not itself be a token_overlap or
#                     low-margin match
#   anchor agreement  two or more YES renderings agreeing, not one
#   address exclusive the address must carry exactly one distinct EIN overall
#   state agreement   the sibling's filed state must match the anchor's
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 88))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

M <- readRDS(file.path(PF, "data-dev", "FILER-SAMPLE-MATCH.rds"))
g <- as.data.table(M$grants)[in_scope == TRUE]
say("columns available on the run: %s",
    paste(intersect(c("status","ein","score","match_pass","bmf_name"), names(g)),
          collapse = ", "))

g[, st_key := toupper(gsub("[^A-Z0-9]", "", toupper(sq(recip_street))))]
g[, pobox  := grepl("^P?O?BOX|^POST", st_key)]
g[, addr_key := fifelse(nzchar(st_key) & !pobox & nzchar(sq(recip_zip5)),
                        paste(st_key, sq(recip_zip5), sep = "|"), NA_character_)]
a <- g[!is.na(addr_key)]
a[, nm_key := gsub(" +", " ", trimws(toupper(gsub("[^A-Z0-9 ]", " ", sq(recip_name)))))]
a[, has_ein := !is.na(ein) & nzchar(sq(ein))]
a[, sc := suppressWarnings(as.numeric(score))]

build <- function(dt, key_cols, min_yes = 1L, min_anchor_score = 0,
                  exclusive = FALSE, label = "") {
  dt <- copy(dt)
  dt[, .grp := do.call(paste, c(lapply(key_cols, function(k) sq(dt[[k]])), sep = "\v"))]
  cand <- dt[, {
    yes <- status == "YES" & has_ein & (is.na(sc) | sc >= min_anchor_score)
    .(n_names = uniqueN(nm_key), n_yes = sum(yes), n_other = sum(status != "YES"),
      yes_eins = uniqueN(ein[yes]), all_eins = uniqueN(ein[has_ein]),
      anchor = if (sum(yes)) ein[yes][1] else NA_character_)
  }, by = .grp]
  elig <- cand[n_names >= 2L & n_yes >= min_yes & n_other >= 1L & yes_eins == 1L]
  if (exclusive) elig <- elig[all_eins == 1L]
  lab <- merge(dt[status != "YES"], elig[, .(.grp, anchor)], by = ".grp")
  lab[, informative := !(has_ein & ein == anchor)]
  data.table(gate = label, groups = nrow(elig), labels = nrow(lab),
             informative = sum(lab$informative))
}

hr(); say("GATE SWEEP"); hr()
res <- rbindlist(list(
  build(a, "addr_key",                          label = "address only (baseline)"),
  build(a, "addr_key", exclusive = TRUE,        label = "+ address has ONE ein overall"),
  build(a, "addr_key", min_yes = 2L,            label = "+ >=2 YES renderings agree"),
  build(a, "addr_key", min_anchor_score = 0.90, label = "+ anchor score >= 0.90"),
  build(a, c("FILEREIN", "addr_key"),           label = "same FILER + address"),
  build(a, c("FILEREIN", "addr_key"), exclusive = TRUE, min_yes = 2L,
        min_anchor_score = 0.90,                label = "filer + addr + all three gates")))
say("%-42s %8s %8s %12s", "gate", "groups", "labels", "informative")
for (i in seq_len(nrow(res)))
  say("%-42s %8s %8s %12s", res$gate[i], format(res$groups[i], big.mark = ","),
      format(res$labels[i], big.mark = ","), format(res$informative[i], big.mark = ","))

hr(); say("STRICTEST GATE -- examples to eyeball"); hr()
a2 <- copy(a)
a2[, .grp := paste(sq(FILEREIN), sq(addr_key), sep = "\v")]
cand <- a2[, {
  yes <- status == "YES" & has_ein & (is.na(sc) | sc >= 0.90)
  .(n_names = uniqueN(nm_key), n_yes = sum(yes), n_other = sum(status != "YES"),
    yes_eins = uniqueN(ein[yes]), all_eins = uniqueN(ein[has_ein]),
    anchor = if (sum(yes)) ein[yes][1] else NA_character_,
    anchor_name = if (sum(yes)) sq(bmf_name[yes])[1] else "")
}, by = .grp]
elig <- cand[n_names >= 2L & n_yes >= 2L & n_other >= 1L & yes_eins == 1L & all_eins == 1L]
lab <- merge(a2[status != "YES"], elig[, .(.grp, anchor, anchor_name)], by = ".grp")
lab <- lab[!(has_ein & ein == anchor)]
say("informative labels under the strictest gate: %d", nrow(lab))
if (nrow(lab)) {
  show <- lab[order(recip_name)][1:min(20L, nrow(lab))]
  say("  %-34s %-6s %-11s %-11s %s", "filed name", "tier", "own ein", "anchor", "anchor BMF name")
  for (i in seq_len(nrow(show)))
    say("  %-34s %-6s %-11s %-11s %s", substr(show$recip_name[i], 1, 34),
        show$status[i], sq(show$ein[i]), show$anchor[i],
        substr(sq(show$anchor_name[i]), 1, 30))
}
fwrite(lab, file.path(PF, "data-dev", "TRIANGULATION-GATED.csv"))
hr(); say("wrote data-dev/TRIANGULATION-GATED.csv")

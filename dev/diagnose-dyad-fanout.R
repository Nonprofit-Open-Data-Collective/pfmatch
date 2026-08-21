#!/usr/bin/env Rscript
# ============================================================================
# The first build's substitutability rule is wrong, and this is why.
#
# "X is a 509(a)(3) supporting organization of Y" is not a one-to-one relation.
# The YMCA Retirement Fund supports 905 local YMCAs; SparkJoy Foundation
# supports 408 unrelated Maine charities; Vitalyst Health Foundation supports
# 400. A grant reported to "Bangor YMCA" is emphatically NOT interchangeable
# with "YMCA Retirement Fund", so a bare Schedule A edge cannot license
# substitution.
#
# Substitution needs the relation to be EXCLUSIVE - the arm exists to fund this
# one body and no other. Fan-out is the measurable form of that.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
sub <- function() cat(strrep("-", 78), "\n")

d <- readRDS(file.path(PF, "data-dev", "PF-DYADS.rds"))
d <- as.data.table(unclass(d))

hr(); say("FAN-OUT OF THE SCHEDULE A SUPPORT RELATION"); hr()
sa <- d[!is.na(sched_a_dir)]
sa[, `:=`(supporter = fifelse(sched_a_dir == "a_supports_b", ein_a, ein_b),
          supported = fifelse(sched_a_dir == "a_supports_b", ein_b, ein_a),
          sup_name  = fifelse(sched_a_dir == "a_supports_b", name_a, name_b),
          sed_name  = fifelse(sched_a_dir == "a_supports_b", name_b, name_a))]
sa[, fan_out := .N, by = supporter]   # how many bodies does this supporter support
sa[, fan_in  := .N, by = supported]   # how many arms does this body have

say("Schedule A edges: %s over %s supporters",
    format(nrow(sa), big.mark=","), format(uniqueN(sa$supporter), big.mark=","))
say("")
print(sa[, .(edges = .N, pct_of_edges = round(100*.N/nrow(sa),1)),
         by = .(fan_out_bucket = cut(fan_out, c(0,1,2,3,6,11,51,Inf), right = FALSE,
                labels = c("1","2","3","4-5","6-10","11-50","51+")))][order(fan_out_bucket)],
      row.names = FALSE)
say("")
say("edges from a supporter with fan-out 1 : %s (%.0f%%) - the exclusive case",
    format(sum(sa$fan_out == 1), big.mark=","), 100*mean(sa$fan_out == 1))
say("edges from a supporter with fan-out >10: %s (%.0f%%) - grantmakers, not arms",
    format(sum(sa$fan_out > 10), big.mark=","), 100*mean(sa$fan_out > 10))

sub(); say("THE BIGGEST SUPPORTERS - none of these licenses a substitution"); sub()
print(head(unique(sa[, .(supporter, sup_name = substr(sup_name,1,44), fan_out)],
                  by = "supporter")[order(-fan_out)], 15), row.names = FALSE)

sub(); say("DOES A NAME CORE MATCH SURVIVE HIGH FAN-OUT?"); sub()
sa[, core_same := pf_arm_core(name_a) == pf_arm_core(name_b) &
                  nchar(pf_arm_core(name_a)) >= 8L]
print(sa[, .(edges = .N, name_core_agrees = sum(core_same),
             pct = round(100*mean(core_same),1)),
         by = .(fan_out_bucket = cut(fan_out, c(0,1,2,3,6,11,51,Inf), right = FALSE,
                labels = c("1","2","3","4-5","6-10","11-50","51+")))][order(fan_out_bucket)],
      row.names = FALSE)
say("")
say("The name core is the check that survives: at fan-out 1 the names agree far")
say("more often than at fan-out 51+, which is what an exclusive arm looks like.")

hr(); say("WHAT EACH CANDIDATE RULE WOULD CLASS AS SUBSTITUTABLE"); hr()
d[, core_same := pf_arm_core(name_a) == pf_arm_core(name_b) &
                 nchar(pf_arm_core(name_a)) >= 8L &
                 lengths(strsplit(pf_arm_core(name_a), " ")) >= 2L]
fo <- unique(sa[, .(supporter, fan_out)], by = "supporter")
d[, sup_ein := fifelse(is.na(sched_a_dir), NA_character_,
                fifelse(sched_a_dir == "a_supports_b", ein_a, ein_b))]
d[, fan_out := fo$fan_out[match(sup_ein, fo$supporter)]]

rules <- list(
  `sched A edge (any fan-out)`        = !is.na(d$sched_a_dir),
  `sched A, fan-out <= 3`             = !is.na(d$sched_a_dir) & d$fan_out <= 3L,
  `sched A, fan-out 1`                = !is.na(d$sched_a_dir) & d$fan_out == 1L,
  `identical name core`               = d$core_same,
  `name core + same state`            = d$core_same & d$same_state %in% TRUE,
  `sched A fan-out<=3 OR name core`   = (!is.na(d$sched_a_dir) & d$fan_out <= 3L) | d$core_same
)
say("%-34s %10s %8s", "rule", "pairs", "% of all")
for (r in names(rules)) {
  v <- rules[[r]]; v[is.na(v)] <- FALSE
  say("%-34s %10s %7.1f%%", r, format(sum(v), big.mark=","), 100*mean(v))
}

sub(); say("MAX DEGREE UNDER EACH RULE - the number that decides it"); sub()
for (r in names(rules)) {
  v <- rules[[r]]; v[is.na(v)] <- FALSE
  s <- d[v]
  if (!nrow(s)) { say("%-34s -", r); next }
  dg <- rbind(s[, .(ein = ein_a)], s[, .(ein = ein_b)])[, .N, by = ein]
  say("%-34s max %5d   mean %4.2f   EINs with degree>10 %5d",
      r, max(dg$N), mean(dg$N), sum(dg$N > 10))
}

sub(); say("WHAT 'sched A fan-out<=3 OR name core' DROPS FROM THE OLD RULE"); sub()
old <- !is.na(d$sched_a_dir) | d$core_same; old[is.na(old)] <- FALSE
new <- rules[["sched A fan-out<=3 OR name core"]]; new[is.na(new)] <- FALSE
say("dropped: %s pairs", format(sum(old & !new), big.mark=","))
print(head(d[old & !new, .(a = substr(name_a,1,34), b = substr(name_b,1,34), fan_out)], 15),
      row.names = FALSE)

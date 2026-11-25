## Re-derive the benchmark clear rate under the new individual-payee flag.
##
## §5 of dev/PERFORMANCE-REPORT-20261106.md carried this as a PROJECTION:
## "individual-payee flag fix | 69.0% -> ~72.3%", sourced to a hand audit of 100
## cases in dev/NO-RESIDUAL-AUDIT.md which extrapolated ~219 individuals onto a
## 592-case cell. Commit 5f73dcd replaced the 202-name given-name whitelist with
## a scored flag, so the count can now be measured on the whole benchmark
## instead of extrapolated from a sample.
##
## Run from the repository root:  Rscript dev/rederive-denominator.R
##
## Both arms of BASELINE-2026-10C are done here. The normalizer does not enter
## it: nothing is re-matched. Each arm's frozen result frame already carries its
## tiers, and all this does is recompute the flag from the grants and join it on.
## (An earlier version of this script did the augmented arm only, on the stated
## grounds that the active arm "could not be re-run on the current normalizer".
## That was wrong twice: MANIFEST.md's addendum says the active arm was *not*
## re-run while the two **matchdb tiers** could not be, and re-running is not a
## precondition for this measurement in the first place.)

if (!file.exists("DESCRIPTION"))
  stop("run this from the repository root", call. = FALSE)

suppressMessages(library(data.table))
if (requireNamespace("pkgload", quietly = TRUE)) pkgload::load_all(".", quiet = TRUE)

say <- function(...) cat(sprintf(...), "\n", sep = "")
w <- function(k, n) {
  ci <- pfmatch::pf_wilson(k, n)
  sprintf("%5d / %5d = %6.2f%%  [%.2f, %.2f]", k, n, 100 * k / n,
          100 * ci[1, "lo"], 100 * ci[1, "hi"])
}

## -- 1. the population the frozen benchmark was built from ------------------
g <- pf_read_grants("inputs", pattern = "^efv2_1k_grants_.*\\.csv$")
p <- as.data.table(pf_prepare_grants(g))
say("grant rows            %d   (MANIFEST.md: 4,903)", nrow(g))
say("population id         %s   (MANIFEST.md: 0b5126ef02f2a8b0)", pf_population_id(p))
stopifnot(nrow(g) == 4903L)

## -- 2. join, and prove the join ------------------------------------------
## `.id` and `grant_id` are both positional G%06d over the same input files.
## Positional ids mis-attach silently when the frame changes, so the alignment
## is checked rather than assumed: `name_x` is the npnormalize-processed name
## and `recip_name` the raw filed one, so the check undoes the normalizer's own
## expansions before comparing.
canon <- function(x) {
  v <- toupper(ifelse(is.na(x), "", x))
  v <- gsub("&", " AND ", v, fixed = TRUE)
  v <- gsub("\\bSAINT\\b", "ST", v)
  v <- gsub("\\bMOUNT\\b", "MT", v)
  gsub("[^A-Z0-9]", "", v)
}
join_arm <- function(file, expect) {
  b <- as.data.table(readRDS(file.path("dev/BASELINE-2026-10C", file)))
  say("  %-28s %d identities   (report §3b: %s)", file, nrow(b), expect)
  m <- merge(b[, .(.id, tier, name_x)],
             p[, .(grant_id, recip_name, looks_personal, flag_placeholder,
                   flag_individual)],
             by.x = ".id", by.y = "grant_id", all.x = TRUE)
  stopifnot(nrow(m) == nrow(b), m[is.na(recip_name), .N] == 0L)
  agree <- mean(canon(m$name_x) == canon(m$recip_name))
  say("  name agreement               %.2f%%", 100 * agree)
  if (agree < 0.97)
    stop("join is not aligned for ", file, "; its figures would be meaningless")
  m
}
cat("\n== joining both arms ==\n")
arms <- list(active    = join_arm("benchmark-1k-active.rds",    "4,687"),
             augmented = join_arm("benchmark-1k-augmented.rds", "4,748"))
say("  (join residual is abbreviation expansion: UNIV->UNIVERSITY,")
say("   ASSN->ASSOCIATION, FDN->FOUNDATION, ST->SAINT, & -> AND)")

## -- 3. the flag as it stood before 5f73dcd -------------------------------
## Lifted verbatim from 373e700:R/prepare.R so the two can be counted on one
## population. Kept here rather than in the package, where it is deleted.
old_org <- c(
  "INC","INCORPORATED","CORP","CORPORATION","CO","COMPANY","LLC","LTD",
  "FOUNDATION","FDN","FUND","TRUST","ASSOCIATION","ASSN","SOCIETY","INSTITUTE",
  "INSTITUTION","CENTER","CENTRE","COUNCIL","COMMITTEE","CHURCH","TEMPLE",
  "SYNAGOGUE","MOSQUE","MINISTRY","MINISTRIES","MISSION","MISSIONS","SCHOOL",
  "SCHOOLS","ACADEMY","COLLEGE","UNIVERSITY","SEMINARY","HOSPITAL","CLINIC",
  "HEALTH","MUSEUM","LIBRARY","THEATRE","THEATER","ORCHESTRA","CHORUS",
  "BALLET","GALLERY","CLUB","LEAGUE","ALLIANCE","COALITION","NETWORK",
  "PARTNERSHIP","PROJECT","PROGRAM","SERVICES","SERVICE","ORGANIZATION",
  "GROUP","SOCIETIES","CHAPTER","CHARITIES","CHARITABLE","AMERICAN",
  "NATIONAL","INTERNATIONAL","COMMUNITY","UNITED","FRIENDS","BOARD",
  "AUTHORITY","DISTRICT","COUNTY","CITY","STATE","PUBLIC","OF","THE","AND",
  "FOR","USA","US","INSTITUTO","ASSOCIATES","ENDOWMENT")
old_given <- c(
  "JAMES","JOHN","ROBERT","MICHAEL","WILLIAM","DAVID","RICHARD","JOSEPH",
  "THOMAS","CHARLES","CHRISTOPHER","DANIEL","MATTHEW","ANTHONY","DONALD",
  "MARK","PAUL","STEVEN","ANDREW","KENNETH","JOSHUA","GEORGE","KEVIN","BRIAN",
  "EDWARD","RONALD","TIMOTHY","JASON","JEFFREY","RYAN","JACOB","GARY",
  "NICHOLAS","ERIC","STEPHEN","JONATHAN","LARRY","JUSTIN","SCOTT","BRANDON",
  "FRANK","BENJAMIN","GREGORY","SAMUEL","RAYMOND","PATRICK","ALEXANDER",
  "JACK","DENNIS","JERRY","TYLER","AARON","JOSE","ADAM","NATHAN","HENRY",
  "ZACHARY","DOUGLAS","PETER","KYLE","WALTER","ETHAN","JEREMY","HAROLD",
  "KEITH","CHRISTIAN","ROGER","NOAH","GERALD","CARL","TERRY","SEAN","AUSTIN",
  "ARTHUR","LAWRENCE","JESSE","DYLAN","BRYAN","JOE","JORDAN","BILLY","BRUCE",
  "ALBERT","WILLIE","GABRIEL","LOGAN","ALAN","JUAN","WAYNE","RALPH","ROY",
  "EUGENE","RANDY","VINCENT","RUSSELL","LOUIS","PHILIP","BOBBY","JOHNNY",
  "BRADLEY","MARY","PATRICIA","JENNIFER","LINDA","ELIZABETH","BARBARA",
  "SUSAN","JESSICA","SARAH","KAREN","NANCY","LISA","MARGARET","BETTY",
  "SANDRA","ASHLEY","DOROTHY","KIMBERLY","EMILY","DONNA","MICHELLE","CAROL",
  "AMANDA","MELISSA","DEBORAH","STEPHANIE","REBECCA","LAURA","SHARON",
  "CYNTHIA","KATHLEEN","AMY","SHIRLEY","ANGELA","HELEN","ANNA","BRENDA",
  "PAMELA","NICOLE","SAMANTHA","KATHERINE","EMMA","RUTH","CHRISTINE",
  "CATHERINE","DEBRA","RACHEL","CAROLYN","JANET","VIRGINIA","MARIA","HEATHER",
  "DIANE","JULIE","JOYCE","VICTORIA","KELLY","CHRISTINA","JOAN","EVELYN",
  "LAUREN","JUDITH","OLIVIA","FRANCES","MARTHA","CHERYL","MEGAN","ANDREA",
  "HANNAH","JACQUELINE","ANN","JEAN","ALICE","KATHRYN","GLORIA","TERESA",
  "DORIS","SARA","JANICE","MARIE","JULIA","GRACE","JUDY","THERESA","MADISON",
  "BEVERLY","DENISE","MARILYN","AMBER","DANIELLE","ABIGAIL","BRITTANY","ROSE",
  "NATALIE","SOPHIA","ALEXIS","LORI","KAYLA","JANE","TIFFANY","CRYSTAL")
old_flag <- function(name) {
  v <- toupper(trimws(as.character(name))); v[is.na(v)] <- ""
  v <- trimws(gsub("[[:space:]]+", " ", gsub("[^A-Z ]+", " ", v)))
  vapply(strsplit(v, " ", fixed = TRUE), function(t) {
    t <- t[nzchar(t)]
    if (length(t) < 2L || length(t) > 3L) return(FALSE)
    if (any(t %in% old_org)) return(FALSE)
    any(nchar(t[-1]) == 1L) || any(t %in% old_given)
  }, logical(1))
}
for (a in names(arms)) {
  arms[[a]][, old_personal := old_flag(recip_name)]
  arms[[a]][, new_personal := looks_personal %in% TRUE]
}

## -- 4. per arm: where the flags land, and what the clear rate becomes -----
for (a in names(arms)) {
  m <- arms[[a]]
  tot <- nrow(m); yes <- m[tier == "YES", .N]
  cat("\n\n================ the ", a, " arm ================\n", sep = "")

  cat("\n== flagged-personal identities by tier ==\n")
  print(m[, .(identities = .N, old = sum(old_personal), new = sum(new_personal),
              placeholder = sum(flag_placeholder %in% TRUE)), by = tier][order(tier)])

  cat("\n== clear rate ==\n")
  say("as published (§3b)        %s", w(yes, tot))
  for (fl in c("old_personal", "new_personal")) {
    k <- yes - m[tier == "YES" & get(fl), .N]
    n <- tot - m[get(fl) == TRUE, .N]
    say("%-25s %s", paste0("minus ", fl), w(k, n))
  }
  k <- yes - m[tier == "YES" & (new_personal | flag_placeholder %in% TRUE), .N]
  n <- tot - m[new_personal | flag_placeholder %in% TRUE, .N]
  say("%-25s %s", "minus persons + pointers", w(k, n))
  say("delta from the new flag alone: %+.2f pt",
      100 * ((yes - m[tier == "YES" & new_personal, .N]) /
             (tot - m[new_personal == TRUE, .N]) - yes / tot))

  say("")
  say("flagged persons landing in NO: %d of %d (%.1f%%) new, %d of %d (%.1f%%) old",
      m[tier == "NO" & new_personal, .N], m[new_personal == TRUE, .N],
      100 * m[tier == "NO" & new_personal, .N] / m[new_personal == TRUE, .N],
      m[tier == "NO" & old_personal, .N], m[old_personal == TRUE, .N],
      100 * m[tier == "NO" & old_personal, .N] / m[old_personal == TRUE, .N])
}

## -- 5. do the two arms agree on who is a person? -------------------------
## They are two matching runs over one grant population, so the flag -- which
## reads only the name -- must fire on the same recipients in both. If it does
## not, the join is wrong somewhere.
cat("\n\n== cross-arm check on the shared identities ==\n")
x <- merge(arms$active[, .(.id, a_new = new_personal, a_tier = tier)],
           arms$augmented[, .(.id, g_new = new_personal, g_tier = tier)],
           by = ".id")
say("identities in both arms: %d", nrow(x))
say("flag disagrees on:       %d  (must be 0 -- the flag reads only the name)",
    x[a_new != g_new, .N])
cat("\ntier movement between arms, among flagged persons:\n")
print(x[a_new == TRUE, .N, by = .(a_tier, g_tier)][order(-N)])

cat("\n== what the new flag adds in the NO tier, augmented arm, 15 of them ==\n")
set.seed(9)
add <- arms$augmented[tier == "NO" & new_personal & !old_personal]
say("added in the NO tier: %d", nrow(add))
print(add[sample(.N, min(15, .N))][, .(recip_name)])

say("")
say("A person cannot match an organisation, so a flag that is right puts almost")
say("all of its hits in NO. That is the internal check on the figures above.")

## -- 6. §3a, the production triangulation frame ---------------------------
## The largest frame that exists: 91,008 identities. No join is needed here at
## all -- TRI-V2-MATCH.rds's `status` frame carries `recip_name` in the same row
## as the tier, and carries the OLD `looks_personal` as it stood when the run
## was built, so old and new are compared in place.
cat("\n\n================ §3a, the production frame ================\n")
tri <- readRDS("data-dev/TRI-V2-MATCH.rds")
say("built        %s", tri$built)
say("normalizer   %s", tri$normalizer)
say("id_scheme    %s", tri$id_scheme)
say("rekeyed      %s", tri$rekeyed)

s <- as.data.table(tri$status)
rm(tri); invisible(gc())
say("identities   %s   (report §3a: 91,008)", format(nrow(s), big.mark = ","))

cat("\n== tier counts, against the published figures ==\n")
pub <- c(YES = 41341L, MAYBE = 23340L, NO = 26327L)
got <- table(s$status)
for (k in names(pub))
  say("  %-6s %s published %s   %s", k, format(got[[k]], big.mark = ","),
      format(pub[[k]], big.mark = ","),
      if (identical(as.integer(got[[k]]), pub[[k]])) "reconciles" else "*** DIFFERS ***")
stopifnot(nrow(s) == 91008L)

## The stored flag is the whitelist as it stood on 2026-11-03; recompute both so
## the comparison is like for like on one frame.
s[, stored_personal := looks_personal %in% TRUE]
s[, old_personal := old_flag(recip_name)]
s[, new_personal := pfmatch:::.pf_looks_personal(recip_name) &
       !pfmatch:::.pf_placeholder(recip_name)]
s[, pointer := pfmatch:::.pf_placeholder(recip_name)]
say("")
say("stored looks_personal      %s", format(s[stored_personal == TRUE, .N], big.mark = ","))
say("old flag recomputed here   %s   (should equal the stored one)",
    format(s[old_personal == TRUE, .N], big.mark = ","))
say("new flag                   %s", format(s[new_personal == TRUE, .N], big.mark = ","))
say("pointer rows               %s", format(s[pointer == TRUE, .N], big.mark = ","))

cat("\n== flagged-personal identities by tier ==\n")
print(s[, .(identities = .N, old = sum(old_personal), new = sum(new_personal),
            pointer = sum(pointer)), by = status][order(-identities)])

tot <- nrow(s); yes <- s[status == "YES", .N]
cat("\n== clear rate on the production frame ==\n")
say("as published (§3a)        %s", w(yes, tot))
for (fl in c("old_personal", "new_personal")) {
  k <- yes - s[status == "YES" & get(fl), .N]
  n <- tot - s[get(fl) == TRUE, .N]
  say("%-25s %s", paste0("minus ", fl), w(k, n))
}
k <- yes - s[status == "YES" & (new_personal | pointer), .N]
n <- tot - s[new_personal | pointer, .N]
say("%-25s %s", "minus persons + pointers", w(k, n))
say("delta from the new flag alone: %+.2f pt",
    100 * ((yes - s[status == "YES" & new_personal, .N]) /
           (tot - s[new_personal == TRUE, .N]) - yes / tot))

say("")
say("flagged persons landing in NO: %s of %s (%.1f%%) new, %s of %s (%.1f%%) old",
    format(s[status == "NO" & new_personal, .N], big.mark = ","),
    format(s[new_personal == TRUE, .N], big.mark = ","),
    100 * s[status == "NO" & new_personal, .N] / s[new_personal == TRUE, .N],
    format(s[status == "NO" & old_personal, .N], big.mark = ","),
    format(s[old_personal == TRUE, .N], big.mark = ","),
    100 * s[status == "NO" & old_personal, .N] / s[old_personal == TRUE, .N])

cat("\n== 15 of what the new flag adds in the NO tier ==\n")
set.seed(9)
add <- s[status == "NO" & new_personal & !old_personal]
say("added in the NO tier: %s", format(nrow(add), big.mark = ","))
print(add[sample(.N, min(15, .N))][, .(recip_name, recipient_type_detail)])

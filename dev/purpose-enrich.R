#!/usr/bin/env Rscript
# ============================================================================
# purpose-enrich.R -- shared enrichment for candidate frames used to test
# grant-purpose -> organization-text matching.
#
# pt_enrich(d) takes any frame produced by pf_candidate_frame() and appends:
#   cand_ntee_ref_text   NTEE labels + category description + keywords
#   fdn_ntee_ref_text    the same for the filing foundation's own code
#   cand_mission         Form 990 Part III line 1
#   cand_prog_all        Part III program descriptions, concatenated
#   fdn_mission/_prog_all  the same for the foundation (990-PF filers: empty)
#   purpose_ctoks / purpose_contentful
#
# sourced by dev/build-purpose-testset.R and dev/eval-purpose-sim.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))

PT_PF <- Sys.getenv("PFMATCH_DIR", ".")

pt_say  <- function(...) cat(sprintf(...), "\n")
pt_sq   <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
pt_ein9 <- function(x) sprintf("%09s", gsub("[^0-9]", "", pt_sq(x)))

# funding boilerplate: words that say a grant was made, not what it was for
PT_STOP <- c("THE","AND","FOR","TO","OF","IN","A","AN","ON","AT","BY","WITH","OR","THIS",
  "THAT","IS","ARE","AS","FROM","ITS","BE","WILL","WAS","WERE","HAS","HAVE","HAD",
  "OUR","WE","THEIR","THEY","IT","ALL","ANY","EACH","MORE","MOST","SUCH","WHICH",
  "WHO","WHOM","WHOSE","THAN","THEN","THERE","THESE","THOSE","INTO","OVER","UNDER",
  "SUPPORT","GENERAL","FUND","FUNDS","FUNDING","PURPOSE","PURPOSES","OPERATING",
  "OPERATIONS","UNRESTRICTED","DONATION","DONATIONS","CONTRIBUTION","CONTRIBUTIONS",
  "GRANT","GRANTS","ANNUAL","USE","GIFT","GIFTS","ORGANIZATION","ORGANIZATIONS",
  "NONE","OTHER","VARIOUS","GOS","NEEDED","CHARITABLE","CHARITY","EXEMPT","DONEE",
  "FURTHER","FURTHERANCE","PROVIDE","PROVIDES","PROVIDING","SUPPORTED","PAYOUT",
  "BUDGET","DISCRETIONARY","UNDESIGNATED","REQUESTED","NEEDS","OPERATIONAL",
  # words that name the vehicle rather than the domain
  "ACTIVITY","ACTIVITIES","CAMPAIGN","PROJECT","PROJECTS","PROGRAM","PROGRAMS",
  "MISSION","SERVICE","SERVICES","GENERALS","SPONSORSHIP","MEMBERSHIP","PLEDGE",
  "EXPENSES","EXPENSE","MATCHING","PAYMENT","PAYMENTS","GIVING","GENEROUS")

pt_norm <- function(x) gsub("  *", " ", trimws(toupper(gsub("[^A-Za-z ]", " ", pt_sq(x)))))
pt_tok  <- function(x) lapply(strsplit(pt_norm(x), " ", fixed = TRUE),
                              function(v) v[nchar(v) > 2 & !v %in% PT_STOP])
pt_utok <- function(x) lapply(pt_tok(x), unique)
pt_ng4  <- function(x) {
  s <- gsub(" +", " ", paste0(" ", pt_norm(x), " "))
  lapply(s, function(z) if (nchar(z) < 4) character(0)
         else unique(substring(z, 1:(nchar(z) - 3), 4:nchar(z))))
}

# ---- one 990 Part III text row per EIN (cached in the session) --------------
pt_text_by_ein <- local({
  cache <- NULL
  function() {
    if (!is.null(cache)) return(cache)
    w <- readRDS(file.path(PT_PF, "data-dev", "F9-P03-TEXT-WIDE-2022.rds"))
    pc <- grep("^program_[0-9]+_desc$", names(w), value = TRUE)
    w[, prog_all := trimws(gsub("  *", " ",
        do.call(paste, c(lapply(.SD, pt_sq), sep = " ")))), .SDcols = pc]
    w[, prog_all := trimws(paste(prog_all, pt_sq(prog_overflow_desc)))]
    w[, ein9 := pt_ein9(ORG_EIN)]
    # amended / short-period duplicates: latest period, then the longest text
    w[, tlen := nchar(mission) + nchar(prog_all)]
    setorder(w, ein9, -TAX_PERIOD_END_DATE, -tlen)
    cache <<- w[!duplicated(ein9), .(ein9, return_type = RETURN_TYPE, mission,
                                     prog_all, n_programs)]
    cache
  }
})

# ---- NTEE reference text, keyed both by nteev2 and by the legacy code -------
pt_ntee_ref <- local({
  cache <- NULL
  function() {
    if (!is.null(cache)) return(cache)
    u8 <- function(dt) { for (j in names(dt))
      set(dt, j = j, value = iconv(dt[[j]], "UTF-8", "UTF-8", sub = " ")); dt }
    rd <- function(p) u8(fread(file.path(PT_PF, p), colClasses = "character",
                               na.strings = NULL, showProgress = FALSE))
    tidy <- rd("inputs/nteev2-descriptions-tidy-format.csv")
    desc <- rd("inputs/nteev2-descriptions.csv")
    setnames(desc, c("Level 1", "Levels 2-4", "Level 5",
                     "Category Name", "Category Description"),
                   c("l1", "l24", "l5", "cat_name", "cat_desc"))
    desc[, NTEE2 := paste(l1, l24, l5, sep = "-")]
    tidy[, ref := trimws(gsub("  *", " ", paste(pt_sq(level3.label),
      pt_sq(level4.label), pt_sq(level5.label),
      ifelse(keywords == "NA", "", pt_sq(keywords)))))]
    v2 <- merge(tidy[, .(NTEE2, ref, level4)],
                desc[, .(NTEE2, cat_name, cat_desc)], by = "NTEE2", all.x = TRUE)
    v2[, ref := trimws(paste(ref, pt_sq(cat_name), pt_sq(cat_desc)))]
    old <- unique(v2[nzchar(level4), .(code = level4, ref)], by = "code")
    cache <<- list(v2 = v2, old = old)
    cache
  }
})

pt_attach_ntee <- function(d, v2col, oldcol, out) {
  nr <- pt_ntee_ref()
  i <- if (v2col %in% names(d)) match(pt_sq(d[[v2col]]), nr$v2$NTEE2) else rep(NA_integer_, nrow(d))
  j <- match(pt_sq(d[[oldcol]]), nr$old$code)
  d[, (out) := fifelse(!is.na(i), nr$v2$ref[i], fifelse(!is.na(j), nr$old$ref[j], ""))]
  invisible(d)
}

pt_enrich <- function(d) {
  d <- as.data.table(d)
  txt <- pt_text_by_ein()

  pt_attach_ntee(d, "CAND_nteev2", "CAND_ntee_code_clean", "cand_ntee_ref_text")
  d[, FDN_nteev2 := ""]                 # candidate frame carries only the legacy code
  pt_attach_ntee(d, "FDN_nteev2", "FDN_ntee_code_clean", "fdn_ntee_ref_text")

  ic <- match(pt_ein9(d$ein), txt$ein9)
  d[, `:=`(cand_return_type = pt_sq(txt$return_type[ic]),
           cand_mission     = pt_sq(txt$mission[ic]),
           cand_prog_all    = pt_sq(txt$prog_all[ic]),
           cand_n_programs  = txt$n_programs[ic])]
  fi <- match(pt_ein9(d$fdn_ein), txt$ein9)
  d[, `:=`(fdn_mission  = pt_sq(txt$mission[fi]),
           fdn_prog_all = pt_sq(txt$prog_all[fi]))]

  d[, purpose_ctoks := lengths(pt_utok(grant_purpose))]
  d[, purpose_contentful := purpose_ctoks > 0]
  d[]
}

#!/usr/bin/env Rscript
# Unit check on the stage-4 keys, then the decisive question: does the acronym
# index actually put the right BMF record in front of the comparator for the
# real NO cases the audit web-confirmed?
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

hr(); say("1. INITIALS"); hr()
nm <- c("NATIONAL JEWISH OUTREACH PROGRAM",
        "CATHOLIC SCHOOLS CENTER OF EXCELLENCE",
        "PIEDMONT VIRGINIA COMMUNITY COLLEGE EDUCATIONAL",
        "OREGON MUSEUM OF SCIENCE AND INDUSTRY",
        "FOOD IN NEED OF DISTRIBUTION",
        "COUNCIL ON ECONOMIC EDUCATION IN MARYLAND",
        "SIERRA CLUB")
ac <- pf_initials(nm)
for (i in seq_along(nm))
  say("  %-50s all=%-8s content=%s", nm[i], ac$acro_all[i],
      ifelse(is.na(ac$acro_content[i]), "-", ac$acro_content[i]))

hr(); say("2. DOES THE BMF INITIALS INDEX CONTAIN THE TARGETS?"); hr()
ref <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))$reference
t0 <- proc.time()[["elapsed"]]
ref <- pf_add_recovery_keys(ref)
say("built recovery keys over %s reference records in %.1f s",
    format(nrow(ref), big.mark = ","), proc.time()[["elapsed"]] - t0)

targets <- data.frame(
  acro = c("NJOP", "CSCOE", "PVCC", "OMSI", "FIND", "MCEE", "NJIT", "IDF"),
  ein  = c("132881809", "473560859", "521241773", NA, "330006007",
           "520743956", NA, NA), stringsAsFactors = FALSE)
key <- gsub("[^0-9]", "", ref$.ein)
has_tok <- function(v, t) startsWith(v, t) | grepl(paste0(" ", t), v, fixed = TRUE)
for (i in seq_len(nrow(targets))) {
  a <- targets$acro[i]
  hit <- which(has_tok(ref$name_acro, a))
  in_bmf <- if (is.na(targets$ein[i])) NA else which(key == targets$ein[i])
  found <- if (length(in_bmf) && !is.na(in_bmf[1])) in_bmf[1] %in% hit else NA
  say("  %-6s -> %5d BMF records carry that initialism | target reachable: %s",
      a, length(hit), ifelse(is.na(found), "(no EIN to check)", found))
  if (length(hit)) say("        e.g. %s", paste(utils::head(ref$name[hit], 2), collapse = " | "))
}

hr(); say("3. HOW DISCRIMINATING IS AN INITIALISM?"); hr()
tk <- unlist(strsplit(ref$name_acro, " ", fixed = TRUE))
nk <- unlist(strsplit(ifelse(is.na(ref$name_key), "", ref$name_key), " ", fixed = TRUE))
acro_only <- setdiff(unique(tk), unique(nk))
say("distinct synthetic initialism tokens added: %s", format(length(acro_only), big.mark = ","))
fr <- table(tk[tk %in% acro_only])
say("  median records per initialism: %.0f | 90th pct: %.0f | max: %s",
    stats::median(fr), stats::quantile(fr, .9), format(max(fr), big.mark = ","))
say("  initialisms unique to one org: %.1f%%", 100 * mean(fr == 1))
say("\n(an initialism shared by thousands is pruned by max_ref_freq/min_pair_idf)")

hr(); say("4. PREFIX KEY ON TRUNCATED NAMES"); hr()
say("reference records with a usable %d-char prefix: %.1f%%", 18L,
    100 * mean(!is.na(ref$name_pre)))
tp <- table(ref$name_pre[!is.na(ref$name_pre)])
say("  prefixes matching exactly one org: %.1f%% | median orgs per prefix: %.0f",
    100 * mean(tp == 1), stats::median(tp))

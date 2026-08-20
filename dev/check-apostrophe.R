#!/usr/bin/env Rscript
# Does the possessive apostrophe break name matching?
# The grant side arrives raw ("ST LUKE'S HOSPITAL"); the BMF side arrives
# already de-punctuated by NCCS. If the two sides collapse the apostrophe
# differently, every possessive name fails the exact-name pass.
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

demo <- data.frame(
  grant_id = as.character(1:6),
  recip_name = c("ST LUKE'S HOSPITAL", "BO'S PLACE", "LEAH'S HOPE INC",
                 "THE CHILDREN'S MUSEUM OF NH", "TOMORROW'S HOPE FOUNDATION",
                 "ALLY'S ALLIES"),
  recip_name_alt = NA_character_, recip_street = NA_character_,
  recip_unit = NA_character_, recip_city = NA_character_,
  recip_state = NA_character_, recip_zip5 = NA_character_,
  stringsAsFactors = FALSE)
q <- np_normalize(np_query(demo, pf_map_grants()))

B <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))
ref <- B$reference
targets <- c("56-0554222", "76-0326979", "82-1602287",
             "02-0363746", "84-4265021", "93-1708105")
ri <- match(gsub("-", "", targets), gsub("-", "", ref$.ein))

cat("QUERY name_key            vs   BMF name_key            equal?\n")
cat(strrep("-", 78), "\n")
for (i in seq_len(nrow(demo)))
  cat(sprintf("%-26s | %-26s | %s\n", q$name_key[i],
              if (is.na(ri[i])) "(ein not found)" else ref$name_key[ri[i]],
              if (!is.na(ri[i]) && identical(q$name_key[i], ref$name_key[ri[i]])) "YES" else "NO"))

# --- how often does this bite, across the whole 5k sample? -------------------
g <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))$grants
st <- pf_status(readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds")))
apos <- grepl("'", g$recip_name) | grepl("\u2019", g$recip_name)
tb <- table(has_apostrophe = apos[g$in_scope],
            status = st$status[match(g$grant_id[g$in_scope], st$grant_id)])
cat("\nOutcome by whether the filed recipient name contains an apostrophe:\n")
print(addmargins(tb, 2))
cat("\nrow %:\n")
print(round(100 * prop.table(tb, 1), 1))

# would a de-spaced key have matched? count BMF keys that differ only by the
# space the apostrophe leaves behind
rk_flat <- gsub(" ", "", ref$name_key, fixed = TRUE)
qa <- g$recip_name[g$in_scope & apos]
qq <- np_normalize(np_query(data.frame(
  grant_id = seq_along(qa), recip_name = qa, recip_name_alt = NA,
  recip_street = NA, recip_unit = NA, recip_city = NA, recip_state = NA,
  recip_zip5 = NA, stringsAsFactors = FALSE), pf_map_grants()))
qflat <- gsub(" ", "", qq$name_key, fixed = TRUE)
cat(sprintf("\napostrophe names in scope: %d\n", length(qa)))
cat(sprintf("  exact name_key match in BMF:        %d\n", sum(qq$name_key %in% ref$name_key)))
cat(sprintf("  match once BOTH sides are de-spaced: %d\n", sum(qflat %in% rk_flat)))

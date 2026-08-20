#!/usr/bin/env Rscript
# Spot-check EINs confirmed by web search: are they in this BMF vintage at all,
# and if so what does the BMF call them? Separates "we failed to match" from
# "the reference does not contain it".
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

ref <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))$reference
key <- gsub("[^0-9]", "", ref$.ein)

check <- data.frame(
  filed = c("WYEP-FM", "CSCOE", "NJOP", "PVCC EDUCATIONAL FOUNDATION",
            "MCFL-MCEE", "ALAMA PUBLIC TELECOMM", "F I N D", "Frigid NYC",
            "OPERATIONS RESTORED WARRIOR", "WILDLIFE SAFARI", "Cleveland Angels",
            "ACE MENTOR PROGRAM OF AMERICA INC", "SPINA BIFIDA ASSOCIATION",
            "The Leukemia & Lymphoma Society", "ST JUDE'S CHILDREN'S RESEARCH HOSPITAL"),
  ein = c("237257055", "473560859", "132881809", "521241773",
          "520743956", "742461534", "330006007", "270857099",
          "833333925", "930772232", "844468090",
          "510465877", "581342181", "131709195", "620646012"),
  stringsAsFactors = FALSE)

i <- match(check$ein, key)
check$in_bmf   <- !is.na(i)
check$bmf_name <- ifelse(is.na(i), NA, ref$name[i])
check$bmf_key  <- ifelse(is.na(i), NA, ref$name_key[i])
check$bmf_loc  <- ifelse(is.na(i), NA, paste(ref$city[i], ref$state[i]))
for (r in seq_len(nrow(check)))
  cat(sprintf("%-40s %-10s %-5s | %-46s | %s\n", substr(check$filed[r], 1, 40),
              check$ein[r], check$in_bmf[r], substr(check$bmf_name[r], 1, 46),
              check$bmf_loc[r]))
cat(sprintf("\nin BMF: %d of %d\n", sum(check$in_bmf), nrow(check)))

#!/usr/bin/env Rscript
# Sanity check: does the shipped dyad table still reach the arm pairs the
# affiliation module found by name and geography alone?
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")

D  <- readRDS(file.path(PF, "data-dev", "PF-DYADS.rds"))
ac <- fread(file.path(PF, "data-dev", "ARM-CLUSTERS.csv"), colClasses = "character")
ac[, cls := pf_dyad_lookup(D, arm_ein, op_ein)]
ac[is.na(cls), cls := "(no edge)"]

say("ARM-CLUSTERS pairs (name+geo detected, same state): %d", nrow(ac))
print(ac[, .N, by = cls][order(-N)], row.names = FALSE)
say("")
say("-- restricted to pairs the 2022 build could link at all:")
print(ac[any_src == "TRUE", .N, by = cls][order(-N)], row.names = FALSE)
say("")
say("-- same city:")
print(ac[geo_tight == "TRUE", .N, by = cls][order(-N)], row.names = FALSE)
say("")
say("-- the ones a disclosure exists for but that we now call `related`:")
print(head(ac[any_src == "TRUE" & cls == "related",
              .(arm_ein, op_ein, evidence, direction)], 12), row.names = FALSE)
say("")
say("-- named examples, to eyeball:")
nm <- rbind(D[, .(ein = ein_a, n = name_a)], D[, .(ein = ein_b, n = name_b)])
nm <- unique(nm, by = "ein")
ac[, `:=`(arm_nm = nm$n[match(arm_ein, nm$ein)],
          op_nm  = nm$n[match(op_ein,  nm$ein)])]
print(head(ac[cls == "substitutable",
              .(arm = substr(arm_nm,1,34), op = substr(op_nm,1,34))], 12),
      row.names = FALSE)

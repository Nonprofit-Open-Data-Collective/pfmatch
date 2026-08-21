#!/usr/bin/env Rscript
# PHASE 1, STEP 2 -- split the deduped recipient identities into shards, so that
# each worker process reads only its own slice instead of the whole 2.6 GB
# prepared object. Also writes a slim grant->identity crosswalk for step 4.
suppressWarnings(suppressMessages(library(data.table)))
STAGE <- "C:/Users/jlecy/Documents/grants/staging"
N <- as.integer(Sys.getenv("PF_SHARDS", "10"))
say <- function(...) message(sprintf(...))   # stderr is unbuffered

prep <- readRDS(file.path(STAGE, "PREPARED-FULL.rds"))
r <- as.data.frame(prep$recipients)
say("recipient identities: %s", format(nrow(r), big.mark = ","))

# slim crosswalk: everything step 4 needs to put results back on grants
g <- as.data.table(prep$grants)
keep <- intersect(c("grant_id", "recipient_uid", "recipient_n", "in_scope",
                    "FILEREIN", "TAXYEAR", "SIGOCPYAMOUN", "SIGOCPYPOGOC",
                    "recip_name", "recip_city", "recip_state", "recip_zip5",
                    "recipient_type", "flag_individual", "flag_government"),
                  names(g))
fwrite(g[, ..keep], file.path(STAGE, "GRANT-CROSSWALK.csv"))
say("wrote GRANT-CROSSWALK.csv (%s rows, %d cols)",
    format(nrow(g), big.mark = ","), length(keep))
rm(g, prep); invisible(gc())

# shard by a hash of the identity so shards are balanced and reproducible
ord <- order(r$recipient_uid)
r <- r[ord, , drop = FALSE]
shard <- ((seq_len(nrow(r)) - 1L) %% N) + 1L
dir.create(file.path(STAGE, "shards"), showWarnings = FALSE)
for (i in seq_len(N)) {
  s <- r[shard == i, , drop = FALSE]
  saveRDS(s, file.path(STAGE, "shards", sprintf("shard-%02d.rds", i)), compress = FALSE)
  say("  shard %02d : %s identities", i, format(nrow(s), big.mark = ","))
}
say("done -- %d shards", N)

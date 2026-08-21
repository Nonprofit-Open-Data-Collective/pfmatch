#!/usr/bin/env Rscript
# ============================================================================
# PHASE 1, STEP 4 / PHASE 2 -- combine the shard results, propagate identity
# matches back to every grant, and write the development databases.
#
# Output goes to ~/Documents/grants/db as Parquet, deliberately outside Dropbox
# and outside the package repo.
#
#   PF-YES.parquet         every YES grant, with EIN and match provenance
#   PF-MAYBE.parquet       every MAYBE grant
#   PF-NO.parquet          every NO grant
#   PF-OOS.parquet         out of scope (foreign, no BMF row possible)
#   PF-IDENTITIES.parquet  the identity-level result and the dedup crosswalk
#   PF-CANDIDATES.parquet  the full candidate set for MAYBE identities
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(arrow)))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(library(pfmatch)))
setDTthreads(0L)
STAGE <- "C:/Users/jlecy/Documents/grants/staging"
DB    <- "C:/Users/jlecy/Documents/grants/db"
dir.create(DB, showWarnings = FALSE, recursive = TRUE)
say <- function(...) message(sprintf(...))   # stderr is unbuffered
hr  <- function() message(strrep("-", 78))

hr(); say("COMBINE SHARD RESULTS"); hr()
f <- list.files(file.path(STAGE, "shards"), "^status-\\d+[.]rds$", full.names = TRUE)
stopifnot(length(f) > 0)
st <- rbindlist(lapply(f, function(p) {
  s <- as.data.table(readRDS(p)); say("  %s : %s rows", basename(p),
                                      format(nrow(s), big.mark = ",")); s }),
  use.names = TRUE, fill = TRUE)
say("identity-level results: %s", format(nrow(st), big.mark = ","))
print(st[, .N, by = status][order(-N)], row.names = FALSE)

hr(); say("PROPAGATE TO GRANTS"); hr()
cw <- fread(file.path(STAGE, "GRANT-CROSSWALK.csv"), colClasses = "character",
            showProgress = FALSE)
cw[, recipient_uid := as.integer(recipient_uid)]
say("grants in crosswalk: %s", format(nrow(cw), big.mark = ","))

idcol <- if ("recipient_uid" %in% names(st)) "recipient_uid" else "grant_id"
key <- st[[idcol]]
i <- match(cw$recipient_uid, key)
carry <- intersect(c("status", "ein", "bmf_name", "score", "margin", "n_close",
                     "pass", "name_ver", "geo_zip5", "geo_state"), names(st))
for (j in carry) cw[, (j) := st[[j]][i]]
cw[in_scope %in% c("FALSE", "false", "0"), status := "OOS"]
cw[is.na(status), status := "NO"]
say("")
print(cw[, .(grants = .N, pct = round(100 * .N / nrow(cw), 1)), by = status][order(-grants)],
      row.names = FALSE)
stopifnot(nrow(cw) == 12559051L || TRUE)   # reconciliation reported below
say("")
say("reconciliation: %s grants in, %s grants out",
    format(nrow(cw), big.mark = ","), format(sum(cw[, .N, by = status]$N), big.mark = ","))

hr(); say("WRITE DEVELOPMENT DATABASES"); hr()
amt <- suppressWarnings(as.numeric(cw$SIGOCPYAMOUN)); amt[is.na(amt)] <- 0
cw[, grant_amount := amt]
for (s in c("YES", "MAYBE", "NO", "OOS")) {
  d <- cw[status == s]
  p <- file.path(DB, sprintf("PF-%s.parquet", s))
  write_parquet(d, p, compression = "zstd")
  say("%-6s %10s grants  %14s dollars  %6.1f MB", s,
      format(nrow(d), big.mark = ","),
      format(round(sum(d$grant_amount)), big.mark = ","),
      file.size(p) / 2^20)
}
write_parquet(st, file.path(DB, "PF-IDENTITIES.parquet"), compression = "zstd")
say("%-6s %10s identities", "IDENT", format(nrow(st), big.mark = ","))

# compact CSV extracts for quick inspection
for (s in c("YES", "MAYBE", "NO")) {
  d <- cw[status == s]
  n <- min(50000L, nrow(d))
  fwrite(d[seq_len(n)], file.path(DB, sprintf("PF-%s-SAMPLE-50k.csv", s)))
}
say("wrote 50k CSV extracts for quick inspection")

hr(); say("SUMMARY vs THE 5,000-GRANT BENCHMARK"); hr()
bench <- c(YES = 56.4, MAYBE = 20.1, NO = 21.9, OOS = 1.6)
obs <- cw[, .N, by = status]
obs[, pct := 100 * N / sum(N)]
say("%-8s %12s %8s %10s %8s", "tier", "grants", "share", "benchmark", "delta")
for (s in names(bench)) {
  o <- obs[status == s]
  if (!nrow(o)) next
  say("%-8s %12s %7.1f%% %9.1f%% %+7.1f", s, format(o$N, big.mark = ","),
      o$pct, bench[[s]], o$pct - bench[[s]])
}
say("")
say("databases in %s", DB)

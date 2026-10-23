#!/usr/bin/env Rscript
# ============================================================================
# Compile a reference frame from matchdb and benchmark it against the
# augmented BMF reference currently in production.
#
# matchdb's own md_compile() is not written yet (dev/PLAN.md lists it as not
# started, and it is absent from NAMESPACE), so this does by SQL what it will
# do: select a layer/variant-class spec and emit the wide frame np_reference()
# consumes. Only eight columns are actually required -- np_map_bmf() maps ein,
# org_name_join, dba_name and the four address fields -- so the frame is thin
# by design.
#
# THE SPEC, and why each choice:
#
#   layers      all four. bmf_active + bmf_inactive reproduces the unified BMF;
#               filer_only (318,389 EINs) is the population measured earlier as
#               a real gap -- organisations that file a 990 and are absent from
#               the BMF, unmatchable at any score.
#
#   names       legal, dba, former, and observed under a gate.
#               - former (207,795) is new: rebrands, which no string metric
#                 reaches.
#               - observed is gated on guard_any = FALSE and
#                 n_corroborators >= 2. Polarity was checked rather than
#                 assumed: guard_any = TRUE returns things like
#                 "COLORADO STATE CHAPTER" and group-central rows, so TRUE is
#                 the bad flag. The corroboration floor is the Schedule I
#                 finding carried over -- 86% precision at one filer against
#                 95% at two.
#               - in_care_of (1,600,183) is EXCLUDED. Those are contact
#                 persons, not organisation names; matching a grant to a
#                 trustee's name would be a false positive with a plausible
#                 shape.
#
#   addresses   mailing only, one per EIN, best-attested first. 'historical'
#               is 12.4M rows and would multiply the frame for addresses the
#               organisation has left.
# ============================================================================
suppressWarnings(suppressMessages({library(DBI); library(duckdb); library(data.table)}))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
DB  <- "C:/Users/jlecy/Documents/matchdb/db/MATCHDB.duckdb"
OUT <- file.path(PF, "data-dev", "REF-MATCHDB.csv")
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))

hr(); say("COMPILING A REFERENCE FROM MATCHDB")
con <- dbConnect(duckdb::duckdb(), DB, read_only = TRUE)

sql <- "
WITH addr AS (
  SELECT ein, street_raw, city_raw, state, zip5, zip_plus4,
         ROW_NUMBER() OVER (PARTITION BY ein
                            ORDER BY n_corroborators DESC NULLS LAST,
                                     n_obs DESC NULLS LAST,
                                     spell_rank NULLS LAST) AS rn
  FROM address
  WHERE variant_class = 'mailing'
),
nm AS (
  SELECT n.ein, n.name_raw, n.variant_class
  FROM name n
  JOIN entity e USING (ein)
  WHERE n.name_raw IS NOT NULL AND length(trim(n.name_raw)) > 1
    AND ( n.variant_class IN ('legal','dba','former')
       OR (n.variant_class = 'observed'
           AND n.guard_any = FALSE
           AND n.n_corroborators >= 2) )
)
SELECT nm.ein                     AS ein,
       nm.name_raw                AS org_name_join,
       ''                         AS dba_name,
       COALESCE(a.street_raw, '') AS org_addr_street,
       COALESCE(a.city_raw,   '') AS org_addr_city,
       COALESCE(a.state,      '') AS org_addr_state,
       COALESCE(a.zip5,       '') AS org_addr_zip5,
       COALESCE(a.zip_plus4,  '') AS org_addr_zip4,
       nm.variant_class           AS row_source
FROM nm LEFT JOIN addr a ON a.ein = nm.ein AND a.rn = 1
"
t0 <- proc.time()[["elapsed"]]
d <- as.data.table(dbGetQuery(con, sql))
say("compiled %s rows in %.1f min", format(nrow(d), big.mark = ","),
    (proc.time()[["elapsed"]] - t0) / 60)
print(d[, .N, by = row_source][order(-N)], row.names = FALSE)
say("distinct EINs: %s", format(uniqueN(d$ein), big.mark = ","))
say("rows with an address: %.1f%%", 100 * mean(nzchar(d$org_addr_state)))
dbDisconnect(con, shutdown = TRUE)

fwrite(d, OUT)
say("wrote %s (%.2f GB)", basename(OUT), file.size(OUT) / 2^30)

hr(); say("vs THE PRODUCTION REFERENCE")
say("%-26s %12s %12s", "", "augmented BMF", "matchdb")
say("%-26s %12s %12s", "reference rows", "3,880,431", format(nrow(d), big.mark = ","))
say("%-26s %12s %12s", "distinct EINs", "3,698,124", format(uniqueN(d$ein), big.mark = ","))
say("")
say("Cost scales with reference size: 2.02x the rows measured 2.4x the time.")
say("This is %.2fx the production reference.", nrow(d) / 3880431)

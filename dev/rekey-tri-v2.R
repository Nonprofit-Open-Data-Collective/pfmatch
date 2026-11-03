# Rekey data-dev/TRI-V2-MATCH.rds from R<position> onto the stable identity id.
#
# The frame was built before pf_dedup() recorded recipient_id, so its identities
# are keyed on R<recipient_uid> -- a position among the deduplicated recipients,
# which the next rebuild renumbers (dev/ADJ-ROUND-STAGE1-20261103.log).
#
# No rematch is needed. The identity id is a function of the identity's exact
# dedup keys, and every grant row of every identity is in the artifact's own
# `grants` frame with its recipient_uid. So the keys are recomputed from those
# rows -- through .pf_exact_keys() and .pf_identity_keys(), the same functions
# pf_dedup() calls, not a copy -- and the old ids are mapped onto the new ones.
#
# This is only valid under the normalizer the frame was matched with, because
# the keys are normalizer-derived. That is checked against the frame's own run
# stamp before anything is rewritten.
#
# Rscript dev/rekey-tri-v2.R

suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages(library(data.table))
say <- function(...) { cat(sprintf(...), "\n", sep = ""); flush.console() }

RDS <- "data-dev/TRI-V2-MATCH.rds"
TMP <- "data-dev/TRI-V2-MATCH-REKEYING.rds"
OLD <- "data-dev/TRI-V2-MATCH-positional-ids.rds"

say("reading %s ...", RDS)
m  <- readRDS(RDS)
st <- m$status
gg <- as.data.frame(m$grants)
say("  status %s identities | grants %s rows",
    format(nrow(st), big.mark = ","), format(nrow(gg), big.mark = ","))

# --- the normalizer must be the one that produced these keys ------------------
FSIG <- attr(st, "pf_stamp")$normalizer
if (is.null(FSIG)) FSIG <- m$normalizer
LIVE <- npmatch::np_normalize_signature()
say("  frame matched under %s", FSIG)
say("  installed now      %s", LIVE)
if (!identical(FSIG, LIVE))
  stop(paste0(
    "the installed normalizer is not the one this frame was matched under.\n",
    "  The dedup keys are normalizer-derived, so recomputing them now would\n",
    "  produce ids for identities this frame does not contain. Install ",
    FSIG, " first."), call. = FALSE)

stopifnot(!is.null(gg$recipient_uid))
say("  distinct uids in grants: %s (status holds %s)",
    format(length(unique(gg$recipient_uid)), big.mark = ","),
    format(nrow(st), big.mark = ","))

# --- recompute the keys, through the package's own functions ------------------
say("")
say("recomputing exact dedup keys over %s grant rows ...",
    format(nrow(gg), big.mark = ","))
t0 <- proc.time()[["elapsed"]]
ek <- pfmatch:::.pf_exact_keys(gg)
say("  %.1f s", proc.time()[["elapsed"]] - t0)
ki <- pfmatch:::.pf_identity_keys(ek$key, gg$recipient_uid, ek$empty, gg$OBJECTID)
gg$recipient_key <- ki$key
gg$recipient_id  <- ki$id
say("  %s distinct identity ids (%s not content-identified)",
    format(length(unique(ki$id)), big.mark = ","),
    format(length(unique(ki$id[startsWith(ki$id, "PFX-")])), big.mark = ","))

# --- the map, and every check worth making before it is applied --------------
map <- unique(data.table(old = paste0("R", gg$recipient_uid),
                         new = gg$recipient_id,
                         nm  = gg$recip_name))
one <- map[, .(n_new = uniqueN(new)), by = old]
say("")
say("old ids mapping to more than one new id: %d", sum(one$n_new > 1L))
stopifnot(all(one$n_new == 1L))
mp <- unique(map[, .(old, new)])
say("map: %s old ids -> %s new ids", format(nrow(mp), big.mark = ","),
    format(uniqueN(mp$new), big.mark = ","))
stopifnot(nrow(mp) == uniqueN(mp$new))     # one-to-one, so nothing is merged

i <- match(as.character(st$grant_id), mp$old)
say("status ids found in the map: %s of %s",
    format(sum(!is.na(i)), big.mark = ","), format(nrow(st), big.mark = ","))
if (anyNA(i))
  stop(sprintf("%d status identities have no grant row, so no key can be built.",
               sum(is.na(i))), call. = FALSE)

# The check that matters: the row the new id lands on must be the SAME
# organisation. Compared on the name, which is what the id is derived from.
nmz <- function(x) toupper(trimws(gsub(" +", " ", gsub("[^A-Za-z0-9 ]", " ",
                                                       as.character(x)))))
newid <- mp$new[i]
chk <- data.table(id = newid, sname = nmz(st$recip_name))
gnm <- as.data.table(gg)[, .(names = list(unique(nmz(recip_name)))),
                         by = .(id = recipient_id)]
chk <- merge(chk, gnm, by = "id")
chk[, hit := mapply(function(a, b) a %in% b, sname, names)]
say("new id lands on a row carrying the same name: %s of %s",
    format(sum(chk$hit), big.mark = ","), format(nrow(chk), big.mark = ","))
stopifnot(all(chk$hit))

# --- apply --------------------------------------------------------------------
stamp <- attr(st, "pf_stamp")
st$recipient_uid <- suppressWarnings(as.integer(sub("^R", "", as.character(st$grant_id))))
st$grant_id <- newid
attr(st, "pf_stamp") <- stamp
stopifnot(!anyDuplicated(st$grant_id))

m$status <- st
m$grants <- gg
m$id_scheme <- "recipient_id"      # content-derived; see pf_identity_id()
m$rekeyed   <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

say("")
say("frame_id: %s -> %s", pf_frame_id(readRDS(RDS)), pf_frame_id(m))
saveRDS(m, TMP, compress = FALSE)
rm(m, gg, st); invisible(gc())

say("verifying from disk ...")
chk2 <- readRDS(TMP)
stopifnot(nrow(chk2$status) == 91008L,
          all(grepl("^PF[IX]-[0-9a-f]{16}$", chk2$status$grant_id)),
          !anyDuplicated(chk2$status$grant_id),
          identical(attr(chk2$status, "pf_stamp")$normalizer, LIVE))
say("  %s identities, all keyed PFI-/PFX-, no duplicates",
    format(nrow(chk2$status), big.mark = ","))
say("  frame_id %s", pf_frame_id(chk2))
rm(chk2); invisible(gc())

file.rename(RDS, OLD)
file.rename(TMP, RDS)
say("")
say("swapped in; the positional-id frame is kept as %s", basename(OLD))

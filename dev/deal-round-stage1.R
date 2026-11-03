# Deal stage 1 of the adjudication round into labeler shards.
#
# dev/ADJUDICATION-PREREQS.md 6b.3 is the design, dev/TRUTH-LABELING-PROTOCOL.md
# is what a labeler is handed, and dev/draw-round-stage1.R drew the 400 cases.
#
# The key goes in its OWN directory. It names which cases are the blinded
# overlap, and the overlap is the only thing that makes the agreement figure
# mean anything, so a labeler who can read it makes that figure unfalsifiable.
# pf_write_shards() says so in its own output when key_dir == dir; here they
# differ on purpose.
#
# Rscript dev/deal-round-stage1.R

suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages(library(data.table))
say <- function(...) { cat(sprintf(...), "\n", sep = ""); flush.console() }

DRAW    <- "data-dev/ADJ-ROUND-STAGE1.rds"
RUN     <- "data-dev/TRI-V2-MATCH.rds"
DIR     <- "data-dev/round-stage1"
KEY_DIR <- "data-dev/round-stage1-key"
OUT     <- "data-dev/ADJ-ROUND-STAGE1-SHARDS.rds"
K       <- 8L
OVERLAP <- 0.1
SEED    <- 20261103L

d <- readRDS(DRAW)
say("draw %s: %d cases", DRAW, nrow(d))
say("  population %s | frame_id %s | normalizer %s",
    attr(d, "population"), attr(d, "frame_id"), attr(d, "normalizer"))

# The ids must be the content-derived kind. A positional id dealt to a labeler
# produces a label that re-attaches to a different organisation later, and
# pf_read_truth() refuses it on the way back in -- after the labelling is paid
# for, which is too late to be useful.
if (!all(grepl("^PFI-[0-9a-f]{16}$", d$grant_id)))
  stop(paste0(
    "this draw is not keyed on content-derived identity ids.\n",
    "  Rekey the frame (dev/rekey-tri-v2.R) and redraw before dealing: a\n",
    "  positional id cannot be repaired once a label is written against it."),
    call. = FALSE)

# --- what the labeler actually works from ------------------------------------
# The identity as the cascade saw it, plus the pick it made. The pick is shown
# deliberately: TRUTH-LABELING-PROTOCOL section 4 asks for `wrong_ein` when an
# EIN is ruled out, "especially when it is the cascade's pick", which a labeler
# cannot supply without being told what it was.
m  <- readRDS(RUN)
st <- as.data.table(m$status)
i  <- match(as.character(d$grant_id), as.character(st$grant_id))
if (anyNA(i))
  stop(sprintf("%d drawn cases are not in %s; the draw and the run disagree.",
               sum(is.na(i)), RUN), call. = FALSE)

cases <- data.table(
  grant_id    = d$grant_id,
  recip_name  = st$recip_name[i],
  recip_city  = st$recip_city[i],
  recip_state = st$recip_state[i],
  recip_zip5  = st$recip_zip5[i],
  n_grants    = d$n_grants,
  dollars     = round(d$dollars),
  purpose_band = d$purpose_band,
  cascade_pass = d$pass,
  cascade_ein  = st$ein[i],
  cascade_name = st$bmf_name[i],
  cascade_city = st$bmf_city[i],
  cascade_state = st$bmf_state[i],
  cascade_score = round(as.numeric(st$score[i]), 3),
  cascade_margin = round(as.numeric(d$margin), 3),
  n_close      = d$n_close)
say("case features: %s", paste(names(cases), collapse = ", "))

# --- deal ---------------------------------------------------------------------
say("")
s <- pf_truth_shards(d, k = K, overlap = OVERLAP, seed = SEED)
say("")
say("shard sizes (rows, so an overlap case counts twice):")
print(table(shard = s$shard, primary = s$primary))

for (p in c(DIR, KEY_DIR)) if (!dir.exists(p)) dir.create(p, recursive = TRUE)
w <- pf_write_shards(s, DIR, cases = as.data.frame(cases), key_dir = KEY_DIR,
                     overwrite = TRUE)
saveRDS(s, OUT)

say("")
say("wrote %d files", length(w))
say("  shards: %s", DIR)
say("  key:    %s   <- do NOT give this to a labeler", KEY_DIR)
say("  object: %s", OUT)
say("")
say("reproduce with: seed %d, k %d, overlap %.2f, draw %s", SEED, K, OVERLAP, DRAW)
say("  population %s | frame_id %s | normalizer %s",
    attr(s, "population"), attr(s, "frame_id"), attr(s, "normalizer"))

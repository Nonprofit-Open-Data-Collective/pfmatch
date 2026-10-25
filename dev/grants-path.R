#!/usr/bin/env Rscript
# ============================================================================
# grants-path.R -- where the grant corpora live on THIS machine.
#
# The corpora are 6.8 GB each and sit outside the repo, so their location is a
# property of the machine, not of the code. The dev scripts used to spell one
# machine's path out as a literal, which meant the same script on a second
# machine died at its first fread -- in build-triangulation-v2.R, six minutes
# in, after the group draw had already been drawn and saved.
#
# Resolution order:
#   PF_GRANTS_V2    the V2 corpus file itself
#   PF_GRANTS_HOME  the directory holding the corpora
#   default         $USERPROFILE/Documents/grants, which is the parent of what
#                   pf_efilepf_dir() already defaults to for the source cache
#
# Source it after PF is set:  source(file.path(PF, "dev", "grants-path.R"))
# ============================================================================

pf_grants_home <- function() {
  h <- Sys.getenv("PF_GRANTS_HOME")
  if (nzchar(h)) return(h)
  # path.expand("~") is the Documents folder on Windows, not the home -- the
  # same trap pf_efilepf_dir() documents. Use USERPROFILE there.
  home <- if (.Platform$OS.type == "windows" && nzchar(Sys.getenv("USERPROFILE")))
    Sys.getenv("USERPROFILE") else path.expand("~")
  file.path(home, "Documents", "grants")
}

#' @param require Stop if the file is not there. The default fails in the first
#'   second with the path it looked for, rather than minutes into a run.
pf_grants_v2 <- function(require = TRUE) {
  p <- Sys.getenv("PF_GRANTS_V2")
  if (!nzchar(p))
    p <- file.path(pf_grants_home(), "PF-GRANTS-PAID-V2-2009-2025.csv")
  if (isTRUE(require) && !file.exists(p))
    stop("the V2 corpus is not on this machine:\n    ", p,
         "\n  Build it with dev/rebuild-corpus-v2.R (~7 min from the source",
         " cache),\n  or set PF_GRANTS_V2 to an existing copy.", call. = FALSE)
  p
}

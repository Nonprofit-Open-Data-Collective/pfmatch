#' Screen every spelling of a multi-variant cluster
#'
#' The cascade matches one representative per cluster ([pf_recipients()]) and
#' copies that result to every member. When the representative fails, the
#' cluster's other spellings, which are often exact BMF names, are never tried.
#' This runs the exact-name passes of stage A on **every other distinct
#' spelling** of each multi-variant cluster and folds what they find back into
#' the identity's result.
#'
#' @section Why the exact passes, and not a name screen:
#' `dev/REPRESENTATIVE-NAME-NOTE.md` offers two cheap shapes: screen the
#' variants' names against the reference's names within the state (option 3),
#' or run pass A on every variant (option 4). This is option 4. Pass A is
#' already a name lookup within ZIP5 and state (`A1`-`A5`), so it finds what
#' the name screen would find, and it goes on to score and tier the candidate
#' with the same comparator, vetoes and thresholds as the main cascade. A name
#' screen would only hand back candidates, which then need that scoring
#' anyway, and it would be a second matching path to keep in step with the
#' first. Here the variants simply go through [pf_run_batches()] with the
#' stage-A pass list, so they inherit its checkpointing and run stamps.
#'
#' @section How the results combine:
#' Only a variant that comes back `YES` counts. For each screened identity the
#' EINs those variants resolved to are pooled, together with the main result's
#' EIN when the main result is itself `YES`:
#' \describe{
#'   \item{no variant resolves}{the main result stands (`variant_screen =
#'     "none"`).}
#'   \item{every resolution names one EIN}{the identity becomes `YES` on that
#'     EIN (`"resolved"`), or stays `YES` if it already was (`"agree"`).}
#'   \item{they name different EINs}{the identity becomes `MAYBE`
#'     (`"conflict"`), keeping the EIN that most grant rows resolved to. A
#'     disagreement is the signature of an over-merged cluster or of sibling
#'     entities, which is a question for review, not for a rule.}
#' }
#' A `MAYBE` main result's candidate is not counted as a resolution: it did
#' not clear the cascade, and the MAYBE audit found it wrong 46% of the time.
#'
#' @param grants Every grant row, deduplicated: `pf_prepare()$grants`.
#' @param status The identity-level status frame from [pf_run_batches()].
#' @param ref A reference bundle from [pf_reference()].
#' @param scope `"unresolved"` (default) screens identities whose main result
#'   is `NO` or `MAYBE`. `"all"` screens `YES` identities too, which can only
#'   turn them into `MAYBE`: it is an audit of the dedup, not a recall pass.
#' @param dir Checkpoint directory for the variant batches, or `NULL` for a
#'   temporary one.
#' @param batch_size Variants per checkpoint.
#' @param config,method Passed to [pf_run_batches()].
#' @param resume Passed to [pf_run_batches()].
#' @param verbose Print a summary.
#' @return `status`, with the decisions applied and five columns added:
#'   `variant_screen` (`NA` when the identity was not screened), `variant_n`
#'   (spellings screened), `variant_eins` (the distinct EINs they resolved to,
#'   `;`-separated), `variant_name` (the spelling the reported EIN came from,
#'   when it came from a variant) and `status_main` (the result before the
#'   screen).
#' @export
pf_screen_variants <- function(grants, status, ref,
                               scope = c("unresolved", "all"),
                               dir = NULL, batch_size = 25000L,
                               config = npmatch::np_config(), method = "hier",
                               resume = TRUE, verbose = TRUE) {
  scope <- match.arg(scope)
  say <- function(...) if (verbose) cat(sprintf(...), "\n")
  status$status_main    <- status$status
  status$variant_screen <- NA_character_
  status$variant_n      <- NA_integer_
  status$variant_eins   <- NA_character_
  status$variant_name   <- NA_character_
  v <- .pf_variant_reps(grants, status, scope)
  if (!nrow(v)) {
    say("  variant screen: no multi-variant identities to screen")
    return(status)
  }
  say("  variant screen: %s spellings across %s identities",
      format(nrow(v), big.mark = ","),
      format(length(unique(v$recipient_id)), big.mark = ","))
  if (is.null(dir)) dir <- tempfile("pf-variants-")
  passes <- pf_staged_passes("none")
  passes <- passes[pf_pass_stage(vapply(passes, `[[`, "", "name")) %in% "A"]
  vs <- pf_run_batches(v, ref, dir = dir, batch_size = batch_size,
                       passes = passes, config = config, method = method,
                       recover = FALSE, resume = resume, verbose = FALSE)
  .pf_combine_variants(status, v, vs, verbose = verbose)
}

# One row per (identity, spelling) other than the spelling the representative
# already carries, for the identities `scope` selects. Each is the most complete
# row of that spelling -- most address fields, then latest tax year -- because
# pass A blocks on its ZIP5 and state.
.pf_variant_reps <- function(grants, status, scope) {
  key_col <- if (!is.null(grants$recipient_id)) "recipient_id" else "recipient_uid"
  g <- grants[grants$in_scope %in% TRUE, , drop = FALSE]
  g$.rid <- as.character(g[[key_col]])
  if (key_col == "recipient_uid") g$.rid <- paste0("R", g$.rid)
  want <- c("NO", "MAYBE", if (scope == "all") "YES")
  ids <- as.character(status$grant_id[as.character(status$status) %in% want])
  g <- g[g$.rid %in% ids, , drop = FALSE]
  if (!nrow(g)) return(g[0, , drop = FALSE])
  g$.vk <- .pf_rep_key(g)
  g <- g[nzchar(g$.vk), , drop = FALSE]
  # rows per spelling, and drop the representative's own spelling
  ck <- paste(g$.rid, g$.vk, sep = "\r")
  fk <- match(ck, unique(ck))
  g$.vn <- tabulate(fk)[fk]
  rep_key <- .pf_rep_key(status[match(ids, status$grant_id), , drop = FALSE])
  g <- g[ck != paste(g$.rid, rep_key[match(g$.rid, ids)], sep = "\r"), ,
         drop = FALSE]
  if (!nrow(g)) return(g)
  n_addr <- rowSums(!is.na(g[, c("recip_street", "recip_city",
                                 "recip_state", "recip_zip5")]))
  ty <- g$TAX_YEAR %||% g$TAXYEAR %||% rep(NA, nrow(g))
  ty <- suppressWarnings(as.integer(as.character(ty)))
  ty[is.na(ty)] <- -1L
  ord <- order(g$.rid, g$.vk, -n_addr, -ty, g$recip_name, method = "radix")
  g <- g[ord, , drop = FALSE]
  g <- g[!duplicated(paste(g$.rid, g$.vk, sep = "\r")), , drop = FALSE]
  # no whitespace in the id: np_cascade() normalizes it in `.id`, and pf_status()
  # would then fail to find its own rows
  g$grant_id <- paste0(g$.rid, "|V", ave(seq_len(nrow(g)), g$.rid,
                                         FUN = seq_along))
  rownames(g) <- NULL
  g
}

# Fold the variant results into the identity status. See pf_screen_variants(),
# "How the results combine".
.pf_combine_variants <- function(status, v, vs, verbose = TRUE) {
  say <- function(...) if (verbose) cat(sprintf(...), "\n")
  vs <- vs[match(v$grant_id, vs$grant_id), , drop = FALSE]
  hit <- as.character(vs$status) %in% "YES" & !is.na(vs$ein)
  scr <- unique(v$.rid)
  i_s <- match(scr, status$grant_id)
  status$variant_screen[i_s] <- "none"
  status$variant_n[i_s] <- as.integer(table(v$.rid)[scr])
  if (any(hit)) {
    # strongest resolution first within each identity: most grant rows, then score
    k <- which(hit)
    k <- k[order(v$.rid[k], -v$.vn[k], -vs$score[k], method = "radix")]
    for (ks in split(k, v$.rid[k])) {
      i <- match(v$.rid[ks[1]], status$grant_id)
      main_yes <- as.character(status$status[i]) == "YES" && !is.na(status$ein[i])
      eins <- unique(c(if (main_yes) status$ein[i], vs$ein[ks]))
      status$variant_eins[i] <- paste(eins, collapse = ";")
      if (main_yes && length(eins) == 1L) {
        status$variant_screen[i] <- "agree"
        next
      }
      if (!main_yes) status <- .pf_take_variant(status, i, vs, v, ks[1])
      status$variant_screen[i] <- if (length(eins) > 1L) "conflict" else "resolved"
      status$status[i] <- if (length(eins) > 1L) "MAYBE" else "YES"
    }
  }
  tb <- table(factor(status$variant_screen, c("none", "resolved", "agree", "conflict")))
  say("  variant screen: %s resolved to YES, %s agree, %s conflict -> MAYBE, %s none",
      tb[["resolved"]], tb[["agree"]], tb[["conflict"]], tb[["none"]])
  status
}

# Report the variant's match as the identity's: the EIN and everything that
# describes the winning pair, so the row stays internally consistent.
.pf_take_variant <- function(status, i, vs, v, k) {
  for (col in intersect(c("ein", "bmf_name", "score", "name_sim", "margin",
                          "n_close", "bmf_state", "bmf_city", "bmf_zip5",
                          "geo_state", "geo_zip5"), names(vs)))
    status[[col]][i] <- vs[[col]][k]
  status$match_pass[i]   <- paste0("variant:", vs$match_pass[k])
  status$variant_name[i] <- v$recip_name[k]
  status
}

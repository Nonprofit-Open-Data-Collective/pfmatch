p <- "R/dedup.R"
x <- readLines(p, warn = FALSE)
fx <- function(s) { i <- grep(s, x, fixed = TRUE); stopifnot(length(i) == 1); i }

## ---- 1. sub-block oversized blocks instead of dropping them ----------------
i <- fx('    grp <- grp[lengths(grp) > 1L & lengths(grp) <= max_block]')
x[i] <- paste(c(
'    # Blocks larger than max_block used to be dropped outright. At 100k rows',
'    # that never binds; on the full 12.5M-grant file roughly 500k of 3.38M keys',
'    # sit in state-level blocks over the cap, and they are the densest',
'    # neighbourhoods -- exactly where fuzzy matching earns its keep. Sub-block',
'    # them on the leading characters of the name key instead. Jaro-Winkler',
'    # weights the common prefix heavily, so two names agreeing to within 0.08',
'    # distance almost always share a first letter; splitting on it is close to',
'    # lossless and bounds the O(k^2) comparison inside each block.',
'    grp <- grp[lengths(grp) > 1L]',
'    n_capped <- 0L',
'    split_big <- function(ix, depth) {',
'      if (length(ix) <= max_block) return(list(ix))',
'      if (depth > 3L) { n_capped <<- n_capped + length(ix); return(list()) }',
'      sub <- split(ix, substr(cand$name_key[ix], 1L, depth))',
'      sub <- sub[lengths(sub) > 1L]',
'      unlist(lapply(sub, split_big, depth = depth + 1L), recursive = FALSE)',
'    }',
'    big <- lengths(grp) > max_block',
'    if (any(big)) {',
'      grp <- c(grp[!big], unlist(lapply(grp[big], split_big, depth = 1L),',
'                                 recursive = FALSE))',
'      grp <- grp[lengths(grp) > 1L]',
'    }',
'    if (n_capped)',
'      say("  %s keys left uncompared after 3 levels of sub-blocking",',
'          format(n_capped, big.mark = ","))'), collapse = "\n")

## ---- 2. stop growing the edge vectors quadratically ------------------------
j <- fx('    ei <- integer(0); ej <- integer(0); n_veto <- 0L')
x[j] <- paste(c(
'    # Accumulate into a list and flatten once. Appending with c() inside the',
'    # per-pair loop costs O(L^2) element copies in the number of accepted',
'    # joins, which is invisible at 100k and a real term at full scale.',
'    acc <- vector("list", length(grp)); n_veto <- 0L; bi <- 0L'), collapse = "\n")

k <- fx('    for (ix in grp) {')
x[k] <- '    for (ix in grp) {\n      bi <- bi + 1L'

m <- fx('      if (!nrow(hit)) next')
x[m] <- '      if (!nrow(hit)) next\n      ea <- integer(nrow(hit)); eb <- integer(nrow(hit)); nn <- 0L'

n <- fx('        if (conflict(a, b)) { n_veto <- n_veto + 1L; next }')
x[n] <- '        if (conflict(a, b)) { n_veto <- n_veto + 1L; next }\n        nn <- nn + 1L; ea[nn] <- a; eb[nn] <- b'

o <- fx('        ei <- c(ei, a); ej <- c(ej, b)')
x[o] <- '      }'
# the old loop closing brace now belongs to the pair loop; append the block flush
x <- append(x, c(
'      if (nn) acc[[bi]] <- list(a = ea[seq_len(nn)], b = eb[seq_len(nn)])'),
  after = o)

# drop the now-duplicated closing brace that followed the removed assignment
p2 <- o + 2L
stopifnot(trimws(x[p2]) == "}")
x <- x[-p2]

q <- fx('    say("  %s fuzzy joins accepted, %s rejected by the number/ordinal/direction veto",')
x <- c(x[seq_len(q - 1L)],
       '    acc <- acc[!vapply(acc, is.null, logical(1))]',
       '    ei <- unlist(lapply(acc, `[[`, "a"), use.names = FALSE)',
       '    ej <- unlist(lapply(acc, `[[`, "b"), use.names = FALSE)',
       '    if (is.null(ei)) { ei <- integer(0); ej <- integer(0) }',
       x[seq.int(q, length(x))])
writeLines(x, p); cat("patched\n")

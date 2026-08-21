suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
r <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
cat("class:", class(r), "\n"); cat("names:", paste(names(r), collapse=" | "), "\n\n")
for (n in names(r)) {
  x <- r[[n]]
  cat("---", n, ":", paste(class(x), collapse="/"), "\n")
  if (is.data.frame(x)) { cat("   dim:", nrow(x), "x", ncol(x), "\n")
    cat("   cols:", paste(names(x), collapse=", "), "\n")
    print(utils::head(as.data.table(x), 2)) }
  else if (is.list(x)) cat("   list of", length(x), ":", paste(head(names(x),20), collapse=", "), "\n")
  else cat("   len:", length(x), "\n")
}

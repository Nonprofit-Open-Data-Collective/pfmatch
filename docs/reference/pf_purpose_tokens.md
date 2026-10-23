# Tokenize purpose or organization text

Tokenize purpose or organization text

## Usage

``` r
pf_purpose_tokens(
  x,
  unique_only = FALSE,
  stopwords = pf_purpose_stopwords(),
  min_nchar = 3L
)
```

## Arguments

- x:

  Character vector.

- unique_only:

  Drop repeats within a document.

- stopwords:

  Vocabulary to remove; defaults to
  [`pf_purpose_stopwords()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_purpose_stopwords.md).

- min_nchar:

  Shortest token to keep.

## Value

A list of character vectors.

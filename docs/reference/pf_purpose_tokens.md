<div id="main" class="col-md-9" role="main">

# Tokenize purpose or organization text

<div class="ref-description section level2">

Tokenize purpose or organization text

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_purpose_tokens(
  x,
  unique_only = FALSE,
  stopwords = pf_purpose_stopwords(),
  min_nchar = 3L
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   x:

    Character vector.

-   unique_only:

    Drop repeats within a document.

-   stopwords:

    Vocabulary to remove; defaults to `pf_purpose_stopwords()`.

-   min_nchar:

    Shortest token to keep.

</div>

<div class="section level2">

## Value

A list of character vectors.

</div>

</div>

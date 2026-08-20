# Making pfmatch a package

`pfmatch` was a bare `R/` + `dev/` folder on purpose: the point of the first pass
was to find out what match rate is achievable on 990-PF grant recipients before
committing to a package boundary. That question is now answered well enough to
draw the boundary.

> **Status: §§1-6 done, 2026-08-20.** `R CMD check` on the built tarball is
> **Status: OK** — no errors, warnings, or notes. Step 7's npmatch promotions are
> a separate document, `dev/NPMATCH-PROMOTION-PLAN.md`, and have **not** been
> started. What remains open is listed at the bottom of §7.

---

## 1. What exists today

Eleven modules, 43 exported functions, no `DESCRIPTION`, no `NAMESPACE`, no
`man/`. Loaded by `source()`-ing `R/` after `devtools::load_all()` on `npmatch`.

### Preprocessing

| step | function | module |
|---|---|---|
| read one or many grant CSVs | `pf_read_grants()` | `prepare.R` |
| recipient name + address, line-2 disambiguation, ZIP repair, foreign flag | `pf_prepare_grants()`, `pf_map_grants()` | `prepare.R` |
| free-text `SIGOCPYRFSTA` → 5 standard types | `pf_standardize_status()`, `pf_status_audit()`, `pf_oos_details()` | `recipient-type.R` |
| name typed into the street field | `pf_recover_name_from_street()` | `recover.R` |
| collapse grant rows to recipient identities | `pf_dedup()`, `pf_recipients()` | `dedup.R` |

### Reference

| step | function | module |
|---|---|---|
| read + normalize BMF, name freq, token IDF, blocking index | `pf_build_reference()` | `match.R` |
| acronym / prefix blocking keys | `pf_add_recovery_keys()`, `pf_initials()` | `recover.R` |
| BMF context columns for review | `pf_bmf_context()`, `pf_bmf_context_cols()` | `enrich.R` |

### Matching cascade

| stage | passes | function |
|---|---|---|
| A — state-blocked exact | `A1-name-zip5` … `A5-dba-dba` | `pf_staged_passes()` |
| B — state-blocked token | `B1-token-state`, `B2-token-concat` | `pf_staged_passes()` |
| C — unblocked residual sweep | `C1-name-any`, `C2-dba-any`, `C3-token-any` | `pf_staged_passes()` |
| D — alias / repair | acronym, prefix | `pf_recovery_passes()` |
| — | drive the cascade | `pf_match_grants()`, `pf_default_passes()`, `pf_pass_stage()` |
| — | hard constraint: never match the filer | `pf_drop_self_matches()` |
| — | checkpointed batches over the full file | `pf_run_batches()`, `pf_batch_report()` |
| — | identity result → every grant row | `pf_propagate_matches()` |

### Adjudication and reporting

| step | function | module |
|---|---|---|
| candidate sheet with BMF + foundation context | `pf_candidate_frame()` | `enrich.R` |
| EIN → NTEE text, 990 mission, programs | `pf_build_org_text()`, `pf_ntee_text()` | `text.R` |
| grant purpose features and tie-band tiebreak | `pf_purpose_coverage()`, `pf_purpose_is_contentful()`, `pf_purpose_tiebreak()`, `pf_tiebreak_config()` | `purpose.R` |
| attach mission text by EIN | `pf_attach_missions()` | `enrich.R` |
| outcome split, crosstab, geo agreement, per-pass table | `pf_report()`, `pf_status()`, `pf_crosstab()`, `pf_geo_agreement()` | `report.R` |

---

## 2. The boundary with npmatch

The rule that has been in force informally: **generic linkage machinery lives in
`npmatch`; only what is specific to 990-PF Part XIV lives here.** Applying it
honestly to the current code gives three groups.

**Correctly in pfmatch.** `recipient-type.R` (column (c) has no controlled
vocabulary and the rule cascade is entirely 990-PF), `prepare.R` (the
`PNAM`/`BNBN1`/`BNBN2` name-field logic is a 990-PF schema quirk),
`selfmatch.R` (a grant is a payment *from* the filer — only true here),
`purpose.R` (`SIGOCPYPOGOC` is a 990-PF field), `report.R`'s outcome framing.

**Should be promoted to npmatch.** Three things are generic and are only here by
accident of where they were needed first:

* `dedup.R` — collapsing a query file to distinct identities and propagating a
  match across a cluster applies to any repeated-query linkage problem. SAM and
  USASpending have the same repetition.
* `recover.R`'s `pf_initials()` / `pf_add_recovery_keys()` — acronym indexing and
  prefix keys are reference-side blocking devices with nothing 990-PF about them.
  The 35-character truncation *motivating* them is 990-PF; the mechanism is not.
* `batch.R` — checkpointed batching over a large query file is infrastructure.

**Belongs in npmatch and is currently wrong there.** `np_config()$tiebreak` only
accepts `"name"`, and that key is net 0 to −2 on 990-PF data because it assumes
the entity whose full name matches the query is correct — while the `FOUNDATION`
arm is correct 52.8% of the time here (`PURPOSE-MATCH-FINDINGS.md` §10). The fix
is to let `tiebreak` accept a **function** `f(df, close_rows) -> row index`, so a
caller can supply its own key without npmatch knowing anything about grant
purposes. That is a small, backward-compatible change to `.np_overall_summary()`
and it is the one npmatch change worth making.

Do the promotions **after** packaging, not during. Moving code and adding a
package boundary at the same time makes it impossible to tell which change broke
something.

---

## 3. Package skeleton

```
pfmatch/
  DESCRIPTION            Imports: data.table, stats; Depends: R (>= 4.1)
                         Imports: npmatch (Remotes: local or GitHub)
                         Suggests: stringdist, testthat (>= 3.0), knitr
  NAMESPACE              roxygen-generated
  R/                     as today, plus pipeline.R
  man/                   roxygen-generated
  data/                  nteev2.rda           <- the only bundled data
  data-raw/              make-nteev2.R        <- builds it from the two CSVs
  inst/
    probes/              the dev/probe-*.R and compare-*.R scripts, shipped as
                         reproducible evidence but not sourced at load
  tests/testthat/        promoted from dev/test-*.R and dev/check-*.R
  vignettes/
    pfmatch.Rmd          the README, as the getting-started vignette
    benchmarks.Rmd       BENCHMARK-NOTES + AUDIT-FINDINGS
    purpose.Rmd          PURPOSE-MATCH-DESIGN + FINDINGS
  .Rbuildignore          data/*.csv (600 MB+), data-dev/, dev/
```

Three notes on this.

**`data/` in the repo is not `data/` in the package.** The 600 MB of grant CSVs
and 250 MB Part III extracts must be `.Rbuildignore`d — they are inputs, not
package data. Rename the directory to `data-raw/` or `inputs/` to avoid the
collision with R's reserved `data/`; this is the one rename the packaging
requires.

**The NTEE lookup should become bundled data.** `pf_ntee_text()` currently reads
two CSVs from disk at call time via `pf_data_dir()`, which makes the function
environment-dependent and untestable. The tidy file is 1,086 rows; build it once
in `data-raw/make-nteev2.R` and ship `nteev2.rda`. `pf_ntee_text()` then becomes
a pure accessor with an override argument for a newer vintage. `pf_data_dir()`
disappears.

**The BMF and the 990 text do not become package data.** They are 1.7 GB and
650 MB and versioned by vintage. They stay caller-supplied paths, which is what
every function already assumes.

---

## 4. Export surface

43 exports is too many for a package and about right for a working folder. Three
tiers:

**Export and document (the API, ~20).** `pf_run`, `pf_prepare`, `pf_reference`,
`pf_link`, `pf_adjudicate`, `pf_read_grants`, `pf_prepare_grants`,
`pf_standardize_status`, `pf_status_audit`, `pf_dedup`, `pf_recipients`,
`pf_propagate_matches`, `pf_build_reference`, `pf_staged_passes`,
`pf_recovery_passes`, `pf_match_grants`, `pf_run_batches`, `pf_candidate_frame`,
`pf_build_org_text`, `pf_purpose_tiebreak`, `pf_report`, `pf_status`,
`pf_crosstab`.

**Export but mark `@keywords internal` (~12).** Configuration and vocabulary
accessors that callers may need to inspect or override but that are not the
point: `pf_default_passes`, `pf_pass_stage`, `pf_map_grants`, `pf_type_levels`,
`pf_type_labels`, `pf_status_levels`, `pf_oos_details`, `pf_bmf_context_cols`,
`pf_tiebreak_config`, `pf_purpose_stopwords`, `pf_initials`, `pf_ntee_text`.

**Un-export (~8).** Implementation detail with no caller outside the package:
`pf_purpose_tokens`, `pf_purpose_coverage`, `pf_add_recovery_keys`,
`pf_recover_name_from_street`, `pf_attach_missions`, `pf_dedup_report`,
`pf_batch_report`, `pf_geo_agreement`, `pf_drop_self_matches`. Several of these
are already called only from inside other pfmatch functions.

The `.pf_*` helpers stay internal as they are.

---

## 5. The wrappers (written, in `R/pipeline.R`)

`dev/run-full-file.R` had to hand-assemble nine calls in the right order, and
every other caller reproduced that order. The wrappers name the four stages:

```r
prep <- pf_prepare(grants, dedup = "fuzzy")      # read -> repair -> scope -> dedup
ref  <- pf_reference(bmf)                        # build or load the cached bundle
lnk  <- pf_link(prep, ref, batch_size = 25000)   # cascade -> self-guard -> propagate
adj  <- pf_adjudicate(lnk, bmf, tiebreak = FALSE)  # candidate sheet
```

or, for the common case:

```r
res <- pf_run(grants = "inputs", bmf = "…/bmf_2026_01_processed.csv")
```

`pf_run()` returns a `pf_run` object with a `print()` method giving the outcome
split and per-stage timings. It deliberately does **not** return the reference
bundle — it is 1.3 GB and already on disk at `ref_cache`.

Design constraints these follow:

* **The wrappers add no logic.** They order existing calls, thread cache paths,
  and time each stage. Anything a wrapper does can be done by hand.
* **Caching is a path argument, never a global.** `pf_reference(cache = NULL)`
  forces a rebuild; `pf_link(dir =)` is the checkpoint directory and re-running
  skips completed batches.
* **The purpose tiebreak stays off by default** in `pf_adjudicate()`, and turning
  it on requires passing `org_text` explicitly. The evidence is 1 gain and 0
  losses out of 6 verifiable changes; that does not justify a default.
* **Stage boundaries are where you would want to cache**, which is why there are
  four and not two: the reference costs ~5 minutes, prepare costs seconds, and
  linking costs hours.

Verified: all 12 `R/` files parse, and `pf_prepare()` runs end-to-end on
`1k_grants_01.csv` (1,000 rows → 978 in-scope identities).

---

## 6. Testing

`dev/` already contains eight `test-*.R` / `check-*.R` scripts that assert real
behaviour; they just are not runnable as a suite. Promote them:

| from | to | asserts |
|---|---|---|
| `dev/test-apostrophe-fix.R` | `tests/testthat/test-normalize.R` | punctuation asymmetry against the BMF |
| `dev/test-recovery-keys.R` | `tests/testthat/test-recover.R` | acronym / prefix key construction |
| `dev/test-selfmatch.R` | `tests/testthat/test-selfmatch.R` | filer EIN never wins |
| `dev/check-scope.R` | `tests/testthat/test-recipient-type.R` | status cascade coverage |
| `dev/measure-dedup.R` | `tests/testthat/test-dedup.R` | over-merge guard |

Plus new unit tests the package needs and does not have: `pf_purpose_coverage()`
returns `NA` rather than 0 on empty input; `pf_purpose_tiebreak()` never changes
a score or a tier; `pf_propagate_matches()` is a no-op on singleton clusters.

Fixtures: `1k_grants_01.csv` is 290 KB and is a legitimate `inst/extdata`
fixture. The BMF is not — tests that need a reference should use a 500-row
synthetic one built in `tests/testthat/helper-ref.R`.

The `probe-*.R` and `compare-*.R` scripts are **not** tests — they are evidence
for decisions, and they need the real BMF. Ship them under `inst/probes/` with a
README saying what each one measured and where the result is written up.

---

## 7. Order of operations

1. Rename `data/` → `inputs/`, add `.Rbuildignore`.
2. Add `DESCRIPTION` / `NAMESPACE`; roxygenize. No code changes.
3. Bundle `nteev2.rda`; make `pf_ntee_text()` a pure accessor; drop
   `pf_data_dir()`.
4. Apply the export tiering from §4.
5. Promote `dev/test-*.R` into `tests/testthat/`; add the three missing unit
   tests.
6. Re-run `PF_SET=1k` and confirm the benchmark is byte-identical. **Packaging
   must not move the numbers**; if it does, something in step 3 or 4 changed
   behaviour.
7. Only then consider the npmatch promotions in §2, one at a time, each with the
   benchmark re-run.

### What was actually done (2026-08-20)

Steps 1-5 as written, plus three things the plan did not anticipate:

* **npmatch had never been installed as a library** — only `load_all()`ed. It had
  to be `R CMD INSTALL`ed before pfmatch could declare it in `Imports`.
* **31 `dev/` scripts** were rewritten from the `source(R/*.R)` loop to
  `library(npmatch)` + `devtools::load_all(PF)`. `load_all()` defaults to
  `export_all = TRUE`, so scripts calling the newly-unexported functions still
  work; `library(pfmatch)` would break them.
* **The NTEE lookup had duplicate keys.** Several legacy codes collapse onto one
  NTEEv2 code — `B80`, `B8040`, `B8043` are all `EDU-B80-RG` — and only some
  carry keywords, so `by_v2` held 1,086 rows for 1,082 keys and
  `pf_build_org_text()`'s `match()` was picking by incidental row order. The
  builder now keeps the richest description per key and asserts uniqueness.
  Verified: every bundled key is present in the source files, its text is one of
  the source texts for that key, and it is the longest of them.

### Step 6, honestly

The benchmark was **not** verified byte-identical. The command that saved the
pre-packaging crosstab failed silently on a Dropbox file lock, so there was no
baseline to compare against, and by then the pipeline had also changed for
unrelated reasons (dedup, staged passes, recovery, the apostrophe fix), which
makes `BENCHMARK-NOTES.md` the wrong comparator anyway.

What was done instead is stronger for this purpose: a **diff of the executable
code** against a pre-packaging backup, with comments and roxygen stripped. Only
two files differ:

* `R/prepare.R` — the `path =` default, `"data"` -> `"inputs"`. Every caller
  passes `path` explicitly, so the default is never exercised.
* `R/text.R` — `pf_ntee_text()` and `pf_data_dir()`. **Neither is called by the
  cascade**; they are adjudication-only.

Every other module — `recipient-type`, `match`, `dedup`, `recover`, `selfmatch`,
`batch`, `report`, `enrich`, `purpose` — is byte-identical in code. Packaging is
therefore behaviour-neutral for the match path by construction, not by
measurement.

### Still open

* `vignettes/` — the plan proposed three; none were written. The findings
  documents are still plain markdown under `dev/`.
* `tests/` covers `purpose.R` and `text.R` only (21 assertions). The five
  promotions from `dev/test-*.R` named in §6 have not been done, and they are
  the ones that need a synthetic reference fixture.
* A real `PF_SET=1k` before/after comparison, if one is ever wanted, needs a
  clean baseline run first.

Step 7 is a separate decision — see `dev/NPMATCH-PROMOTION-PLAN.md`.

---

## 8. What this plan does not do

It does not fix the outstanding audit items — the apostrophe normalization bug,
the OOS gating for `individual`/`government`, or the group-exemption collapse.
Those are worth more to the match rate than packaging is (roughly +3 points
combined, against 0 for packaging), and adjudicating the MAYBE tier is worth more
than all of it (+11 to +14). Packaging is worth doing because it makes the code
usable by someone other than its author and testable in CI — not because it
improves anything measured.

If the two compete for the same day, do the audit items first.

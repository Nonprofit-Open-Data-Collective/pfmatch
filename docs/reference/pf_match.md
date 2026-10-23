# Match 990-PF grant recipients to the BMF

Wraps
[`npmatch::np_cascade()`](https://nonprofit-open-data-collective.github.io/npmatch/reference/np_cascade.html)
for the grant-recipient problem. The only structural difference from the
npmatch/SAM setup is the blocking cascade: a foundation and its grantees
need not share a state, so no pass keys on geography.

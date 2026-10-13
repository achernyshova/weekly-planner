Concerns with the current CT upstream MR process

No data testing in dev before merge. CT doesn’t have a process for validating data in a dev environment, so code changes get merged without anyone checking what the output data looks like. The code can look fine in review while the data it produces has problems, and we usually find out only after it reaches our downstream pipelines.
MRs can be approved without our review. We’re added as reviewers so we can see what’s changing upstream and plan the matching changes on our side. But CT can approve and merge without us, so changes can go in without our knowledge.
Impact on our team. Because of these two gaps, we often find upstream changes reactively, through broken or unexpected data downstream. That means unplanned fixes, possible data quality issues reaching our consumers, and time spent tracking down the root cause.

Proposed asks

Make our approval required on MRs that touch shared upstream datasets, for example through CODEOWNERS or a required approval rule, so they can’t merge without us.
Validate data in dev before merge. Ask CT to run changes in dev and share results with the MR, such as row counts, schema diffs, and sample comparisons. That way reviewers can approve the data and not just the code.
Add a short impact note to MR descriptions. It should say what changed, which tables or columns are affected, and whether downstream consumers need to act.
Write the process down together with CT (Ryan/Adam) once it’s agreed, so it’s clear to both teams.

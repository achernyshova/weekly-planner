# CLH ZIP3 — SQL-only, seed-driven package

No Python, Python libraries, dbt or external runtime is required to run this package in Databricks. The editable metric seed controls the formulas. The SQL notebook generates the necessary SQL expressions using SQL variables and EXECUTE IMMEDIATE, then runs reusable calculation views.

## Start here

1. **Unzip the package.** The main files are `01_run_all.sql`, `metrics_seed.csv`, `02_validation_queries.sql` and this README. `seed_bootstrap_optional.sql` is an optional all-SQL alternative to reading the CSV.
2. **Upload only `metrics_seed.csv` to an existing Unity Catalog Volume folder**, for example `/Volumes/my_catalog/my_schema/my_volume/clh_zip3_sql_only/metrics_seed.csv`. You do not need to upload the SQL files to the Volume.
3. **Import `01_run_all.sql` into your Databricks Workspace as a SQL notebook.** Attach a Databricks SQL warehouse, or compatible Databricks Runtime 14.3+ notebook compute. Current SQL warehouses are the recommended execution target. The notebook deliberately uses one SQL statement per cell and does not require BEGIN/END scripting.
4. **Edit the settings cells at the top.** Set `clh_seed_path` to the exact Volume path from step 2. Confirm the source table and year. Confirm fresh target names for result and QA tables. Leave `clh_publish_results` as `FALSE` for your first run.
5. **Run All in this ONE notebook.** It loads and validates the seed, reads source metadata, normalizes identifiers/numbers, generates expressions, deduplicates ZCTA contributions, runs the aggregation and previews ZIP3 980. It does not overwrite or modify the source table.
6. **Inspect the preview and QA.** For additional checks, copy the cells from `02_validation_queries.sql` into the bottom of the SAME notebook. Do not expect temporary views to be shared with a different notebook merely because it uses the same warehouse.
7. **Publish when ready.** Set `clh_publish_results` to `TRUE`, check both target names again, and rerun the notebook. The final cells use CREATE TABLE, not CREATE OR REPLACE. Existing targets cause an error rather than an overwrite. For subsequent runs use fresh names for both targets, or manage replacement deliberately yourself.

Your source identity needs SELECT on the source, permission to inspect its Unity Catalog metadata, and READ VOLUME on the seed location. To publish, it also needs CREATE TABLE in the target schema and normal catalog/schema usage privileges. The source must be a three-part Unity Catalog table or persistent view visible in its catalog's information_schema.columns. A session-only source temp view will not have the required Unity Catalog metadata.

## Settings

The supplied source is:

```text
110189_ctg_prod_exp.ds_public.clh_achrq_2022_zipcode
```

The source year is `2022`. The default result names are:

```text
110189_ctg_prod_exp.ds_public.clh_2022_zip3_features
110189_ctg_prod_exp.ds_public.clh_2022_zip3_features_qa
```

Only the seed path contains placeholders. Use table names without backticks in the settings; the notebook quotes them safely after validating the three-part names. For this package, identifier components must contain only letters, digits and underscores. The script refuses a result target equal to the source or QA target.

The settings are declared with `DECLARE OR REPLACE VARIABLE`, so they can be rerun in the same session. When changing settings, rerun the notebook from the top rather than changing a variable in the middle of an existing calculation.

## What you edit for future changes

**Edit `metrics_seed.csv`, not the aggregation SQL.** Keep the header names and column order unchanged. Save it as ordinary UTF-8 CSV, retaining valid CSV quoting around JSON/text fields, and upload the revised file to the same Volume path. Rerun the notebook to apply it.

Each row has these calculation fields:

- `enabled`: `1` calculates the definition; `0` keeps it in the seed but excludes it from the output schema.
- `source_column`: actual column name in the source. `output_column`: desired output name. Aliases are explicit.
- `geography`: `ZCTA` or `ZIP`, independently of the chosen formula.
- `method`: `sum`, `weighted_mean`, `ratio`, numeric-coded `mode`, `svi`, `pooled_age_median` or `gini_between`. `held` is accepted only in disabled starter rows.
- `value_expression`: source metric, or numerator expression for a component ratio.
- `weight_expression`: matching denominator or the selected population/subgroup proxy. For a sum use `1.0`.
- `valid_expression`: additional eligibility test, such as `ACS_PCT_UNEMPLOY_ZC BETWEEN 0 AND 100`.
- `approximate`: `1` labels a proxy/approximation in QA; `0` indicates a source-supported calculation method. Neither overrides the documented geography approximation.
- `weight_basis` and `notes`: explanation of your chosen interpretation.
- `options_json`: `{}` for ordinary metrics; complete SVI output names or pooled-median bin definitions for special methods.

`worksheet_method` and `worksheet_dependencies` preserve the instruction transcription for review. They do not execute formulas. The actual executable choices are the method/value/weight/validity/options fields.

For example, the unemployment row uses:

```text
method            = weighted_mean
value_expression  = ACS_PCT_UNEMPLOY_ZC
weight_expression = ACS_TOT_CIVILIAN_LABOR_ZC
valid_expression  = ACS_PCT_UNEMPLOY_ZC BETWEEN 0 AND 100
```

The generic calculation is `SUM(value * weight) / SUM(weight)` on the same valid pairs. Change only the seed's weight to select a different summary, and update `approximate`, `weight_basis` and `notes` to describe it. Source percentages stored as 62 remain on the 0–100 scale; do not apply another division by 100 to the result. Age-share expressions divide by 100 only when converting that age percentage into a population weight.

The scalar expression language is intentionally restricted to unqualified source fields, numeric arithmetic, comparisons, Boolean conditions and the approved scalar functions/operators listed in the SQL notebook. Comments, statement separators, aggregates, subqueries and arbitrary function names are rejected. Empty-string tests such as `TRIM(field) <> ''` are supported; this is not a general-purpose language for arbitrary text constants. Numeric-coded mode is supported; arbitrary string categories need an explicit numeric coding. Enabled unknown columns or invalid formulas stop the run rather than inventing values.

Treat the seed as access-controlled executable configuration: changing it changes the generated SQL. Syntax/method checks are useful safeguards, not a security boundary for untrusted users. Source-column names are discovered from metadata; numeric fields are TRY_CAST so invalid numeric strings become missing.

## Optional: avoid the CSV reader entirely

`seed_bootstrap_optional.sql` contains the same initial seed as a SQL VALUES statement. Copy its contents into the **same notebook**, replacing the CSV-load cell that creates `_clh3_seed_raw`. Do not run both loaders. This option needs no Volume upload, but the CSV is easier to maintain over time. Editing the CSV does not update the optional SQL snapshot.

If you prefer a permanent seed table, create one once from `_clh3_seed_raw`:

```sql
CREATE TABLE my_catalog.my_schema.clh_metric_rules
USING DELTA AS SELECT * FROM _clh3_seed_raw;
```

Then replace the CSV-load cell with:

```sql
CREATE OR REPLACE TEMP VIEW _clh3_seed_raw AS
SELECT * FROM my_catalog.my_schema.clh_metric_rules;
```

The remaining notebook is unchanged. This lets you manage enabled flags, weights and methods with SQL UPDATE statements. Keep the raw seed column names/string representation consistent with the supplied CSV. The initial CREATE is intentionally not a replacement command.

## Current metric choices

The seed is unchanged from the latest seed-driven candidate: 195 definition rows, of which 184 are enabled. The five SVI rows expand to a score plus four shares each, giving **204 metric columns plus YEAR and ZIP3**. Seventeen previously held percentages are enabled as documented weighted-mean proxies. Matching denominator counts are used where present; population/subgroup proxies are explicit where an exact original denominator is unavailable. Two deep-poverty age-specific weights are explicitly proposed age-matched corrections to inconsistent screenshot weights. This SQL-only conversion does not claim those proxies are exact pooled subgroup rates.

The remaining 11 definitions are included but disabled: the missing-data flag, two insurance rows whose weight instructions were blank, HHC nursing and seven native-ZIP distances without safe ZIP-level population allocations. They do not become all-NULL output columns. Supply an approved method/weight and enable them in the seed when ready. If an additional weight comes from another source, join it into a persistent source view first; set `clh_source_table` to that view and reference the added column in the seed.

**ZCTA geography:** represented ZCTA estimates are counted once per metric, with a nonpoint exact ZIPCODE=ZCTA preference and compatible fallback. Membership uses the ZCTA's first three digits. This is the documented ZCTA-prefix approximation, not exact postal-ZIP3 allocation. Conflicting fallback mappings remain exclusions in QA. Exact-row missing values are not silently filled from other mapped rows.

**Native ZIP geography:** true ZIP establishment counts remain one contribution per postal ZIP, including valid point ZIPs. They are not collapsed by ZCTA. The result therefore contains explicitly documented mixed geography bases.

**Gini APPROX:** `GINI_BETWEEN_MEDIAN_APPROX` uses `ACS_TOT_HH_ZC` and `ACS_MEDIAN_HH_INC_ZC` with method `gini_between`, implementing the worksheet's unique-pair median-gap formula efficiently with ordered cumulative sums. `ACS_GINI_INDEX_APPROX` is a separate household-weighted mean of existing local Ginis. Both are enabled in this starter seed; disable either if not wanted. Never add them into a purported pooled Gini. The between-median proxy ignores within-ZCTA household-income differences.

**SVI:** score means use valid-score population. Quartile population shares use all known represented population and exact bands [0,.25],(.25,.50],(.50,.75],(.75,1]. Their sum equals valid-score population coverage, not necessarily 100. Zero is valid; invalid/sentinel scores are excluded.

**Median age:** pooled disjoint bins use interpolation within the median bin. An open upper-tail median is undefined rather than invented. Other mean-of-medians proxies retain their documented approximate status.

## QA and reruns

The final temporary result is `_clh3_final`; metric-level QA is `_clh3_qa`. With publication enabled, equivalent permanent Delta tables are created under the configured target names. Permanent outputs can be read from another notebook; temporary views and variables cannot be assumed to survive a new session or another notebook.

Missing metric/weight pairs are excluded from both sides of weighted formulas. A reported zero metric remains valid with a positive weight. A zero/absent total denominator produces NULL. Partial coverage remains visible. For sums, QA weight is one per source unit, so coverage is unit coverage—not population coverage. Known-weight coverage does not account for unknown real denominator amounts; unknown weights are counted separately. Mode ties produce NULL with a tie flag instead of an arbitrary winner.

This notebook rereads the current seed and rebuilds the temporary views every run. Enabling publication is not a two-table transaction: if one CREATE succeeds and the second fails, the first table remains. Check both names and permissions first. Rerunning with existing target names fails safely; the package never drops or replaces production targets automatically.

## Troubleshooting

**Volume/file error:** confirm the exact `/Volumes/catalog/schema/volume/.../metrics_seed.csv` path and READ VOLUME permission. Use the optional SQL bootstrap if you want to isolate CSV-reader issues. CSV schema is positional, so keep the supplied header order.

**Metadata unavailable:** confirm the source is a three-part Unity Catalog persistent table/view and the catalog/schema spelling matches metadata. Check source/catalog usage and SELECT permissions. Added source views must expose YEAR, ZIPCODE, ZCTA, POINT_ZIP, STATEFIPS, STATE, REGION and TERRITORY.

**Unknown column/token or invalid seed:** inspect the changed row. Use actual source names in expressions and only supported scalar functions. Do not place SUM/AVG in `value_expression`; the method supplies aggregation. SVI output names must not collide with other enabled outputs. Median bin intervals must be contiguous and ordered.

**Variable/view not found:** rerun from the top in the same imported notebook and attached compute. Avoid splitting these stages across separate notebooks or query objects.

**Existing target table:** choose fresh result and QA names, or turn publication off. Do not use a drop/replace workaround unless you deliberately intend to replace that data.

**Slow execution:** initial normalization and the long contribution layer process millions of metric-source pairs. Test on an appropriately sized warehouse/cluster. This package favors reusable SQL and explicit QA over a large hand-coded wide SELECT; no Python runtime or hidden service is required.

## Compatibility and sources

This package uses standalone SQL statements and session variables. Its feature floor is Databricks SQL or Databricks Runtime **14.3+** for EXECUTE IMMEDIATE. It does not require SQL scripting, which has a higher Runtime 16.3+ floor. CSV reading from Volumes uses the Databricks `read_files` function; source-column metadata uses Unity Catalog `information_schema.columns`.

Official documentation: [EXECUTE IMMEDIATE](https://docs.databricks.com/aws/en/sql/language-manual/sql-ref-syntax-aux-execute-immediate), [SQL variables](https://docs.databricks.com/aws/en/sql/language-manual/sql-ref-variables), [read_files](https://docs.databricks.com/aws/en/sql/language-manual/functions/read_files), [CSV options](https://docs.databricks.com/aws/en/spark/api-options), and [SQL warehouse sessions](https://docs.databricks.com/aws/en/sql/user/queries/sessions).


## Validation performed for this SQL-only version

The delivered SQL statement sequence—including SQL-variable assignment and EXECUTE IMMEDIATE—ran locally on Apache Spark 4.0.1 against all 41,048 public CLH source records. The supplied seed produced 917 ZIP3 rows and 204 metric columns. All 187,068 metric/key cells matched the previous seed-driven implementation and independent pandas aggregation checks, with zero numerical mismatches. The independent reference uses canonical contribution records, so this tests aggregation consistency rather than independently validating every stakeholder proxy choice.

The test executed the included all-SQL seed bootstrap and verified every raw seed field against the CSV. The Databricks-only read_files CSV call and Unity Catalog information_schema access were checked against official documentation but could not be executed in the local Apache Spark environment; equivalent seed rows/source metadata were substituted for those two integration steps. Source normalization, seed parsing/validation, generated metric expressions, all numerical algorithms, dynamic output-column generation, and preview-only publication statements were executed. No live Databricks connection, permanent Delta write, or production-table overwrite was performed.

`validated_results.csv` contains the local results and `validation_980.csv` provides metric-level QA for 980. If opening the result CSV in Excel, import ZIP3 as text to retain leading zeros. `validation_summary.json` records the execution counts and these limitations. There are no Python files in the runtime ZIP.

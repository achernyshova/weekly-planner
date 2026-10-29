-- Databricks notebook source

-- Copy these checks into cells of the SAME notebook/session after 01_run_all.sql.
-- The _clh3_* views are session-local, even when another notebook uses the same warehouse.



-- Should return no rows: one result per YEAR/ZIP3.
SELECT YEAR,ZIP3,COUNT(*) AS rows_per_key
FROM _clh3_final GROUP BY YEAR,ZIP3 HAVING COUNT(*)<>1;

-- COMMAND ----------

-- Should return no rows: one QA row per enabled output/YEAR/ZIP3.
SELECT YEAR,ZIP3,metric,COUNT(*) AS rows_per_metric_key
FROM _clh3_qa GROUP BY YEAR,ZIP3,metric HAVING COUNT(*)<>1;

-- COMMAND ----------

-- Review source coverage and explicitly approximate methods.
SELECT metric,implementation_status,qa_status,COUNT(*) AS zip3_count
FROM _clh3_qa
GROUP BY metric,implementation_status,qa_status
ORDER BY metric,qa_status;

-- COMMAND ----------

-- ZIP3 980 Gini outputs are DIFFERENT statistics; never add them.
SELECT metric,metric_value,method,implementation_status,
       valid_units,source_units,pct_known_weight_covered,qa_status
FROM _clh3_qa
WHERE ZIP3='980' AND metric IN ('ACS_GINI_INDEX_APPROX','GINI_BETWEEN_MEDIAN_APPROX');

-- COMMAND ----------

-- SVI shares should sum to known-population valid-score coverage, not necessarily 100.
-- Should return no rows when all five score/share groups reconcile.
WITH score_coverage AS (
 SELECT q.YEAR,q.ZIP3,q.metric AS score_metric,q.pct_known_weight_covered
 FROM _clh3_qa q JOIN _clh3_definition_seed d ON q.metric=d.metric WHERE d.method='svi'
), shares AS (
 SELECT q.YEAR,q.ZIP3,d.parent_metric AS score_metric,SUM(q.metric_value) AS share_total
 FROM _clh3_qa q JOIN _clh3_definition_seed d ON q.metric=d.metric
 WHERE d.method='svi_share' GROUP BY q.YEAR,q.ZIP3,d.parent_metric
)
SELECT s.*,c.pct_known_weight_covered
FROM shares s JOIN score_coverage c
 ON s.YEAR=c.YEAR AND s.ZIP3=c.ZIP3 AND s.score_metric=c.score_metric
WHERE ABS(s.share_total-c.pct_known_weight_covered)>0.0000001;

-- COMMAND ----------

-- Exact valid contributions used by each selected 980 calculation.
-- For a ratio method value is the numerator component; see the seed value_expression.
SELECT YEAR,ZIP3,metric,unit_id,geography,method,contribution_rule,
       value,weight,usable,mapped_values_differ
FROM _clh3_valid
WHERE ZIP3='980'
 AND metric IN ('ACS_TOT_POP_WT_ZC','ACS_TOT_HH_ZC','ACS_PCT_UNEMPLOY_ZC',
                'GINI_BETWEEN_MEDIAN_APPROX','ACS_GINI_INDEX_APPROX','CCBP_TOT_PHYS_ZP')
ORDER BY metric,unit_id;

-- COMMAND ----------

-- Count repeated candidate mappings versus final canonical source-unit contributions.
SELECT metric,contribution_rule,COUNT(*) AS canonical_units,
       SUM(raw_mapping_rows) AS raw_mapping_rows
FROM _clh3_contributions WHERE ZIP3='980'
GROUP BY metric,contribution_rule ORDER BY metric,contribution_rule;

-- COMMAND ----------

-- Seed choices that are NOT active: they do not appear as all-NULL result columns.
SELECT source_column,output_column,method,weight_basis,notes
FROM _clh3_seed WHERE NOT enabled ORDER BY output_column;

-- COMMAND ----------

-- Optional: after publication, permanent results do not depend on notebook session views.
-- SELECT * FROM 110189_ctg_prod_exp.ds_public.clh_2022_zip3_features WHERE ZIP3='980';
-- SELECT * FROM 110189_ctg_prod_exp.ds_public.clh_2022_zip3_features_qa WHERE ZIP3='980';

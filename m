-- Databricks notebook source

-- Rebuilt 202-row seed: original instruction columns are preserved.
-- No assertions, audit pipeline, permanent writes, or silent enabled=0 filters.
-- Inputs
DECLARE OR REPLACE VARIABLE source_table STRING DEFAULT '110189_ctg_prod_exp.ds_public.clh_achrq_2022_zipcode';

-- COMMAND ----------

DECLARE OR REPLACE VARIABLE source_year INT DEFAULT 2022;

-- COMMAND ----------

DECLARE OR REPLACE VARIABLE statement_sql STRING;

-- COMMAND ----------

-- Read all 202 retained instruction rows, including metadata. Keep the path literal.
CREATE OR REPLACE TEMP VIEW metric_seed_raw AS
SELECT * FROM read_files(
 '/Volumes/110189_ctg_prod_exp/ds_public/self_service/metrics_seed.csv',
 format=>'csv', header=>true, multiLine=>true, escape=>'"',
 schema=>'`Data Source` STRING, `name` STRING, `label` STRING, `Variable Type (for aggregation from ZIP5 to ZIP3)` STRING, `Suggested Aggregation Method (from ZIP5 to ZIP3)` STRING, `Dependent Vars for aggregation` STRING, `Variable Rename for aggregation` STRING, `Keep in Mart` STRING, `source_column` STRING, `output_column` STRING, `row_role` STRING, `geography` STRING, `method` STRING, `value_expression` STRING, `weight_expression` STRING, `valid_expression` STRING, `approximate` STRING, `options_json` STRING, `execution_status` STRING, `implementation_note` STRING, `source_reference` STRING'
);

-- COMMAND ----------

-- Calculate metric rows; YEAR and source metadata have explicit separate roles.
-- method=unresolved retains the output as NULL. See execution_status in the seed.
CREATE OR REPLACE TEMP VIEW metric_rules AS
SELECT
 TRIM(output_column) AS output_column,
 UPPER(TRIM(geography)) AS geography, LOWER(TRIM(method)) AS method,
 TRIM(value_expression) AS value_expression,
 TRIM(weight_expression) AS weight_expression,
 TRIM(valid_expression) AS valid_expression,
 FROM_JSON(options_json,
  'STRUCT<quartile_outputs:ARRAY<STRING>,bins:ARRAY<STRUCT<lower:DOUBLE,upper:DOUBLE,count_expr:STRING>>>') AS options
FROM metric_seed_raw
WHERE TRIM(`Keep in Mart`)='1' AND row_role='metric';

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW age_bins AS
SELECT s.output_column AS parent_metric,p AS bin_order,
 b.lower AS lower_bound,b.upper AS upper_bound,b.count_expr
FROM metric_rules s
LATERAL VIEW POSEXPLODE(s.options.bins) e AS p,b
WHERE s.method='pooled_age_median';

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW metric_definitions AS
SELECT output_column AS metric,method,
 CAST(NULL AS STRING) AS parent_metric,CAST(NULL AS INT) AS quartile
FROM metric_rules
UNION ALL
SELECT q,'svi_share',s.output_column,p+1
FROM metric_rules s
LATERAL VIEW POSEXPLODE(s.options.quartile_outputs) e AS p,q
WHERE s.method='svi';

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW calculation_rules AS
SELECT output_column AS metric,method,geography,value_expression,weight_expression,valid_expression
FROM metric_rules WHERE method<>'pooled_age_median'
UNION ALL
SELECT CONCAT('__BIN_',s.output_column,'_',CAST(b.bin_order AS STRING)), 'sum',s.geography,
 b.count_expr,'1.0',
 CONCAT('(',s.valid_expression,') AND (',
   CONCAT_WS(' AND ',TRANSFORM(s.options.bins,x->CONCAT('((',x.count_expr,') IS NOT NULL AND (',x.count_expr,')>=0)'))),')')
FROM metric_rules s JOIN age_bins b ON s.output_column=b.parent_metric;

-- COMMAND ----------

SET VAR statement_sql = CONCAT(
 'CREATE OR REPLACE TEMP VIEW source_columns AS SELECT column_name, ordinal_position FROM `',
 SPLIT_PART(source_table,'.',1),'`.information_schema.columns WHERE table_schema=',
 CHR(39),SPLIT_PART(source_table,'.',2),CHR(39),' AND table_name=',
 CHR(39),SPLIT_PART(source_table,'.',3),CHR(39)
);

-- COMMAND ----------

EXECUTE IMMEDIATE statement_sql;

-- COMMAND ----------

-- 1. stg_clh_zipcode
SET VAR statement_sql = (
WITH typed_columns AS (
SELECT ordinal_position,
 CONCAT(
 CASE WHEN UPPER(column_name)='YEAR' THEN CONCAT('TRY_CAST(`',column_name,'` AS INT)')
 WHEN UPPER(column_name) IN ('ZIPCODE','ZCTA') THEN CONCAT(
   'CASE WHEN REGEXP_REPLACE(TRIM(CAST(`',column_name,'` AS STRING)), ',CHR(39),'[.]0+$',CHR(39),', ',CHR(39),CHR(39),') RLIKE ',CHR(39),'^[0-9]{1,5}$',CHR(39),
   ' THEN LPAD(REGEXP_REPLACE(TRIM(CAST(`',column_name,'` AS STRING)), ',CHR(39),'[.]0+$',CHR(39),', ',CHR(39),CHR(39),'),5,',CHR(39),'0',CHR(39),
   ') ELSE REGEXP_REPLACE(TRIM(CAST(`',column_name,'` AS STRING)), ',CHR(39),'[.]0+$',CHR(39),', ',CHR(39),CHR(39),') END')
 WHEN UPPER(column_name) IN ('STATEFIPS','STATE','REGION','CEN_AIAN_NH_IND') THEN CONCAT('TRIM(CAST(`',column_name,'` AS STRING))')
 ELSE CONCAT('TRY_CAST(`',column_name,'` AS DOUBLE)') END,
 ' AS `',column_name,'`') AS projection
FROM source_columns
 )
 SELECT CONCAT('CREATE OR REPLACE TEMP VIEW stg_clh_zipcode AS SELECT ',
  CONCAT_WS(', ',TRANSFORM(ARRAY_SORT(COLLECT_LIST(NAMED_STRUCT('position',ordinal_position,'sql',projection))),x->x.sql)),
  ' FROM `',REPLACE(source_table,'.','`.`'),'` WHERE TRY_CAST(YEAR AS INT)=',CAST(source_year AS STRING))
 FROM typed_columns
);

-- COMMAND ----------

EXECUTE IMMEDIATE statement_sql;

-- COMMAND ----------

-- 2. int_clh_metric_values
SET VAR statement_sql = (
WITH fragments AS (
  SELECT CAST(FLOOR((ROW_NUMBER() OVER(ORDER BY metric)-1)/40) AS INT) AS chunk_id,
   metric, FORMAT_STRING('named_struct(\'metric\',\'%s\',\'method\',\'%s\',\'geography\',\'%s\',\'value\',TRY_CAST((%s) AS DOUBLE),\'weight\',TRY_CAST((%s) AS DOUBLE),\'pair_valid\',COALESCE((%s),FALSE))',
    metric,method,geography,value_expression,weight_expression,valid_expression) AS fragment
  FROM calculation_rules
 ), chunks AS (
  SELECT chunk_id, CONCAT(
   'SELECT s.YEAR,s.ZIPCODE,s.ZCTA,s.POINT_ZIP,m.* FROM stg_clh_zipcode s LATERAL VIEW EXPLODE(ARRAY(',
   CONCAT_WS(',',TRANSFORM(ARRAY_SORT(COLLECT_LIST(NAMED_STRUCT('metric',metric,'sql',fragment))),x->x.sql)),
   ')) e AS m WHERE s.ZIPCODE RLIKE ',CHR(39),'^[0-9]{5}$',CHR(39)) AS query
  FROM fragments GROUP BY chunk_id
 )
 SELECT CONCAT('CREATE OR REPLACE TEMP VIEW int_clh_metric_values AS ',
  CONCAT_WS(' UNION ALL ',TRANSFORM(ARRAY_SORT(COLLECT_LIST(NAMED_STRUCT('chunk',chunk_id,'sql',query))),x->x.sql)))
 FROM chunks
);

-- COMMAND ----------

EXECUTE IMMEDIATE statement_sql;

-- COMMAND ----------

-- 3. int_clh_contributions
CREATE OR REPLACE TEMP VIEW int_clh_contributions AS
WITH zcta_candidates AS (
SELECT YEAR, ZCTA, metric, method,
  COUNT(*) AS candidate_rows,
  COUNT_IF(ZIPCODE=ZCTA) AS exact_rows,
  COUNT_IF(SUBSTRING(ZIPCODE,1,3)=SUBSTRING(ZCTA,1,3)) AS same_prefix_rows,
  COUNT(DISTINCT named_struct('v',value,'w',weight,'ok',pair_valid)) AS signature_count,
  MAX(CASE WHEN ZIPCODE=ZCTA THEN value END) AS exact_value,
  MAX(CASE WHEN ZIPCODE=ZCTA THEN weight END) AS exact_weight,
  MAX(CASE WHEN ZIPCODE=ZCTA AND pair_valid THEN 1 ELSE 0 END) AS exact_valid,
  MIN(value) AS fallback_value, MIN(weight) AS fallback_weight,
  MIN(CASE WHEN pair_valid THEN 1 ELSE 0 END) AS fallback_valid
FROM int_clh_metric_values
WHERE geography='ZCTA' AND POINT_ZIP=0 AND ZCTA RLIKE '^[0-9]{5}$'
GROUP BY YEAR,ZCTA,metric,method
),
contributions AS (
SELECT YEAR,SUBSTRING(ZCTA,1,3) AS ZIP3,ZCTA AS unit_id,
 'ZCTA' AS geography,metric,method,
 CASE WHEN exact_rows=1 THEN exact_value
      WHEN exact_rows=0 AND same_prefix_rows=candidate_rows AND signature_count=1 THEN fallback_value END AS value,
 CASE WHEN exact_rows=1 THEN exact_weight
      WHEN exact_rows=0 AND same_prefix_rows=candidate_rows AND signature_count=1 THEN fallback_weight END AS weight,
 CASE WHEN exact_rows=1 THEN exact_valid=1
      WHEN exact_rows=0 AND same_prefix_rows=candidate_rows AND signature_count=1 THEN fallback_valid=1 ELSE FALSE END AS pair_valid
FROM zcta_candidates
UNION ALL
SELECT YEAR,SUBSTRING(ZIPCODE,1,3),ZIPCODE,'ZIP',metric,method,value,weight,pair_valid
FROM int_clh_metric_values WHERE geography='ZIP'
)
SELECT *, (pair_valid AND (value IS NOT NULL AND value BETWEEN -1.7976931348623157E308 AND 1.7976931348623157E308) AND (weight IS NOT NULL AND weight BETWEEN -1.7976931348623157E308 AND 1.7976931348623157E308) AND weight>0) AS usable FROM contributions;

-- COMMAND ----------

-- 4. int_clh_zip3_metrics
CREATE OR REPLACE TEMP VIEW int_clh_zip3_metrics AS
WITH metric_rules AS (
SELECT
 TRIM(output_column) AS output_column,
 UPPER(TRIM(geography)) AS geography, LOWER(TRIM(method)) AS method,
 TRIM(value_expression) AS value_expression,
 TRIM(weight_expression) AS weight_expression,
 TRIM(valid_expression) AS valid_expression,
 FROM_JSON(options_json,
  'STRUCT<quartile_outputs:ARRAY<STRING>,bins:ARRAY<STRUCT<lower:DOUBLE,upper:DOUBLE,count_expr:STRING>>>') AS options
FROM metric_seed_raw
WHERE TRIM(`Keep in Mart`)='1' AND row_role='metric'
),
age_bins AS (
SELECT s.output_column AS parent_metric,p AS bin_order,
 b.lower AS lower_bound,b.upper AS upper_bound,b.count_expr
FROM metric_rules s
LATERAL VIEW POSEXPLODE(s.options.bins) e AS p,b
WHERE s.method='pooled_age_median'
),
metric_definitions AS (
SELECT output_column AS metric,method,
 CAST(NULL AS STRING) AS parent_metric,CAST(NULL AS INT) AS quartile
FROM metric_rules
UNION ALL
SELECT q,'svi_share',s.output_column,p+1
FROM metric_rules s
LATERAL VIEW POSEXPLODE(s.options.quartile_outputs) e AS p,q
WHERE s.method='svi'
),
metric_summary AS (
SELECT YEAR,ZIP3,metric,method,geography,
 SUM(CASE WHEN weight BETWEEN 0 AND 1.7976931348623157E308 THEN weight END) AS total_known_weight,
 SUM(CASE WHEN usable THEN weight END) AS valid_weight,
 SUM(CASE WHEN usable THEN value END) AS sum_value,
 SUM(CASE WHEN usable THEN value*weight END) AS sum_value_weight,
 SUM(CASE WHEN usable AND value BETWEEN 0 AND .25 THEN weight ELSE 0 END) AS q1_weight,
 SUM(CASE WHEN usable AND value>.25 AND value<=.5 THEN weight ELSE 0 END) AS q2_weight,
 SUM(CASE WHEN usable AND value>.5 AND value<=.75 THEN weight ELSE 0 END) AS q3_weight,
 SUM(CASE WHEN usable AND value>.75 AND value<=1 THEN weight ELSE 0 END) AS q4_weight
FROM int_clh_contributions GROUP BY YEAR,ZIP3,metric,method,geography
),
mode_results AS (
WITH by_code AS (
 SELECT YEAR,ZIP3,metric,value,SUM(weight) AS code_weight FROM int_clh_contributions
 WHERE method='mode' AND usable GROUP BY YEAR,ZIP3,metric,value
), ranked AS (
 SELECT *,MAX(code_weight) OVER(PARTITION BY YEAR,ZIP3,metric) AS max_weight FROM by_code
)
SELECT YEAR,ZIP3,metric,
 CASE WHEN COUNT_IF(code_weight=max_weight)=1 THEN MAX(CASE WHEN code_weight=max_weight THEN value END) END AS result
FROM ranked GROUP BY YEAR,ZIP3,metric
),
gini_results AS (
WITH ordered AS (
 SELECT YEAR,ZIP3,metric,unit_id,value,weight,
  COALESCE(SUM(weight) OVER(PARTITION BY YEAR,ZIP3,metric ORDER BY value,unit_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS prior_w,
  COALESCE(SUM(weight*value) OVER(PARTITION BY YEAR,ZIP3,metric ORDER BY value,unit_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS prior_wm
 FROM int_clh_contributions WHERE method='gini_between' AND usable AND value>=0
)
SELECT YEAR,ZIP3,metric,
 SUM(weight*(value*prior_w-prior_wm))/NULLIF(SUM(weight)*SUM(weight*value),0) AS result
FROM ordered GROUP BY YEAR,ZIP3,metric
),
median_results AS (
WITH bins AS (
 SELECT s.YEAR,s.ZIP3,b.parent_metric,b.bin_order,b.lower_bound,b.upper_bound,s.sum_value AS bin_count,
  SUM(s.sum_value) OVER(PARTITION BY s.YEAR,s.ZIP3,b.parent_metric) AS total_count,
  SUM(s.sum_value) OVER(PARTITION BY s.YEAR,s.ZIP3,b.parent_metric ORDER BY b.bin_order ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_count
 FROM metric_summary s JOIN age_bins b ON s.metric=CONCAT('__BIN_',b.parent_metric,'_',CAST(b.bin_order AS STRING))
), median_bin AS (
 SELECT *,cumulative_count-bin_count AS previous_count FROM bins
 WHERE total_count>0 AND bin_count>0
)
SELECT YEAR,ZIP3,parent_metric AS metric,
 MAX(CASE WHEN previous_count<total_count/2 AND cumulative_count>=total_count/2
  AND upper_bound IS NOT NULL THEN lower_bound+(total_count/2-previous_count)/bin_count*(upper_bound-lower_bound) END) AS result
FROM median_bin GROUP BY YEAR,ZIP3,parent_metric
)
SELECT s.YEAR,s.ZIP3,s.metric,
 CASE WHEN s.method='sum' THEN s.sum_value
      WHEN s.method IN ('weighted_mean','svi') THEN s.sum_value_weight/NULLIF(s.valid_weight,0)
      WHEN s.method='ratio' THEN s.sum_value/NULLIF(s.valid_weight,0)
      WHEN s.method='mode' THEN m.result
      WHEN s.method='gini_between' THEN g.result END AS result
FROM metric_summary s
LEFT JOIN mode_results m ON s.YEAR=m.YEAR AND s.ZIP3=m.ZIP3 AND s.metric=m.metric
LEFT JOIN gini_results g ON s.YEAR=g.YEAR AND s.ZIP3=g.ZIP3 AND s.metric=g.metric
WHERE s.metric NOT RLIKE '^__BIN_'
UNION ALL SELECT YEAR,ZIP3,metric,result FROM median_results
UNION ALL
SELECT s.YEAR,s.ZIP3,d.metric,
 100.0*CASE d.quartile WHEN 1 THEN s.q1_weight WHEN 2 THEN s.q2_weight
                     WHEN 3 THEN s.q3_weight WHEN 4 THEN s.q4_weight END/NULLIF(s.total_known_weight,0)
FROM metric_summary s JOIN metric_definitions d ON s.metric=d.parent_metric
WHERE d.method='svi_share';

-- COMMAND ----------

-- Preserve related source metadata as sorted distinct arrays, not arbitrary scalar values.
-- Related means postal-prefix OR ZCTA-prefix, since the two metric families use different bases.
CREATE OR REPLACE TEMP VIEW clh_zip3_source_metadata AS
SELECT s.YEAR,p.ZIP3,
 SORT_ARRAY(COLLECT_SET(s.`STATEFIPS`)) AS `STATEFIPS`,
 SORT_ARRAY(COLLECT_SET(s.`ZIPCODE`)) AS `ZIPCODE`,
 SORT_ARRAY(COLLECT_SET(s.`ZCTA`)) AS `ZCTA`,
 SORT_ARRAY(COLLECT_SET(s.`STATE`)) AS `STATE`,
 SORT_ARRAY(COLLECT_SET(s.`REGION`)) AS `REGION`,
 SORT_ARRAY(COLLECT_SET(s.`TERRITORY`)) AS `TERRITORY`,
 SORT_ARRAY(COLLECT_SET(s.`POINT_ZIP`)) AS `POINT_ZIP`
FROM stg_clh_zipcode s
LATERAL VIEW EXPLODE(ARRAY_DISTINCT(ARRAY(SUBSTRING(s.ZIPCODE,1,3),SUBSTRING(s.ZCTA,1,3)))) p AS ZIP3
WHERE p.ZIP3 RLIKE '^[0-9]{3}$'
GROUP BY s.YEAR,p.ZIP3;

-- COMMAND ----------

-- 5. clh_zip3_features
SET VAR statement_sql = (
SELECT CONCAT('CREATE OR REPLACE TEMP VIEW clh_zip3_metric_features AS
WITH zip3_keys AS (
SELECT DISTINCT YEAR, SUBSTRING(ZIPCODE,1,3) AS ZIP3 FROM stg_clh_zipcode WHERE ZIPCODE RLIKE \'^[0-9]{5}$\'
UNION
SELECT DISTINCT YEAR, SUBSTRING(ZCTA,1,3) AS ZIP3 FROM stg_clh_zipcode WHERE ZCTA RLIKE \'^[0-9]{5}$\'
)
SELECT k.YEAR,k.ZIP3,',
  CONCAT_WS(',',TRANSFORM(ARRAY_SORT(COLLECT_LIST(NAMED_STRUCT('metric',metric,'sql',
   CONCAT('MAX(CASE WHEN r.metric=',CHR(39),metric,CHR(39),' THEN r.result END) AS `',metric,'`')))),x->x.sql)),
  ' FROM zip3_keys k LEFT JOIN int_clh_zip3_metrics r ON k.YEAR=r.YEAR AND k.ZIP3=r.ZIP3 GROUP BY k.YEAR,k.ZIP3')
 FROM metric_definitions
);

-- COMMAND ----------

EXECUTE IMMEDIATE statement_sql;
-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW clh_zip3_features AS
SELECT f.*,
 m.`STATEFIPS`,
 m.`ZIPCODE`,
 m.`ZCTA`,
 m.`STATE`,
 m.`REGION`,
 m.`TERRITORY`,
 m.`POINT_ZIP`
FROM clh_zip3_metric_features f
LEFT JOIN clh_zip3_source_metadata m
 ON f.YEAR=m.YEAR AND f.ZIP3=m.ZIP3;

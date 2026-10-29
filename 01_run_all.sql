-- Databricks notebook source

-- EDIT ONLY THE SETTINGS IN THIS CELL FIRST.
-- Fully qualified Unity Catalog source/target names, without backticks.
DECLARE OR REPLACE VARIABLE clh_source_table STRING DEFAULT '110189_ctg_prod_exp.ds_public.clh_achrq_2022_zipcode';

-- COMMAND ----------

DECLARE OR REPLACE VARIABLE clh_source_year INT DEFAULT 2022;

-- COMMAND ----------

DECLARE OR REPLACE VARIABLE clh_seed_path STRING DEFAULT '/Volumes/YOUR_CATALOG/YOUR_SCHEMA/YOUR_VOLUME/clh_zip3_sql_only/metrics_seed.csv';

-- COMMAND ----------

DECLARE OR REPLACE VARIABLE clh_target_table STRING DEFAULT '110189_ctg_prod_exp.ds_public.clh_2022_zip3_features';

-- COMMAND ----------

DECLARE OR REPLACE VARIABLE clh_qa_target_table STRING DEFAULT '110189_ctg_prod_exp.ds_public.clh_2022_zip3_features_qa';

-- COMMAND ----------

-- OFF BY DEFAULT. Turning this on creates new tables; it does NOT replace existing tables.
DECLARE OR REPLACE VARIABLE clh_publish_results BOOLEAN DEFAULT FALSE;

-- COMMAND ----------

DECLARE OR REPLACE VARIABLE clh_sql STRING;

-- COMMAND ----------

SELECT assert_true(
  clh_source_table RLIKE '^[A-Za-z0-9_]+[.][A-Za-z0-9_]+[.][A-Za-z0-9_]+$'
  AND clh_target_table RLIKE '^[A-Za-z0-9_]+[.][A-Za-z0-9_]+[.][A-Za-z0-9_]+$'
  AND clh_qa_target_table RLIKE '^[A-Za-z0-9_]+[.][A-Za-z0-9_]+[.][A-Za-z0-9_]+$'
  AND clh_target_table <> clh_qa_target_table
  AND clh_target_table <> clh_source_table AND clh_qa_target_table <> clh_source_table
  AND clh_source_year BETWEEN 2000 AND 2100,
  'Use distinct three-part source/target names containing only letters, numbers, underscores; check year.'
) AS settings_check;

-- COMMAND ----------

-- Read the CSV directly from your Volume; no Python or dbt is needed.
-- Keep CSV header field order unchanged. quote/escape preserve embedded JSON quotes.
CREATE OR REPLACE TEMP VIEW _clh3_seed_raw AS
SELECT * FROM read_files(
 clh_seed_path,format=>'csv',header=>true,multiLine=>true,
 quote=>'"',escape=>'"',mode=>'FAILFAST',
 schema=>'enabled STRING, source_column STRING, output_column STRING, geography STRING, method STRING, value_expression STRING, weight_expression STRING, valid_expression STRING, approximate STRING, weight_basis STRING, options_json STRING, notes STRING, worksheet_method STRING, worksheet_dependencies STRING'
);

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_seed AS
SELECT
 CASE WHEN LOWER(TRIM(enabled)) IN ('1','true','yes') THEN TRUE
      WHEN LOWER(TRIM(enabled)) IN ('0','false','no') THEN FALSE END AS enabled,
 TRIM(source_column) AS source_column, TRIM(output_column) AS output_column,
 UPPER(TRIM(geography)) AS geography, LOWER(TRIM(method)) AS method,
 TRIM(value_expression) AS value_expression, TRIM(weight_expression) AS weight_expression,
 TRIM(valid_expression) AS valid_expression,
 CASE WHEN LOWER(TRIM(approximate)) IN ('1','true','yes') THEN TRUE
      WHEN LOWER(TRIM(approximate)) IN ('0','false','no') THEN FALSE END AS approximate,
 weight_basis, notes, worksheet_method, worksheet_dependencies,
 FROM_JSON(options_json,
   'STRUCT<quartile_outputs:ARRAY<STRING>,bins:ARRAY<STRUCT<lower:DOUBLE,upper:DOUBLE,count_expr:STRING,label:STRING>>>') AS options
FROM _clh3_seed_raw;

-- COMMAND ----------

SELECT assert_true(COUNT(*)>0 AND COUNT_IF(enabled IS NULL OR approximate IS NULL)=0,
 'Seed is empty or contains invalid enabled/approximate flags; use 0/1 or true/false.') AS seed_flag_check
FROM _clh3_seed;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_active_seed AS
SELECT * FROM _clh3_seed WHERE enabled;

-- COMMAND ----------

SELECT assert_true(COUNT(*)>0
 AND COUNT(*)=COUNT(DISTINCT output_column)
 AND COUNT_IF(COALESCE(
   output_column RLIKE '^[A-Za-z][A-Za-z0-9_]*$'
   AND output_column NOT IN ('YEAR','ZIP3') AND output_column NOT RLIKE '^__BIN_'
   AND geography IN ('ZCTA','ZIP')
   AND method IN ('sum','weighted_mean','ratio','mode','svi','pooled_age_median','gini_between')
   AND (method NOT IN ('svi','pooled_age_median','gini_between') OR geography='ZCTA')
   AND value_expression<>'' AND weight_expression<>'' AND valid_expression<>''
   AND options IS NOT NULL,FALSE))=COUNT(*),
 'Invalid/duplicate enabled seed definitions, unsupported method, or invalid options_json.') AS active_seed_check
FROM _clh3_active_seed;

-- COMMAND ----------

-- Discover source columns in Unity Catalog. These metadata rows are used only to
-- normalize numeric fields and validate seed references, not to read source values.
SET VAR clh_sql = CONCAT(
 'CREATE OR REPLACE TEMP VIEW _clh3_source_columns AS SELECT column_name, data_type, ordinal_position FROM `',
 SPLIT_PART(clh_source_table,'.',1),'`.information_schema.columns WHERE table_schema=',
 CHR(39),SPLIT_PART(clh_source_table,'.',2),CHR(39),' AND table_name=',
 CHR(39),SPLIT_PART(clh_source_table,'.',3),CHR(39)
);

-- COMMAND ----------

EXECUTE IMMEDIATE clh_sql;

-- COMMAND ----------

SELECT assert_true(COUNT(*)>0
 AND COUNT(DISTINCT CASE WHEN UPPER(column_name) IN ('YEAR','ZIPCODE','ZCTA','POINT_ZIP','STATEFIPS','STATE','REGION','TERRITORY') THEN UPPER(column_name) END)=8,
 'Source metadata unavailable or required CLH key/lineage columns absent. Check three-part name and permissions.') AS source_metadata_check
FROM _clh3_source_columns;

-- COMMAND ----------

SELECT assert_true(COUNT(*)=0,'Enabled seed source_column not found in source table.') AS seed_source_column_check
FROM _clh3_active_seed s LEFT ANTI JOIN _clh3_source_columns c
 ON UPPER(s.source_column)=UPPER(c.column_name);

-- COMMAND ----------

-- Special methods keep their options in the seed, not in hard-coded metric lists.
SELECT assert_true(COUNT(*)=0,'SVI needs four output names; pooled median needs at least two bins.') AS options_check
FROM _clh3_active_seed
WHERE (method='svi' AND COALESCE(SIZE(options.quartile_outputs),-1)<>4)
 OR (method='pooled_age_median' AND COALESCE(SIZE(options.bins),-1)<2);

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_bins AS
SELECT s.output_column AS parent_metric,p AS bin_order,
 b.lower AS lower_bound,b.upper AS upper_bound,b.count_expr,b.label,
 LAG(b.upper) OVER(PARTITION BY s.output_column ORDER BY p) AS prior_upper,
 SIZE(s.options.bins) AS bin_count
FROM _clh3_active_seed s
LATERAL VIEW POSEXPLODE(s.options.bins) e AS p,b
WHERE s.method='pooled_age_median';

-- COMMAND ----------

SELECT assert_true(COUNT_IF(COALESCE(
 lower_bound IS NOT NULL AND count_expr<>''
 AND (upper_bound IS NULL AND bin_order=bin_count-1 OR upper_bound>lower_bound)
 AND (bin_order=0 OR prior_upper=lower_bound),FALSE))=COUNT(*),
 'Median bins must be ordered, contiguous, disjoint and finite-width except the last open tail.') AS median_bin_check
FROM _clh3_bins;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_definition_seed AS
SELECT output_column AS metric,source_column AS source_field,geography,method,
 CASE WHEN approximate THEN 'approx' ELSE 'implemented' END AS implementation_status,
 CONCAT(COALESCE(notes,''),' Weight basis: ',COALESCE(weight_basis,'')) AS method_notes,
 CAST(NULL AS STRING) AS parent_metric,CAST(NULL AS INT) AS quartile
FROM _clh3_active_seed
UNION ALL
SELECT q,s.source_column,s.geography,'svi_share',
 CASE WHEN s.approximate THEN 'approx' ELSE 'implemented' END,
 CONCAT(COALESCE(s.notes,''),' Weight basis: ',COALESCE(s.weight_basis,'')),
 s.output_column,p+1
FROM _clh3_active_seed s LATERAL VIEW POSEXPLODE(s.options.quartile_outputs) e AS p,q
WHERE s.method='svi';

-- COMMAND ----------

SELECT assert_true(COUNT(*)=COUNT(DISTINCT metric)
 AND COUNT_IF(COALESCE(metric RLIKE '^[A-Za-z][A-Za-z0-9_]*$'
 AND metric NOT IN ('YEAR','ZIP3') AND metric NOT RLIKE '^__BIN_',FALSE))=COUNT(*),
 'Duplicate/reserved output name, including SVI quartile names.') AS output_names_check
FROM _clh3_definition_seed;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_expression_seed AS
SELECT output_column AS metric,method,geography,value_expression,weight_expression,valid_expression
FROM _clh3_active_seed WHERE method<>'pooled_age_median'
UNION ALL
SELECT CONCAT('__BIN_',s.output_column,'_',CAST(b.bin_order AS STRING)), 'sum',s.geography,
 b.count_expr,'1.0',
 CONCAT('(',s.valid_expression,') AND (',
   CONCAT_WS(' AND ',TRANSFORM(s.options.bins,x->CONCAT('((',x.count_expr,') IS NOT NULL AND (',x.count_expr,')>=0)'))),')')
FROM _clh3_active_seed s JOIN _clh3_bins b ON s.output_column=b.parent_metric;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_scalar_expressions AS
SELECT metric,e AS expression FROM _clh3_expression_seed
LATERAL VIEW EXPLODE(ARRAY(value_expression,weight_expression,valid_expression)) a AS e;

-- COMMAND ----------

-- This seed is executable calculation configuration. Keep it access-controlled.
-- Permit numeric scalar expressions only: no subqueries, comments, extra statements,
-- quoted identifiers, dotted names, SQL commands, aggregates or windows in expressions.
SELECT assert_true(COUNT_IF(COALESCE(
 expression IS NOT NULL AND LENGTH(expression)>0
 AND NOT (expression RLIKE ';|--|/[*]|[*]/|`')
 AND NOT (UPPER(expression) RLIKE '(^|[^A-Z0-9_])(SELECT|WITH|UNION|FROM|JOIN|OVER|EXECUTE|DECLARE|INSERT|UPDATE|DELETE|MERGE|CREATE|ALTER|DROP|GRANT|REVOKE|CALL|COPY|SUM|AVG|COUNT|MIN|MAX|COLLECT_LIST)([^A-Z0-9_]|$)')
 AND expression RLIKE CONCAT('^[A-Za-z0-9_ (),.+*/<>=!%',CHR(39),'-]+$'),FALSE))=COUNT(*),
 'Invalid scalar seed expression; only source fields, numeric arithmetic and approved scalar operators/functions are allowed.') AS expression_safety_check
FROM _clh3_scalar_expressions;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_allowed_tokens AS
SELECT UPPER(column_name) AS token FROM _clh3_source_columns
UNION
SELECT * FROM VALUES ('AND'),('OR'),('NOT'),('IS'),('NULL'),('TRUE'),('FALSE'),('BETWEEN'),
 ('IN'),('CASE'),('WHEN'),('THEN'),('ELSE'),('END'),('ABS'),('COALESCE'),('NULLIF'),
 ('GREATEST'),('LEAST'),('ROUND'),('TRIM'),('CAST'),('TRY_CAST'),('AS'),
 ('DOUBLE'),('FLOAT'),('INT'),('BIGINT'),('DECIMAL'),('BOOLEAN'),('STRING'),('POWER'),('SQRT') AS t(token);

-- COMMAND ----------

SELECT assert_true(COUNT(*)=0,'Unknown source field/function/token in enabled seed expression.') AS expression_token_check
FROM (
 SELECT DISTINCT UPPER(token) AS token FROM _clh3_scalar_expressions
 LATERAL VIEW EXPLODE(REGEXP_EXTRACT_ALL(expression,'[A-Za-z_][A-Za-z0-9_]*',0)) t AS token
) t LEFT ANTI JOIN _clh3_allowed_tokens a ON t.token=a.token;

-- COMMAND ----------

-- Generate safe typed projection. Known character identifiers remain strings;
-- other fields are TRY_CAST to DOUBLE even if the XLSX import made them strings.
CREATE OR REPLACE TEMP VIEW _clh3_source_projection AS
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
FROM _clh3_source_columns;

-- COMMAND ----------

SET VAR clh_sql = (
 SELECT CONCAT('CREATE OR REPLACE TEMP VIEW _clh3_source AS SELECT ',
  CONCAT_WS(', ',TRANSFORM(ARRAY_SORT(COLLECT_LIST(NAMED_STRUCT('position',ordinal_position,'sql',projection))),x->x.sql)),
  ' FROM `',REPLACE(clh_source_table,'.','`.`'),'` WHERE TRY_CAST(YEAR AS INT)=',CAST(clh_source_year AS STRING))
 FROM _clh3_source_projection
);

-- COMMAND ----------

EXECUTE IMMEDIATE clh_sql;

-- COMMAND ----------

SELECT assert_true(COUNT(*)>0 AND COUNT(*)=COUNT(DISTINCT ZIPCODE),
 'No source records for this year, or duplicate normalized ZIPCODE keys. Resolve before aggregation.') AS source_key_check
FROM _clh3_source WHERE ZIPCODE RLIKE '^[0-9]{5}$';

-- COMMAND ----------

-- The seed chooses each metric's expressions. Chunking keeps SQL plan sizes manageable.
CREATE OR REPLACE TEMP VIEW _clh3_struct_fragments AS
SELECT CAST(FLOOR((ROW_NUMBER() OVER(ORDER BY metric)-1)/40) AS INT) AS chunk_id,metric,
 CONCAT('named_struct(',
 CHR(39),'metric',CHR(39),',',CHR(39),metric,CHR(39),',',
 CHR(39),'method',CHR(39),',',CHR(39),method,CHR(39),',',
 CHR(39),'geography',CHR(39),',',CHR(39),geography,CHR(39),',',
 CHR(39),'value',CHR(39),',TRY_CAST((',value_expression,') AS DOUBLE),',
 CHR(39),'weight',CHR(39),',TRY_CAST((',weight_expression,') AS DOUBLE),',
 CHR(39),'pair_valid',CHR(39),',COALESCE((',valid_expression,'),FALSE))') AS fragment
FROM _clh3_expression_seed;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_chunk_queries AS
SELECT chunk_id,
 CONCAT('SELECT s.YEAR,s.ZIPCODE,s.ZCTA,s.POINT_ZIP,m.* FROM _clh3_source s LATERAL VIEW EXPLODE(ARRAY(',
 CONCAT_WS(',',TRANSFORM(ARRAY_SORT(COLLECT_LIST(NAMED_STRUCT('metric',metric,'sql',fragment))),x->x.sql)),
 ')) e AS m WHERE s.ZIPCODE RLIKE ',CHR(39),'^[0-9]{5}$',CHR(39)) AS query
FROM _clh3_struct_fragments GROUP BY chunk_id;

-- COMMAND ----------

SET VAR clh_sql=(SELECT CONCAT('CREATE OR REPLACE TEMP VIEW _clh3_raw_long AS ',
 CONCAT_WS(' UNION ALL ',TRANSFORM(ARRAY_SORT(COLLECT_LIST(NAMED_STRUCT('chunk',chunk_id,'sql',query))),x->x.sql)))
 FROM _clh3_chunk_queries);

-- COMMAND ----------

EXECUTE IMMEDIATE clh_sql;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_keys AS
SELECT DISTINCT YEAR, SUBSTRING(ZIPCODE,1,3) AS ZIP3 FROM _clh3_source WHERE ZIPCODE RLIKE '^[0-9]{5}$'
UNION
SELECT DISTINCT YEAR, SUBSTRING(ZCTA,1,3) AS ZIP3 FROM _clh3_source WHERE ZCTA RLIKE '^[0-9]{5}$';

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_lineage AS
SELECT YEAR,SUBSTRING(ZIPCODE,1,3) AS ZIP3,
 COUNT(*) AS native_zip_rows,COUNT(DISTINCT ZCTA) AS mapped_zctas,
 COUNT_IF(POINT_ZIP=1) AS point_zip_rows,
 SORT_ARRAY(COLLECT_SET(STATEFIPS)) AS statefips_set,
 SORT_ARRAY(COLLECT_SET(STATE)) AS state_set,
 SORT_ARRAY(COLLECT_SET(REGION)) AS region_set,
 SORT_ARRAY(COLLECT_SET(TERRITORY)) AS territory_set
FROM _clh3_source WHERE ZIPCODE RLIKE '^[0-9]{5}$'
GROUP BY YEAR,SUBSTRING(ZIPCODE,1,3);

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_zcta_grouped AS
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
FROM _clh3_raw_long
WHERE geography='ZCTA' AND POINT_ZIP=0 AND ZCTA RLIKE '^[0-9]{5}$'
GROUP BY YEAR,ZCTA,metric,method;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_contributions AS
SELECT YEAR, SUBSTRING(ZCTA,1,3) AS ZIP3, ZCTA AS unit_id,
  'ZCTA' AS geography, metric, method,
  CASE WHEN exact_rows=1 THEN exact_value
       WHEN exact_rows=0 AND same_prefix_rows=candidate_rows AND signature_count=1 THEN fallback_value END AS value,
  CASE WHEN exact_rows=1 THEN exact_weight
       WHEN exact_rows=0 AND same_prefix_rows=candidate_rows AND signature_count=1 THEN fallback_weight END AS weight,
  CASE WHEN exact_rows=1 THEN exact_valid=1
       WHEN exact_rows=0 AND same_prefix_rows=candidate_rows AND signature_count=1 THEN fallback_valid=1 ELSE FALSE END AS pair_valid,
  CASE WHEN exact_rows=1 THEN 'EXACT_ZIP_ZCTA'
       WHEN exact_rows=0 AND same_prefix_rows=candidate_rows AND signature_count=1 THEN 'UNAMBIGUOUS_FALLBACK'
       ELSE 'UNRESOLVED_FALLBACK' END AS contribution_rule,
  candidate_rows AS raw_mapping_rows, signature_count>1 AS mapped_values_differ
FROM _clh3_zcta_grouped
UNION ALL
SELECT YEAR,SUBSTRING(ZIPCODE,1,3),ZIPCODE,'ZIP',metric,method,value,weight,pair_valid,
  'NATIVE_ZIP',CAST(1 AS BIGINT),FALSE
FROM _clh3_raw_long WHERE geography='ZIP';

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_valid AS
SELECT *, (pair_valid AND (value IS NOT NULL AND value BETWEEN -1.7976931348623157E308 AND 1.7976931348623157E308) AND (weight IS NOT NULL AND weight BETWEEN -1.7976931348623157E308 AND 1.7976931348623157E308) AND weight>0) AS usable FROM _clh3_contributions;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_stats AS
SELECT YEAR,ZIP3,metric,method,geography,
  COUNT(*) AS source_units,
  COUNT_IF(usable) AS valid_units,
  COUNT_IF(contribution_rule='UNAMBIGUOUS_FALLBACK') AS fallback_units,
  COUNT_IF(contribution_rule='UNRESOLVED_FALLBACK') AS unresolved_units,
  COUNT_IF(mapped_values_differ) AS mapped_value_conflict_units,
  COUNT_IF(weight IS NULL OR NOT (weight BETWEEN 0 AND 1.7976931348623157E308)) AS unknown_weight_units,
  SUM(CASE WHEN weight BETWEEN 0 AND 1.7976931348623157E308 THEN weight END) AS total_known_weight,
  SUM(CASE WHEN usable THEN weight END) AS valid_weight,
  SUM(CASE WHEN usable THEN value END) AS sum_value,
  SUM(CASE WHEN usable THEN value*weight END) AS sum_value_weight,
  SUM(CASE WHEN usable AND value BETWEEN 0 AND .25 THEN weight ELSE 0 END) AS q1_weight,
  SUM(CASE WHEN usable AND value>.25 AND value<=.5 THEN weight ELSE 0 END) AS q2_weight,
  SUM(CASE WHEN usable AND value>.5 AND value<=.75 THEN weight ELSE 0 END) AS q3_weight,
  SUM(CASE WHEN usable AND value>.75 AND value<=1 THEN weight ELSE 0 END) AS q4_weight
FROM _clh3_valid GROUP BY YEAR,ZIP3,metric,method,geography;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_mode AS
WITH by_code AS (
 SELECT YEAR,ZIP3,metric,value,SUM(weight) AS code_weight FROM _clh3_valid
 WHERE method='mode' AND usable GROUP BY YEAR,ZIP3,metric,value
), ranked AS (
 SELECT *,MAX(code_weight) OVER(PARTITION BY YEAR,ZIP3,metric) AS max_weight FROM by_code
)
SELECT YEAR,ZIP3,metric,
 CASE WHEN COUNT_IF(code_weight=max_weight)=1 THEN MAX(CASE WHEN code_weight=max_weight THEN value END) END AS result,
 COUNT_IF(code_weight=max_weight)>1 AS mode_tied
FROM ranked GROUP BY YEAR,ZIP3,metric;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_gini AS
WITH ordered AS (
 SELECT YEAR,ZIP3,metric,unit_id,value,weight,
  COALESCE(SUM(weight) OVER(PARTITION BY YEAR,ZIP3,metric ORDER BY value,unit_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS prior_w,
  COALESCE(SUM(weight*value) OVER(PARTITION BY YEAR,ZIP3,metric ORDER BY value,unit_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS prior_wm
 FROM _clh3_valid WHERE method='gini_between' AND usable AND value>=0
)
SELECT YEAR,ZIP3,metric,
 SUM(weight*(value*prior_w-prior_wm))/NULLIF(SUM(weight)*SUM(weight*value),0) AS result
FROM ordered GROUP BY YEAR,ZIP3,metric;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_bin_map AS
SELECT CONCAT('__BIN_',parent_metric,'_',CAST(bin_order AS STRING)) AS metric,
 parent_metric,bin_order,lower_bound,upper_bound FROM _clh3_bins;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_median AS
WITH bins AS (
 SELECT s.YEAR,s.ZIP3,b.parent_metric,b.bin_order,b.lower_bound,b.upper_bound,s.sum_value AS bin_count,
  SUM(s.sum_value) OVER(PARTITION BY s.YEAR,s.ZIP3,b.parent_metric) AS total_count,
  SUM(s.sum_value) OVER(PARTITION BY s.YEAR,s.ZIP3,b.parent_metric ORDER BY b.bin_order ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_count
 FROM _clh3_stats s JOIN _clh3_bin_map b ON s.metric=b.metric
), median_bin AS (
 SELECT *,cumulative_count-bin_count AS previous_count FROM bins
 WHERE total_count>0 AND bin_count>0
)
SELECT YEAR,ZIP3,parent_metric AS metric,
 MAX(CASE WHEN previous_count<total_count/2 AND cumulative_count>=total_count/2
  AND upper_bound IS NOT NULL THEN lower_bound+(total_count/2-previous_count)/bin_count*(upper_bound-lower_bound) END) AS result
FROM median_bin GROUP BY YEAR,ZIP3,parent_metric;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_results AS
SELECT s.YEAR,s.ZIP3,s.metric,
 CASE WHEN s.method='sum' THEN s.sum_value
      WHEN s.method IN ('weighted_mean','svi') THEN s.sum_value_weight/NULLIF(s.valid_weight,0)
      WHEN s.method='ratio' THEN s.sum_value/NULLIF(s.valid_weight,0)
      WHEN s.method='mode' THEN m.result
      WHEN s.method='gini_between' THEN g.result END AS result
FROM _clh3_stats s
LEFT JOIN _clh3_mode m ON s.YEAR=m.YEAR AND s.ZIP3=m.ZIP3 AND s.metric=m.metric
LEFT JOIN _clh3_gini g ON s.YEAR=g.YEAR AND s.ZIP3=g.ZIP3 AND s.metric=g.metric
WHERE s.metric NOT RLIKE '^__BIN_'
UNION ALL SELECT YEAR,ZIP3,metric,result FROM _clh3_median
UNION ALL
SELECT s.YEAR,s.ZIP3,d.metric,
 100.0*CASE d.quartile WHEN 1 THEN s.q1_weight WHEN 2 THEN s.q2_weight
                     WHEN 3 THEN s.q3_weight WHEN 4 THEN s.q4_weight END/NULLIF(s.total_known_weight,0)
FROM _clh3_stats s JOIN _clh3_definition_seed d ON s.metric=d.parent_metric
WHERE d.method='svi_share';

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_definitions AS
SELECT metric,source_field,geography,method,implementation_status,method_notes
FROM _clh3_definition_seed;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_qa_stats AS
SELECT YEAR,ZIP3,metric,source_units,valid_units,fallback_units,unresolved_units,
 mapped_value_conflict_units,unknown_weight_units,total_known_weight,valid_weight
FROM _clh3_stats WHERE metric NOT RLIKE '^__BIN_'
UNION ALL
SELECT s.YEAR,s.ZIP3,d.metric,s.source_units,s.valid_units,s.fallback_units,s.unresolved_units,
 s.mapped_value_conflict_units,s.unknown_weight_units,s.total_known_weight,s.valid_weight
FROM _clh3_stats s JOIN _clh3_definition_seed d ON s.metric=d.parent_metric
WHERE d.method='svi_share'
UNION ALL
SELECT s.YEAR,s.ZIP3,b.parent_metric,s.source_units,s.valid_units,s.fallback_units,s.unresolved_units,
 s.mapped_value_conflict_units,s.unknown_weight_units,s.total_known_weight,s.valid_weight
FROM _clh3_stats s JOIN _clh3_bin_map b ON s.metric=b.metric WHERE b.bin_order=0;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _clh3_qa AS
SELECT k.YEAR,k.ZIP3,d.metric,d.source_field,d.geography,d.method,d.implementation_status,d.method_notes,
 r.result AS metric_value,
 s.source_units,s.valid_units,s.fallback_units,s.unresolved_units,s.mapped_value_conflict_units,s.unknown_weight_units,
 s.total_known_weight,s.valid_weight,
 100.0*COALESCE(s.valid_weight,0)/NULLIF(s.total_known_weight,0) AS pct_known_weight_covered,
 100.0*COALESCE(s.valid_units,0)/NULLIF(s.source_units,0) AS pct_units_covered,
 COALESCE(m.mode_tied,FALSE) AS mode_tied,
 CASE WHEN d.implementation_status='held' THEN 'HELD_METHOD_UNRESOLVED'
      WHEN COALESCE(s.source_units,0)=0 THEN 'NO_SOURCE_CONTRIBUTIONS'
      WHEN COALESCE(s.valid_units,0)=0 THEN 'NO_VALID_CONTRIBUTIONS'
      WHEN m.mode_tied THEN 'MODE_TIE'
      WHEN r.result IS NULL THEN 'UNDEFINED_RESULT'
      WHEN COALESCE(s.unresolved_units,0)>0 OR COALESCE(s.unknown_weight_units,0)>0
        OR COALESCE(s.valid_weight,0) < s.total_known_weight - 1E-10*GREATEST(1.0,ABS(s.total_known_weight)) THEN 'PARTIAL_COVERAGE'
      ELSE 'COMPUTED' END AS qa_status,
 'clh_zip3_sql_only_v3' AS method_version,
 'ZCTA-prefix approximation for ZCTA fields; postal-prefix grouping for ZIP fields' AS geography_policy
FROM _clh3_keys k CROSS JOIN _clh3_definitions d
LEFT JOIN _clh3_results r ON k.YEAR=r.YEAR AND k.ZIP3=r.ZIP3 AND d.metric=r.metric
LEFT JOIN _clh3_qa_stats s ON k.YEAR=s.YEAR AND k.ZIP3=s.ZIP3 AND d.metric=s.metric
LEFT JOIN _clh3_mode m ON k.YEAR=m.YEAR AND k.ZIP3=m.ZIP3 AND d.metric=m.metric;

-- COMMAND ----------

-- Output column names also come from the seed. Disabled rows do not appear.
SET VAR clh_sql=(SELECT CONCAT('CREATE OR REPLACE TEMP VIEW _clh3_final AS SELECT YEAR,ZIP3,',
 CONCAT_WS(',',TRANSFORM(ARRAY_SORT(COLLECT_LIST(NAMED_STRUCT('metric',metric,'sql',
  CONCAT('MAX(CASE WHEN metric=',CHR(39),metric,CHR(39),' THEN metric_value END) AS `',metric,'`')))),x->x.sql)),
 ' FROM _clh3_qa GROUP BY YEAR,ZIP3') FROM _clh3_definitions);

-- COMMAND ----------

EXECUTE IMMEDIATE clh_sql;

-- COMMAND ----------

-- PREVIEW. No permanent tables have been created at this point.
SELECT (SELECT COUNT(*) FROM _clh3_seed) AS seed_rows,
       (SELECT COUNT(*) FROM _clh3_active_seed) AS enabled_definitions,
       (SELECT COUNT(*) FROM _clh3_definitions) AS output_metrics,
       (SELECT COUNT(*) FROM _clh3_final) AS zip3_rows;

-- COMMAND ----------

SELECT * FROM _clh3_final WHERE ZIP3='980';

-- COMMAND ----------

SELECT metric,metric_value,method,implementation_status,qa_status,
 source_units,valid_units,pct_known_weight_covered,method_notes
FROM _clh3_qa WHERE ZIP3='980' ORDER BY metric;

-- COMMAND ----------

-- OPTIONAL PUBLICATION. clh_publish_results is FALSE by default in the settings cell.
-- Both targets must be new names. This never overwrites existing tables.
SET VAR clh_sql=CASE WHEN clh_publish_results THEN CONCAT(
 'CREATE TABLE `',REPLACE(clh_target_table,'.','`.`'),'` USING DELTA AS SELECT * FROM _clh3_final')
 ELSE CONCAT('SELECT ',CHR(39),'Preview only: result table was not created.',CHR(39),' AS publication_status') END;

-- COMMAND ----------

EXECUTE IMMEDIATE clh_sql;

-- COMMAND ----------

SET VAR clh_sql=CASE WHEN clh_publish_results THEN CONCAT(
 'CREATE TABLE `',REPLACE(clh_qa_target_table,'.','`.`'),'` USING DELTA AS SELECT * FROM _clh3_qa')
 ELSE CONCAT('SELECT ',CHR(39),'Preview only: QA table was not created.',CHR(39),' AS publication_status') END;

-- COMMAND ----------

EXECUTE IMMEDIATE clh_sql;

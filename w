CREATE OR REPLACE TABLE 110189_ctg_prod_exp.ds_public.clh_2022_zip3
USING DELTA
AS
SELECT *
FROM clh_zip3_features;

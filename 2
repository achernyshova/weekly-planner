WITH staged AS (
    SELECT
        array_max(
            transform(
                filter(split(ItemToDate, ';'), x -> trim(x) <> ''),
                x -> to_date(trim(x), 'MMddyyyy')
            )
        ) AS max_item_to_date,

        array_max(
            transform(
                filter(split(ItemServiceDate, ';'), x -> trim(x) <> ''),
                x -> to_date(trim(x), 'MMddyyyy')
            )
        ) AS max_item_service_date,

        to_date(DischargeDate, 'MMddyyyy') AS discharge_date

    FROM health_verity_eng_exp.archive_staged.solventum_input_layer_v202602
),

dated AS (
    SELECT
        coalesce(
            max_item_to_date,
            max_item_service_date,
            discharge_date
        ) AS service_end_date
    FROM staged
),

monthly_counts AS (
    SELECT
        CAST(date_trunc('MONTH', service_end_date) AS DATE) AS month_start,
        COUNT(*) AS row_count
    FROM dated
    WHERE service_end_date >= DATE '2026-01-01'
      AND service_end_date <  DATE '2027-01-01'
    GROUP BY CAST(date_trunc('MONTH', service_end_date) AS DATE)
),

months AS (
    SELECT explode(
        sequence(
            DATE '2026-01-01',
            DATE '2026-12-01',
            INTERVAL 1 MONTH
        )
    ) AS month_start
)

SELECT
    date_format(m.month_start, 'yyyy-MM') AS month,
    coalesce(c.row_count, 0) AS row_count
FROM months m
LEFT JOIN monthly_counts c
    ON m.month_start = c.month_start
ORDER BY m.month_start;

-- ============================================================================
-- Phase 3: Raw data audit
-- Global Leadership Pipeline Conversion Gap
-- ============================================================================
-- Read-only checks against raw.emp_sex_occupation and raw.wb_country_class,
-- run before building clean.country_year_managers. The inclusion rules in
-- 04_build_clean_managers.sql come from these results.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 3.1 Which survey sources feed the raw table
-- ----------------------------------------------------------------------------
SELECT source, COUNT(*) AS row_count
FROM raw.emp_sex_occupation
GROUP BY source
ORDER BY row_count DESC
LIMIT 30;

SELECT LEFT(source, 2) AS source_prefix, COUNT(*) AS row_count
FROM raw.emp_sex_occupation
GROUP BY LEFT(source, 2)
ORDER BY row_count DESC;


-- ----------------------------------------------------------------------------
-- 3.2 ISCO vintage per country-year
-- Usable = ISCO-08 or ISCO-88 available. ISCO-68-only country-years are
-- excluded: its group 0-1 conflates managers with armed forces.
-- Result: 6,228 total country-years, 5,315 usable, 292 ISCO-68-only.
-- ----------------------------------------------------------------------------
WITH classification_flag AS (
    SELECT
        ref_area,
        time,
        MAX(CASE WHEN classif1 LIKE 'OCU_ISCO08%' THEN 1 ELSE 0 END) AS has_isco08,
        MAX(CASE WHEN classif1 LIKE 'OCU_ISCO88%' THEN 1 ELSE 0 END) AS has_isco88,
        MAX(CASE WHEN classif1 LIKE 'OCU_ISCO68%' THEN 1 ELSE 0 END) AS has_isco68
    FROM raw.emp_sex_occupation
    GROUP BY ref_area, time
)
SELECT
    COUNT(*) AS total_country_years,
    SUM(CASE WHEN has_isco08 = 1 OR has_isco88 = 1 THEN 1 ELSE 0 END) AS usable_country_years,
    SUM(CASE WHEN has_isco08 = 0 AND has_isco88 = 0 AND has_isco68 = 1 THEN 1 ELSE 0 END) AS isco68_only_country_years
FROM classification_flag;


-- ----------------------------------------------------------------------------
-- 3.3 Every manager row has a matching employment total
-- Expect zero.
-- ----------------------------------------------------------------------------
WITH managers AS (
    SELECT DISTINCT ref_area, time, sex
    FROM raw.emp_sex_occupation
    WHERE classif1 IN ('OCU_ISCO08_1', 'OCU_ISCO88_1')
),
totals AS (
    SELECT DISTINCT ref_area, time, sex
    FROM raw.emp_sex_occupation
    WHERE classif1 = 'OCU_SKILL_TOTAL'
)
SELECT COUNT(*) AS manager_rows_missing_a_total
FROM managers m
LEFT JOIN totals t
    ON m.ref_area = t.ref_area AND m.time = t.time AND m.sex = t.sex
WHERE t.ref_area IS NULL;


-- ----------------------------------------------------------------------------
-- 3.4 Integrity check -- female counts should never exceed totals
-- Expect zero rows.
-- ----------------------------------------------------------------------------
SELECT ref_area, time, classif1,
       MAX(CASE WHEN sex = 'SEX_F' THEN obs_value::numeric END) AS female_value,
       MAX(CASE WHEN sex = 'SEX_T' THEN obs_value::numeric END) AS total_value
FROM raw.emp_sex_occupation
WHERE classif1 = 'OCU_SKILL_TOTAL'
GROUP BY ref_area, time, classif1
HAVING MAX(CASE WHEN sex = 'SEX_F' THEN obs_value::numeric END)
     > MAX(CASE WHEN sex = 'SEX_T' THEN obs_value::numeric END);


-- ----------------------------------------------------------------------------
-- 3.5 Country coverage: usable ILOSTAT codes, and coverage by year
-- ----------------------------------------------------------------------------
WITH classification_flag AS (
    SELECT
        ref_area,
        time,
        MAX(CASE WHEN classif1 LIKE 'OCU_ISCO08%' THEN 1 ELSE 0 END) AS has_isco08,
        MAX(CASE WHEN classif1 LIKE 'OCU_ISCO88%' THEN 1 ELSE 0 END) AS has_isco88
    FROM raw.emp_sex_occupation
    GROUP BY ref_area, time
)
SELECT COUNT(DISTINCT ref_area) AS usable_country_count
FROM classification_flag
WHERE has_isco08 = 1 OR has_isco88 = 1;

SELECT
    time,
    COUNT(DISTINCT ref_area) AS country_count
FROM raw.emp_sex_occupation
WHERE classif1 LIKE 'OCU_ISCO08%' OR classif1 LIKE 'OCU_ISCO88%'
GROUP BY time
ORDER BY time;


-- ----------------------------------------------------------------------------
-- 3.6 Match ILOSTAT codes against the World Bank classification
-- ----------------------------------------------------------------------------
SELECT
    COUNT(DISTINCT e.ref_area) AS ilostat_usable_countries,
    COUNT(DISTINCT w.code) AS matched_to_world_bank
FROM (
    SELECT DISTINCT ref_area
    FROM raw.emp_sex_occupation
    WHERE classif1 LIKE 'OCU_ISCO08%' OR classif1 LIKE 'OCU_ISCO88%'
) e
LEFT JOIN raw.wb_country_class w
    ON e.ref_area = w.code;


-- ----------------------------------------------------------------------------
-- 3.7 Which ILOSTAT codes have no World Bank match
-- ----------------------------------------------------------------------------
SELECT DISTINCT e.ref_area
FROM (
    SELECT DISTINCT ref_area
    FROM raw.emp_sex_occupation
    WHERE classif1 LIKE 'OCU_ISCO08%' OR classif1 LIKE 'OCU_ISCO88%'
) e
LEFT JOIN raw.wb_country_class w
    ON e.ref_area = w.code
WHERE w.code IS NULL
ORDER BY e.ref_area;


-- ----------------------------------------------------------------------------
-- 3.8 Check ref_area carries no padding that would break the join
-- ----------------------------------------------------------------------------
SELECT ref_area, LENGTH(ref_area) FROM raw.emp_sex_occupation WHERE ref_area LIKE '%USA%' LIMIT 3;


-- ----------------------------------------------------------------------------
-- 3.9 Split the unmatched codes: ILOSTAT aggregates (prefixed 'X') vs. other
-- ----------------------------------------------------------------------------
SELECT
    SUM(CASE WHEN e.ref_area LIKE 'X%' THEN 1 ELSE 0 END) AS x_prefixed_aggregates,
    SUM(CASE WHEN e.ref_area NOT LIKE 'X%' THEN 1 ELSE 0 END) AS other_unmatched
FROM (
    SELECT DISTINCT ref_area
    FROM raw.emp_sex_occupation
    WHERE classif1 LIKE 'OCU_ISCO08%' OR classif1 LIKE 'OCU_ISCO88%'
) e
LEFT JOIN raw.wb_country_class w
    ON e.ref_area = w.code
WHERE w.code IS NULL;

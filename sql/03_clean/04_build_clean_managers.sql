-- Phase 4: build clean.country_year_managers
-- One row per country-year with typed numeric employment and manager counts.
-- Inclusion rules (from Phase 3 audit):
--   - Prefer ISCO-08 when available for a country-year, fall back to ISCO-88
--   - Drop ISCO-68-only country-years entirely (group 0-1 conflates managers
--     with armed forces, cannot be split)
--   - Drop ILOSTAT regional/income-group aggregate codes (prefixed 'X')

-- Step 1: table structure
CREATE TABLE clean.country_year_managers (
    ref_area          VARCHAR(3)  NOT NULL,
    year              INTEGER     NOT NULL,
    isco_version      VARCHAR(6)  NOT NULL,
    female_employment NUMERIC,
    total_employment  NUMERIC,
    female_managers   NUMERIC,
    total_managers    NUMERIC,
    PRIMARY KEY (ref_area, year)
);

-- Step 2: view deciding which ISCO version applies per country-year
CREATE OR REPLACE VIEW clean.v_isco_version_choice AS
SELECT
    ref_area,
    time::INTEGER AS year,
    CASE WHEN MAX(CASE WHEN classif1 LIKE 'OCU_ISCO08%' THEN 1 ELSE 0 END) = 1
         THEN 'ISCO08'
         ELSE 'ISCO88'
    END AS isco_version
FROM raw.emp_sex_occupation
WHERE classif1 LIKE 'OCU_ISCO08%' OR classif1 LIKE 'OCU_ISCO88%'
GROUP BY ref_area, time;

-- Step 3: reshape raw long-format data into clean wide rows
-- (Fixed version: classification codes need the 'OCU_' prefix, e.g.
-- 'OCU_ISCO08_1', not just 'ISCO08_1' -- caught during reconciliation.)
INSERT INTO clean.country_year_managers
    (ref_area, year, isco_version, female_employment, total_employment, female_managers, total_managers)
SELECT
    e.ref_area,
    e.time::INTEGER AS year,
    v.isco_version,
    MAX(CASE WHEN e.sex = 'SEX_F' AND e.classif1 = 'OCU_SKILL_TOTAL' THEN e.obs_value::NUMERIC END) AS female_employment,
    MAX(CASE WHEN e.sex = 'SEX_T' AND e.classif1 = 'OCU_SKILL_TOTAL' THEN e.obs_value::NUMERIC END) AS total_employment,
    MAX(CASE WHEN e.sex = 'SEX_F' AND e.classif1 = ('OCU_' || v.isco_version || '_1') THEN e.obs_value::NUMERIC END) AS female_managers,
    MAX(CASE WHEN e.sex = 'SEX_T' AND e.classif1 = ('OCU_' || v.isco_version || '_1') THEN e.obs_value::NUMERIC END) AS total_managers
FROM raw.emp_sex_occupation e
JOIN clean.v_isco_version_choice v
    ON e.ref_area = v.ref_area AND e.time::INTEGER = v.year
WHERE e.ref_area NOT LIKE 'X%'
GROUP BY e.ref_area, e.time, v.isco_version;

-- Step 4: integrity check -- female counts should never exceed totals
-- Expect zero rows.
SELECT *
FROM clean.country_year_managers
WHERE female_employment > total_employment
   OR female_managers > total_managers;

-- Step 5: reconciliation against ILO's own published SDG 5.5.2 figure
-- Confirms the independently-built ratio roughly agrees with ILO's own
-- calculation. Large disagreements concentrate in obs_status='U'
-- (statistically unreliable) rows -- see Step 6.
SELECT
    c.ref_area,
    c.year,
    ROUND(100.0 * c.female_managers / NULLIF(c.total_managers, 0), 2) AS my_computed_share,
    s.obs_value::NUMERIC AS ilo_published_share,
    ROUND(100.0 * c.female_managers / NULLIF(c.total_managers, 0) - s.obs_value::NUMERIC, 2) AS difference
FROM clean.country_year_managers c
JOIN raw.sdg_women_managers s
    ON c.ref_area = s.ref_area AND c.year = s.time::INTEGER
ORDER BY ABS(ROUND(100.0 * c.female_managers / NULLIF(c.total_managers, 0), 2) - s.obs_value::NUMERIC) DESC
LIMIT 20;

-- Step 6: add and populate a data quality flag
-- Rationale: 101 of 2,958 usable rows (3.4%) show a >30-point swing between
-- the manager-share ratio and the employment-share ratio -- consistent with
-- known small-sample volatility in ILOSTAT's underlying survey data,
-- corroborated by the obs_status='U' pattern found in Step 5's reconciliation.
-- Rows are retained, not deleted, but flagged so Phase 5 can exclude them
-- from headline rankings while keeping them visible in the underlying table.
ALTER TABLE clean.country_year_managers
    ADD COLUMN data_quality_flag BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE clean.country_year_managers
SET data_quality_flag = TRUE
WHERE female_managers IS NOT NULL AND total_managers IS NOT NULL
  AND female_employment IS NOT NULL AND total_employment IS NOT NULL
  AND ABS(
        (100.0 * female_managers / NULLIF(total_managers, 0)) -
        (100.0 * female_employment / NULLIF(total_employment, 0))
      ) > 30;

-- Verify: should return 101
SELECT COUNT(*) AS flagged_rows
FROM clean.country_year_managers
WHERE data_quality_flag = TRUE;

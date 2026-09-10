-- ============================================================================
-- Phase 5: Conversion Ratio Analysis
-- Global Leadership Pipeline Conversion Gap
-- ============================================================================
-- Metric: conversion_ratio = female_manager_share / female_employment_share
-- A ratio < 1.0 means women are under-represented in management relative to
-- their share of the workforce ("poor conversion"). A ratio >= 1.0 means
-- women hold management roles at or above their workforce share.
--
-- NOTE on raw.wb_country_class join:
-- ILOSTAT uses ref_area = 'KOS' for Kosovo; the World Bank classification
-- file uses code = 'XKX'. Every join below maps KOS -> XKX explicitly so
-- Kosovo isn't silently dropped. Without this fix, 189 of 190 possible
-- countries match; with it, all 190 match. (The other 10 unmatched ILOSTAT
-- codes -- AIA, ANT, COK, JEY, MSR, NIU, REU, SHN, TKL, WLF -- are small
-- territories genuinely absent from the World Bank list and are correctly
-- excluded.)
--
-- NOTE on female_employment_share scale:
-- Stored as a percentage (0-100), NOT a proportion (0-1). Range observed:
-- 6.98 to 56. Thresholds below use whole-number cut points (e.g. 40, not
-- 0.40) to match this scale.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 5.1 Country rankings by conversion ratio
-- ----------------------------------------------------------------------------
-- Top performers: Niger (1.625), Belize (1.446), Burkina Faso (1.378)
-- These are confirmed genuine outliers, not representative of their income
-- group -- see 5.5 below.

SELECT
    w.economy,
    r.ref_area,
    w.income_group,
    r.female_employment_share,
    r.female_manager_share,
    r.conversion_ratio
FROM clean.v_conversion_ratio r
JOIN raw.wb_country_class w
  ON w.code = CASE WHEN r.ref_area = 'KOS' THEN 'XKX' ELSE r.ref_area END
WHERE r.conversion_ratio IS NOT NULL
ORDER BY r.conversion_ratio DESC;


-- ----------------------------------------------------------------------------
-- 5.2 Decoupling quadrant -- headline finding
-- ----------------------------------------------------------------------------
-- 115 of 190 countries (60.5%) fall into "High participation, poor
-- conversion": women are well-represented in the workforce (>=40% share)
-- but underconvert into management (ratio < 1.0).

SELECT
    sub.quadrant,
    COUNT(*) AS n
FROM (
    SELECT
        r.ref_area,
        CASE
            WHEN r.female_employment_share >= 40 AND r.conversion_ratio < 1.0
                THEN 'High participation, poor conversion'
            WHEN r.female_employment_share >= 40 AND r.conversion_ratio >= 1.0
                THEN 'High participation, good conversion'
            WHEN r.female_employment_share < 40 AND r.conversion_ratio >= 1.0
                THEN 'Low participation, good conversion'
            ELSE 'Low participation, poor conversion'
        END AS quadrant
    FROM clean.v_conversion_ratio r
    JOIN raw.wb_country_class w
      ON w.code = CASE WHEN r.ref_area = 'KOS' THEN 'XKX' ELSE r.ref_area END
    WHERE r.conversion_ratio IS NOT NULL
) sub
GROUP BY sub.quadrant
ORDER BY COUNT(*) DESC;


-- ----------------------------------------------------------------------------
-- 5.3 Decoupling quadrant by income group -- key refinement of the headline
-- ----------------------------------------------------------------------------
-- The 60.5% figure is NOT evenly distributed. Poor-conversion rate as a
-- share of each income band's own countries:
--
--   High income:          54 / 67  = 80.6%
--   Upper middle income:  28 / 56  = 50.0%
--   Lower middle income:  22 / 45  = 48.9%
--   Low income:           11 / 22  = 50.0%
--
-- High-income economies underconvert at a far higher rate than every other
-- income band, which sit close together around 50%. This reframes the
-- finding from "a universal gap" to "a gap most acute in high-income
-- economies" -- including Germany (rank 6 by conversion ratio, 0.643).

SELECT
    sub.income_group,
    sub.quadrant,
    COUNT(*) AS n
FROM (
    SELECT
        r.ref_area,
        w.income_group,
        CASE
            WHEN r.female_employment_share >= 40 AND r.conversion_ratio < 1.0
                THEN 'High participation, poor conversion'
            WHEN r.female_employment_share >= 40 AND r.conversion_ratio >= 1.0
                THEN 'High participation, good conversion'
            WHEN r.female_employment_share < 40 AND r.conversion_ratio >= 1.0
                THEN 'Low participation, good conversion'
            ELSE 'Low participation, poor conversion'
        END AS quadrant
    FROM clean.v_conversion_ratio r
    JOIN raw.wb_country_class w
      ON w.code = CASE WHEN r.ref_area = 'KOS' THEN 'XKX' ELSE r.ref_area END
    WHERE r.conversion_ratio IS NOT NULL
) sub
GROUP BY sub.income_group, sub.quadrant
ORDER BY sub.income_group, sub.quadrant;


-- ----------------------------------------------------------------------------
-- 5.4 Validation check A -- who makes up High income's poor-conversion group
-- ----------------------------------------------------------------------------
-- Confirms the 80.6% high-income poor-conversion rate is broad-based, not
-- driven by a handful of small outlier economies. Dominated by large,
-- well-known economies with developed labor-market institutions: Japan,
-- Korea, Germany, Netherlands, Switzerland, France, UK, Australia, USA,
-- Sweden. A few small territories appear (San Marino, Luxembourg, Cayman
-- Islands) but are a minority of the 54.

SELECT
    w.economy,
    r.ref_area,
    r.female_employment_share,
    r.conversion_ratio
FROM clean.v_conversion_ratio r
JOIN raw.wb_country_class w
  ON w.code = CASE WHEN r.ref_area = 'KOS' THEN 'XKX' ELSE r.ref_area END
WHERE w.income_group = 'High income'
  AND r.female_employment_share >= 40
  AND r.conversion_ratio < 1.0
ORDER BY r.conversion_ratio ASC;


-- ----------------------------------------------------------------------------
-- 5.5 Validation check B -- Niger/Burkina Faso within low income as a group
-- ----------------------------------------------------------------------------
-- Confirms Niger, Burkina Faso, and Sudan are genuine outliers (ratio > 1.0)
-- against a low-income group where the median country still underconverts.
-- 17 of 22 low-income countries sit below 1.0, several far below
-- (Afghanistan 0.261, Guinea-Bissau 0.4). These three should not be read as
-- representative of low-income economies generally.

SELECT
    w.economy,
    r.ref_area,
    r.female_employment_share,
    r.conversion_ratio,
    RANK() OVER (ORDER BY r.conversion_ratio DESC) AS rank_within_low_income
FROM clean.v_conversion_ratio r
JOIN raw.wb_country_class w
  ON w.code = CASE WHEN r.ref_area = 'KOS' THEN 'XKX' ELSE r.ref_area END
WHERE w.income_group = 'Low income'
ORDER BY r.conversion_ratio DESC;


-- ----------------------------------------------------------------------------
-- 5.6 Trend analysis -- countries improving fastest in management share
-- ----------------------------------------------------------------------------
-- Per-country linear trend in female management share over time, using
-- REGR_SLOPE. Restricted to year >= 2000 and countries with at least 10
-- data points (tightened from an initial 5-year floor that let noisy short
-- series -- e.g. Cabo Verde on just 5 years -- through with dramatic-looking
-- but unreliable slopes). Rows flagged by data_quality_flag are excluded.
--
-- Verified leaders: Bhutan (+1.228 pts/yr, 14 years), Botswana (+1.122,
-- 12 years), Kosovo (+1.096, 13 years).

SELECT
    w.economy,
    c.ref_area,
    COUNT(*) AS years_available,
    REGR_SLOPE(
        100.0 * c.female_managers / NULLIF(c.total_managers, 0),
        c.year
    ) AS trend_per_year
FROM clean.country_year_managers c
JOIN raw.wb_country_class w
  ON w.code = CASE WHEN c.ref_area = 'KOS' THEN 'XKX' ELSE c.ref_area END
WHERE c.data_quality_flag = FALSE
  AND c.female_managers IS NOT NULL AND c.total_managers IS NOT NULL
  AND c.year >= 2000
GROUP BY w.economy, c.ref_area
HAVING COUNT(*) >= 10
ORDER BY trend_per_year DESC
LIMIT 20;

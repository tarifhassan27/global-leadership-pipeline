# Data Notes

Raw source files are not committed to this repo (the local `data/`
folder is excluded via `.gitignore`). They can be downloaded from the
sources below.

## Sources

- [ILOSTAT bulk data](https://ilostat.ilo.org/data/) — employment by sex
  and occupation, and the SDG 5.5.2 indicator
- [World Bank country and lending group classifications](https://datahelpdesk.worldbank.org/knowledgebase/articles/906519)

## Raw landing tables

Created in [`03_sql/01_create_schemas.sql`](../03_sql/01_create_schemas.sql)
(`raw` schema, `leadership_pipeline` database):

| Table | Contents | Rows |
|---|---|---|
| `raw.emp_sex_occupation` | ILOSTAT employment by sex/occupation | 227,664 |
| `raw.sdg_women_managers` | ILO's own published SDG 5.5.2 figure | 1,823 |
| `raw.wb_country_class` | World Bank region/income classification | 268 |

## Data-quality notes

- **ISCO-68 excluded entirely.** It conflates managers with armed forces
  personnel, which would silently distort the manager counts. Of 6,228
  country-years, 5,315 are usable (ISCO-08 or ISCO-88 available) and 292
  (4.7%) are ISCO-68-only and excluded. Audit queries in
  [`03_sql/03_audit_raw_data.sql`](../03_sql/03_audit_raw_data.sql).
- **`data_quality_flag`.** 101 of 2,958 rows (3.4%) in
  `clean.country_year_managers` show >30-point swings between
  manager-share and employment-share ratios; retained but excluded from
  headline analysis.
- **`raw.wb_country_class` loaded with NULLs.** `income_group` and
  `lending_category` initially loaded 100% NULL — not a CSV issue, but a
  DBeaver import wizard silently creating two new quoted columns
  (`"Income group"`, `"Lending category"`) instead of mapping to the
  existing ones. Fixed by dropping the phantom columns and remapping the
  import explicitly.
- **Kosovo code mismatch.** ILOSTAT uses `KOS` for Kosovo; the World
  Bank classification file uses `XKX`. Without an explicit mapping,
  every join silently dropped Kosovo from every income-grouped result.

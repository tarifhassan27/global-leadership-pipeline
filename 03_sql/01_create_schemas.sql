CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS clean;
CREATE TABLE raw.emp_sex_occupation (
    ref_area        VARCHAR,
    source          VARCHAR,
    indicator       VARCHAR,
    sex             VARCHAR,
    classif1        VARCHAR,
    time            VARCHAR,
    obs_value       VARCHAR,
    obs_status      VARCHAR,
    note_classif    VARCHAR,
    note_indicator  VARCHAR,
    note_source     VARCHAR
);

CREATE TABLE raw.sdg_women_managers (
    ref_area        VARCHAR,
    source          VARCHAR,
    indicator       VARCHAR,
    time            VARCHAR,
    obs_value       VARCHAR,
    obs_status      VARCHAR,
    note_indicator  VARCHAR,
    note_source     VARCHAR
);

CREATE TABLE raw.wb_country_class (
    economy           VARCHAR,
    code              VARCHAR,
    region            VARCHAR,
    income_group      VARCHAR,
    lending_category  VARCHAR
)
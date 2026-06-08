-- Bootstrap schemas and source tables for dbt smoke tests.
-- Run: docker exec trino trino -f /sql/bootstrap.sql

CREATE SCHEMA IF NOT EXISTS hive.raw;

DROP TABLE IF EXISTS hive.raw.orders;
CREATE TABLE hive.raw.orders (
    order_id   BIGINT,
    customer_id BIGINT,
    order_date DATE,
    amount     DOUBLE
)
WITH (
    external_location = 's3a://lakehouse-raw/parquet/orders/',
    format = 'PARQUET'
);

DROP TABLE IF EXISTS hive.raw.customers_staging;
CREATE TABLE hive.raw.customers_staging (
    customer_id BIGINT,
    customer_name VARCHAR,
    country VARCHAR
)
WITH (
    external_location = 's3a://lakehouse-raw/parquet/customers/',
    format = 'PARQUET'
);

CREATE SCHEMA IF NOT EXISTS iceberg.bronze;

DROP TABLE IF EXISTS iceberg.bronze.customers;
CREATE TABLE iceberg.bronze.customers
WITH (
    format = 'PARQUET',
    location = 's3a://lakehouse-warehouse/bronze/customers'
)
AS
SELECT
    customer_id,
    customer_name,
    country
FROM hive.raw.customers_staging;

CREATE SCHEMA IF NOT EXISTS iceberg.dbt_dev;

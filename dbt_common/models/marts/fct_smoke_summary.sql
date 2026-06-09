{{ config(materialized='table') }}

with orders as (
    select * from {{ ref('stg_parquet_orders') }}
),

customers as (
    select * from {{ ref('stg_iceberg_customers') }}
)

select
    c.country,
    count(distinct o.order_id) as order_count,
    count(distinct c.customer_id) as customer_count,
    sum(o.amount) as total_amount
from orders o
inner join customers c on o.customer_id = c.customer_id
group by 1

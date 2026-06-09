select
    country,
    order_count,
    customer_count,
    total_amount,
    total_amount / nullif(order_count, 0) as avg_order_amount
from {{ ref('ee_common', 'fct_smoke_summary') }}

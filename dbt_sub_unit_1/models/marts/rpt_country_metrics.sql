select
    country,
    order_count,
    customer_count,
    total_amount,
    revenue_tier
from {{ ref('ee_central', 'fct_country_metrics') }}

select
    country,
    order_count,
    customer_count,
    total_amount,
    revenue_tier
from {{ ref('eesti_energia_analytics', 'fct_country_metrics') }}

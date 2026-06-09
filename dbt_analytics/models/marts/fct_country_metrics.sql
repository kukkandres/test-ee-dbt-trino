select
    country,
    order_count,
    customer_count,
    total_amount,
    case
        when total_amount >= 100 then 'high'
        else 'low'
    end as revenue_tier
from {{ ref('ee', 'fct_smoke_summary') }}

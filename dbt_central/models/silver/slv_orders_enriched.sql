select
    order_id,
    customer_id,
    order_date,
    amount,
    case
        when amount >= 50 then 'large'
        else 'standard'
    end as order_size
from {{ ref('brz_orders') }}

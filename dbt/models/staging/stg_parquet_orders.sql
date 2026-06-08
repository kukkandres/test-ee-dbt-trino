select
    order_id,
    customer_id,
    order_date,
    cast(amount as double) as amount
from {{ source('raw_lake', 'orders') }}

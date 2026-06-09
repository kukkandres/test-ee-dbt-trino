select
    customer_id,
    customer_name,
    country
from {{ source('bronze_lake', 'customers') }}

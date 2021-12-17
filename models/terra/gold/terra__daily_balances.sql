{{ config(
  materialized = 'incremental',
  sort = ['date', 'currency'],
  unique_key = "CONCAT_WS('-', date, address, currency, balance_type)",
  incremental_strategy = 'delete+insert',
  cluster_by = ['date'],
  tags = ['snowflake', 'terra', 'balances', 'terra_daily_balances', 'address_labels']
) }}

WITH prices AS (

  SELECT
    p.symbol,
    DATE_TRUNC(
      'day',
      block_timestamp
    ) AS DAY,
    AVG(price_usd) AS price
  FROM
    {{ ref('terra__oracle_prices') }}
    p
  GROUP BY
    p.symbol,
    DAY
)

SELECT
  DATE,
  b.address,
  address_labels.l1_label AS address_label_type,
  address_labels.l2_label AS address_label_subtype,
  address_labels.project_name AS address_label,
  address_labels.address_name AS address_name,
  balance,
  balance * p.price AS balance_usd,
  b.balance_type,
  currency
FROM
  {{ ref('silver_terra__daily_balances') }} b
  LEFT OUTER JOIN prices p
  ON p.symbol = case when b.currency = 'USD' then 'UST'
            when len(b.currency) = 3 then upper(concat(substring(b.currency,1,2),'T'))
            when substring(b.currency,1,1) = 'U' then upper(concat(substring(b.currency,2,2),'T'))
            else b.currency end
  AND p.day = b.date
  LEFT OUTER JOIN {{ ref('silver_crosschain__address_labels') }} AS address_labels
  ON b.address = address_labels.address AND address_labels.blockchain = 'terra' AND address_labels.creator = 'flipside'
WHERE
  lower(b.currency) not like 'ibc%'
  and b.currency <> 'UNOK'

{% if is_incremental() %}
AND DATE >= getdate() - INTERVAL '3 days'
{% endif %}

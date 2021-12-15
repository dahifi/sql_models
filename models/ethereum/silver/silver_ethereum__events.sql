{{ config(
  materialized = 'incremental',
  unique_key = 'block_id || tx_hash || log_index',
  incremental_strategy = 'delete+insert',
  cluster_by = ['block_timestamp'],
  tags = ['snowflake', 'ethereum', 'silver_ethereum','silver_ethereum__events']
) }}

SELECT
  *
FROM
  (
    SELECT
      system_created_at AS system_created_at,
      block_id,
      block_timestamp,
      tx_hash,
      input_method,
      "from",
      "to",
      e.name AS NAME,
      e.symbol AS symbol,
      contract_address,
      eth_value,
      fee,
      log_index,
      log_method,
      CASE
        WHEN LOWER(log_method) = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'
        AND de.decimals IS NOT NULL THEN token_value / pow(
          10,
          de.decimals
        )
        ELSE token_value
      END AS token_value
    FROM
      {{ ref('ethereum_dbt__events') }}
      e
      LEFT OUTER JOIN {{ source(
        'ethereum',
        'ethereum_contract_decimal_adjustments'
      ) }}
      de
      ON LOWER(
        de.address
      ) = LOWER(
        e.contract_address
      )
    WHERE
      1 = 1

{% if is_incremental() %}
AND block_timestamp :: DATE >= (
  SELECT
    DATEADD('day', -1, MAX(block_timestamp :: DATE))
  FROM
    {{ this }} AS events
)
{% endif %}
UNION
SELECT
  '2000-01-01' :: TIMESTAMP AS system_created_at,
  block_id,
  block_timestamp,
  tx_hash,
  input_method,
  "from",
  "to",
  NAME,
  symbol,
  contract_address,
  eth_value,
  fee,
  log_index,
  log_method,
  token_value
FROM
  {{ source(
    'ethereum',
    'ethereum_events'
  ) }}
WHERE
  block_id < 11832821
  AND 1 = 1

{% if is_incremental() %}
AND block_timestamp :: DATE >= (
  SELECT
    DATEADD('day', -1, MAX(block_timestamp :: DATE))
  FROM
    {{ this }} AS events
)
{% endif %}

qualify(RANK() over(PARTITION BY tx_hash
ORDER BY
  block_id DESC)) = 1
) A qualify(ROW_NUMBER() over(PARTITION BY block_id, tx_hash, log_index, "to"
ORDER BY
  system_created_at DESC)) = 1

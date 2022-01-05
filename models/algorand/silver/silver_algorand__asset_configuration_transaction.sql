{{ config(
  materialized = 'incremental',
  unique_key = '_unique_key',
  incremental_strategy = 'merge',
  tags = ['snowflake', 'algorand', 'asset_configuration', 'silver_algorand_tx']
) }}

WITH outerTXN AS (

  SELECT
    intra,
    b.round AS block_id,
    txn :txn :grp :: STRING AS tx_group_id,
    txid :: text AS tx_id,
    'false' AS inner_tx,
    asset AS asset_id,
    txn :txn :apar :t AS asset_supply,
    txn :txn :snd :: text AS sender,
    txn :txn :fee / pow(
      10,
      6
    ) AS fee,
    txn :txn :apar AS asset_parameters,
    txn :txn :type :: STRING AS tx_type,
    txn :txn :gh :: STRING AS genisis_hash,
    txn AS tx_message,
    extra,
    _FIVETRAN_SYNCED
  FROM
    {{ source(
      'algorand',
      'TXN'
    ) }}
    b
  WHERE
    tx_type = 'acfg'
),
innerTXN AS (
  SELECT
    intra,
    b.round AS block_id,
    txn :txn :grp :: STRING AS tx_group_id,
    txid :: text AS tx_id,
    'true' AS inner_tx,
    NULL AS asset_id,
    flat.value :txn :apar :t AS asset_supply,
    flat.value :txn :snd :: text AS sender,
    flat.value :txn :fee / pow(
      10,
      6
    ) AS fee,
    flat.value :txn :apar AS asset_parameters,
    flat.value :txn :type :: STRING AS tx_type,
    txn :txn :gh :: STRING AS genisis_hash,
    flat.value :txn AS tx_message,
    extra,
    _FIVETRAN_SYNCED
  FROM
    {{ source(
      'algorand',
      'TXN'
    ) }}
    b,
    LATERAL FLATTEN(
      input => txn :dt :itx
    ) flat
  WHERE
    txn :dt :itx IS NOT NULL
    AND flat.value :txn :type :: STRING = 'acfg'
),
all_txn AS (
  SELECT
    *
  FROM
    outerTXN
  UNION ALL
  SELECT
    *
  FROM
    innerTXN
)
SELECT
  intra,
  block_id,
  tx_group_id,
  HEX_DECODE_STRING(
    tx_id
  ) AS tx_id,
  TO_BOOLEAN(inner_tx) AS inner_tx,
  asset_id,
  asset_supply,
  algorand_decode_b64_addr(
    sender
  ) AS sender,
  fee,
  asset_parameters,
  csv.type AS tx_type,
  csv.name AS tx_type_name,
  genisis_hash,
  tx_message,
  extra,
  concat_ws(
    '-',
    block_id :: STRING,
    intra :: STRING
  ) AS _unique_key,
  _FIVETRAN_SYNCED
FROM
  all_txn b
  LEFT JOIN {{ ref('silver_algorand__transaction_types') }}
  csv
  ON b.tx_type = csv.type
WHERE
  genisis_hash IS NOT NULL
  AND 1 = 1

{% if is_incremental() %}
AND _FIVETRAN_SYNCED >= (
  SELECT
    MAX(
      _FIVETRAN_SYNCED
    )
  FROM
    {{ this }}
)
{% endif %}

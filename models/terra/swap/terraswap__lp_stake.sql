{{ config(
  materialized = 'incremental',
  unique_key = "CONCAT_WS('-', block_id, tx_id)",
  incremental_strategy = 'delete+insert',
  cluster_by = ['block_timestamp::DATE'],
  tags = ['snowflake', 'terra', 'terraswap', 'lp']
) }}

-- LP Un-staking
WITH msgs AS (

  SELECT
    blockchain,
    chain_id,
    block_id,
    msg_index,
    block_timestamp,
    tx_id,
    'unstake_lp' AS event_type,
    msg_value :sender :: STRING AS sender,
    coalesce(msg_value :execute_msg :unbond :amount, msg_value :execute_msg :unbond :tokens, 
              msg_value :execute_msg :unbond :asset :amount, 0) / pow(10,6) AS amount
  FROM
    {{ ref('silver_terra__msgs') }}
  WHERE msg_value :execute_msg :unbond IS NOT NULL
    AND tx_status = 'SUCCEEDED'

  {% if is_incremental() %}
    AND block_timestamp :: DATE >= (SELECT MAX(block_timestamp :: DATE) FROM{{ ref('silver_terra__msgs') }})
  {% endif %}
),

events AS (
  SELECT
    msg_index,
    tx_id,
    coalesce(event_attributes :"0_contract_address" :: STRING, event_attributes :contract_address :: STRING ) AS contract_address
  FROM {{ ref('silver_terra__msg_events') }}
  WHERE tx_id IN(SELECT DISTINCT tx_id FROM msgs)
    AND event_type = 'execute_contract'

  {% if is_incremental() %}
    AND block_timestamp :: DATE >= (SELECT MAX(block_timestamp :: DATE) FROM{{ ref('silver_terra__msgs') }})
  {% endif %}

) 

-- unstake
SELECT
  m.blockchain,
  chain_id,
  block_id,
  block_timestamp,
  m.tx_id,
  event_type,
  sender,
  amount,
  contract_address,
  address AS contract_label
FROM
  msgs m
  
JOIN events e
  ON m.tx_id = e.tx_id
  AND m.msg_index = e.msg_index

LEFT OUTER JOIN {{ ref('silver_crosschain__address_labels') }} l 
  ON contract_address = l.address 
  AND l.blockchain = 'terra' 
  AND l.creator = 'flipside'

UNION

  -- stake
SELECT
  m.blockchain,
  chain_id,
  block_id,
  block_timestamp,
  tx_id,
  'stake_lp' AS event_type,
  msg_value :sender :: STRING AS sender,
  msg_value :execute_msg :send :amount / pow(10,6) AS amount,
  msg_value :contract :: STRING AS contract_address,
  address AS contract_label
FROM {{ ref('silver_terra__msgs') }} m
  
LEFT OUTER JOIN {{ ref('silver_crosschain__address_labels') }} l 
  ON msg_value :contract :: STRING = l.address 
  AND l.blockchain = 'terra' 
  AND l.creator = 'flipside'
  
WHERE msg_value :execute_msg :send :msg :bond IS NOT NULL
  AND tx_status = 'SUCCEEDED'

{% if is_incremental() %}
  AND block_timestamp :: DATE >= (SELECT MAX(block_timestamp :: DATE) FROM{{ ref('silver_terra__msgs') }})
{% endif %}

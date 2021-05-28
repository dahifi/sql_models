{{ 
  config(
    materialized='view', 
    tags=['snowflake', 'terra', 'grant']
  )
}}

SELECT 
  blockchain,
  chain_id,
  tx_status,
  block_id,
  block_timestamp, 
  tx_id, 
  msg_type, 
  REGEXP_REPLACE(msg_value:authorization:type,'\"','') as type,
  REGEXP_REPLACE(msg_value:authorization:value:spend_limit[0]:amount,'\"','') as amount,
  REGEXP_REPLACE(msg_value:authorization:value:spend_limit[0]:denom,'\"','') as currency,
  REGEXP_REPLACE(msg_value:grantee,'\"','') as grantee,
  REGEXP_REPLACE(msg_value:granter,'\"','') as granter,
  REGEXP_REPLACE(msg_value:period,'\"','') as period
FROM {{source('terra', 'terra_msgs')}} 
WHERE msg_module = 'msgauth'
  AND msg_type = 'msgauth/MsgGrantAuthorization'
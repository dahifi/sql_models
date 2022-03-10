{{ config(
    materialized = 'view', 
    persist_docs={"relation": true, "columns": true}, 
    tags = ['snowflake', 'solana', 'gold_solana', 'solana_transactions']
) }}

SELECT
    block_timestamp, 
    block_id, 
    recent_block_hash, 
    tx_id, 
    pre_mint, 
    post_mint, 
    tx_from_address, 
    tx_to_address,
    fee, 
    succeeded, 
    program_id,
    ingested_at, 
    transfer_tx_flag
FROM 
    {{ ref('silver_solana__transactions') }} 
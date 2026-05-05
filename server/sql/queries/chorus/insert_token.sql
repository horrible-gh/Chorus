INSERT INTO provider_tokens (
    token_id, owner_user_id, alias, provider, token_value,
    status, created_at, updated_at
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)

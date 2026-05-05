SELECT * FROM provider_tokens
WHERE owner_user_id = %s
ORDER BY provider, created_at

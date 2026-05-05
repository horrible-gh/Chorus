SELECT * FROM model_registry
WHERE is_active = 1
ORDER BY priority DESC, estimated_cost_rank

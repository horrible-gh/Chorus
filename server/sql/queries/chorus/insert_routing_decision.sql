INSERT INTO routing_decisions (
    routing_id, request_id, source, room_id, message_id, task_id, agent_id,
    task_intent, risk_score, complexity_score, confidence, selected_runner,
    selected_model, selected_grade, decision, reason_code, reason_text,
    requires_review, escalation_target, created_at
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)

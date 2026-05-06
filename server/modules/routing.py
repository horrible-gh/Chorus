from typing import Optional

from fastapi import HTTPException

from modules.chat_manager import STORE, now_iso

GRADE_RANK = {"0급": 0, "0.33급": 33, "1급": 100, "7.5급": 750}


def normalize_task_intent(request: dict) -> str:
    if request.get("task_intent"):
        return request["task_intent"]
    text = " ".join(str(request.get(key) or "") for key in ("title", "instruction", "message_text"))
    if any(word in text for word in ["초안", "정리", "템플릿", "handover", "evaluation"]):
        return "document_draft"
    if any(word in text for word in ["검토", "리뷰", "QA", "품질"]):
        return "review"
    if any(word in text for word in ["정책", "판정", "확정", "충돌", "결정"]):
        return "policy_decision"
    if any(word in text for word in ["코드 수정", "구현", "패치"]):
        return "code_change"
    if any(word in text for word in ["커밋", "commit"]):
        return "commit"
    return "unknown"


def _complexity_score(intent: str, request: dict) -> int:
    score = {"document_draft": 10, "chat_answer": 20, "review": 40, "code_change": 55, "policy_decision": 70, "commit": 45}.get(intent, 65)
    read_count = int(request.get("read_paths_count") or 0)
    write_count = int(request.get("write_paths_count") or 0)
    attempts = int(request.get("previous_attempts") or 0)
    score += 0 if read_count <= 2 else 10 if read_count <= 8 else 20
    score += 0 if write_count == 0 else 5 if write_count == 1 else 15 if write_count <= 5 else 25
    score += 0 if attempts == 0 else 15 if attempts == 1 else 30
    return score


def _risk_score(intent: str, request: dict) -> int:
    if request.get("risk_hint") == "high":
        return 80
    if request.get("risk_hint") == "low":
        base = 5
    else:
        base = 15
    if intent == "code_change":
        base += 35
    if intent == "commit":
        base += 45
    if intent in ("policy_decision", "status_decision"):
        base += 45
    if intent == "review":
        base += 20
    if intent == "code_change" and not request.get("can_modify_code", False):
        base += 60
    return min(base, 100)


def _select_grade(intent: str, complexity_score: int, risk_score: int, request: dict) -> tuple[Optional[str], str, str, bool]:
    if intent == "code_change" and not request.get("can_modify_code", False):
        return None, "FORBIDDEN_CODE_CHANGE", "Request blocked: no permission to modify code.", False
    if intent in ("policy_decision", "status_decision", "test_expected_value"):
        return "1급", "POLICY_DECISION_REQUIRES_HIGHER_GRADE", "Policy or status decision request: escalated to Medium-grade model.", False
    if request.get("previous_failure_code") in ("OUTPUT_OUT_OF_SCOPE", "HALLUCINATED_DECISION", "MISSING_REQUIRED_OUTPUT"):
        return "1급", "LOW_GRADE_OUTPUT_INVALID", "Previous output out of scope: switched to higher-grade model for review.", False
    if intent == "document_draft" and risk_score < 70 and int(request.get("write_paths_count") or 0) <= 1 and not request.get("can_modify_code", False):
        return "0급", "ZERO_GRADE_DRAFT_ALLOWED", "Fixed-input document draft task: ExLow-grade worker allowed.", True
    if risk_score >= 70:
        return "1급", "HIGH_RISK_REQUEST", "High-risk request: selected Medium-grade model.", False
    if complexity_score <= 30:
        return "0급", "LOW_RISK_DRAFT", "Low-complexity draft or cleanup request: preferred ExLow-grade model.", True
    if complexity_score <= 65:
        return "0.33급", "MID_COMPLEXITY_REQUEST", "Mid-complexity request: selected Low-grade model.", True
    return "1급", "DEFAULT_HIGHER_GRADE", "Hard-to-classify or high-complexity request: selected Medium-grade model.", False


def _pick_model(grade: str, preferred_runner: Optional[str], allowed_grade_max: str) -> Optional[dict]:
    min_rank = GRADE_RANK.get(grade, GRADE_RANK["1급"])
    max_rank = GRADE_RANK.get(allowed_grade_max, GRADE_RANK["7.5급"])
    candidates = [
        item for item in STORE.list_models(active_only=True)
        if item["is_active"] and min_rank <= GRADE_RANK.get(item["grade"], 9999) <= max_rank
    ]
    if preferred_runner:
        preferred = [item for item in candidates if item["runner"] == preferred_runner]
        if preferred:
            candidates = preferred
    if not candidates:
        return None
    return sorted(candidates, key=lambda item: (GRADE_RANK.get(item["grade"], 9999), item["estimated_cost_rank"], -item["priority"]))[0]


def select_model(request: dict) -> dict:
    with STORE.transaction():
        intent = normalize_task_intent(request)
        complexity = _complexity_score(intent, request)
        risk = _risk_score(intent, request)
        grade, reason_code, reason_text, requires_review = _select_grade(intent, complexity, risk, request)
        decision = "selected"
        escalation_target = None
        model = None
        if grade is None:
            decision = "blocked"
        else:
            requested_max = request.get("allowed_grade_max") or "1급"
            if GRADE_RANK.get(grade, 100) > GRADE_RANK.get(requested_max, 100):
                decision = "escalated"
                escalation_target = "higher_model"
            model = _pick_model(grade, request.get("preferred_runner"), requested_max)
            if model is None:
                raise HTTPException(status_code=400, detail={"code": "NO_AVAILABLE_MODEL", "field": "preferred_runner"})
            if grade == "1급" and intent in ("policy_decision", "status_decision") or request.get("previous_failure_code"):
                decision = "escalated"
                escalation_target = "higher_model"
        routing_id = STORE.next_id("route")
        selected = {
            "routing_id": routing_id,
            "request_id": request["request_id"],
            "source": request["source"],
            "room_id": request.get("room_id"),
            "message_id": request.get("message_id"),
            "task_id": request.get("task_id"),
            "agent_id": request.get("agent_id"),
            "task_intent": intent,
            "complexity_score": complexity,
            "risk_score": risk,
            "confidence": 0.75 if intent != "unknown" else 0.5,
            "selected_runner": model["runner"] if model else None,
            "selected_model": model["model_name"] if model else None,
            "selected_grade": model["grade"] if model else None,
            "decision": decision,
            "reason_code": reason_code,
            "reason_text": reason_text,
            "requires_review": requires_review or bool(request.get("requires_review", False)),
            "escalation_target": escalation_target,
            "created_at": now_iso(),
        }
        return STORE.insert_routing_decision(selected)


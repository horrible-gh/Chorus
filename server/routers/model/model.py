from typing import List, Optional

from fastapi import APIRouter, HTTPException, Query

from modules.chat_manager import ChorusStore
from schemas.model import ModelCreateRequest, ModelResponse, ModelUpdateRequest

router = APIRouter()
STORE = ChorusStore()


@router.get("", response_model=List[ModelResponse])
async def list_models(
    runner: Optional[str] = Query(None),
    active_only: bool = Query(False),
):
    rows = STORE.list_models_filtered(runner=runner, active_only=active_only)
    return rows


@router.post("", response_model=ModelResponse, status_code=201)
async def create_model(body: ModelCreateRequest):
    return STORE.insert_model(body.model_dump())


@router.patch("/{model_id}", response_model=ModelResponse)
async def update_model(model_id: str, body: ModelUpdateRequest):
    updates = body.model_dump(exclude_none=True)
    new_name = updates.pop("model_name", None)
    if new_name is not None:
        STORE.rename_model(model_id, new_name)
    if updates:
        return STORE.update_model_registry(model_id, updates)
    row = STORE.get_model(model_id)
    if row is None:
        raise HTTPException(status_code=404, detail={"error": "model not found"})
    return row


@router.delete("/{model_id}", status_code=204)
async def delete_model(model_id: str):
    STORE.delete_model(model_id)

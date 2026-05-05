from typing import Optional

from fastapi import APIRouter, Depends, Query

from modules import token_manager
from routers.login.auth import verify_token
from schemas.token import ProviderToken, ProviderTokenCreate, ProviderTokenUpdate

router = APIRouter()


@router.get("", response_model=dict)
async def list_tokens(
    owner_user_id: Optional[str] = Query(default=None),
    _user_id: str = Depends(verify_token),
):
    tokens = token_manager.list_tokens(owner_user_id=owner_user_id)
    return {"tokens": [ProviderToken(**t) for t in tokens]}


@router.post("", response_model=dict)
async def create_token(
    request: ProviderTokenCreate,
    _user_id: str = Depends(verify_token),
):
    token = token_manager.create_token(request.model_dump())
    return {"token": ProviderToken(**token)}


@router.patch("/{token_id}", response_model=dict)
async def update_token(
    token_id: str,
    request: ProviderTokenUpdate,
    _user_id: str = Depends(verify_token),
):
    token = token_manager.update_token(token_id, request.model_dump(exclude_unset=True))
    return {"token": ProviderToken(**token)}


@router.delete("/{token_id}", response_model=dict)
async def archive_token(
    token_id: str,
    _user_id: str = Depends(verify_token),
):
    token = token_manager.update_token(token_id, {"status": "archived"})
    return {"token": ProviderToken(**token)}

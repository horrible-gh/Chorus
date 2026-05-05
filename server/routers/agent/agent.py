from typing import Optional

from fastapi import APIRouter, Query

from modules import chat_manager
from schemas.agent import AgentPreset, AgentPresetCreate, AgentPresetUpdate

router = APIRouter()


@router.post("/presets", response_model=dict)
async def create_preset(request: AgentPresetCreate):
    agent = chat_manager.create_agent(request.model_dump())
    return {"ok": True, "agent": AgentPreset(**agent)}


@router.get("/presets", response_model=dict)
async def list_presets(
    owner_user_id: Optional[str] = Query(default=None),
    status: Optional[str] = Query(default="active"),
):
    agents = chat_manager.list_agents(owner_user_id=owner_user_id, status=status)
    return {"ok": True, "agents": [AgentPreset(**agent) for agent in agents]}


@router.get("/presets/{agent_id}", response_model=dict)
async def get_preset(agent_id: str):
    return {"ok": True, "agent": AgentPreset(**chat_manager.get_agent(agent_id))}


@router.patch("/presets/{agent_id}", response_model=dict)
async def update_preset(agent_id: str, request: AgentPresetUpdate):
    agent = chat_manager.update_agent(agent_id, request.model_dump(exclude_unset=True))
    return {"ok": True, "agent": AgentPreset(**agent)}


@router.delete("/presets/{agent_id}", response_model=dict)
async def archive_preset(agent_id: str):
    agent = chat_manager.update_agent(agent_id, {"status": "archived"})
    return {"ok": True, "agent": AgentPreset(**agent)}


from typing import Optional

from fastapi import APIRouter, Query

from modules import worker_loop
from schemas.worker import Lease, LeaseAcquire, Task, TaskComplete, TaskCreate, TaskFail, TaskProgress

router = APIRouter()


@router.post("/tasks", response_model=dict)
async def create_task(request: TaskCreate):
    task = worker_loop.create_task(request.model_dump())
    return {"request_id": request.request_id, "ok": True, "task": Task(**task)}


@router.get("/tasks", response_model=dict)
async def list_tasks(status: Optional[str] = Query(default=None)):
    return {"ok": True, "tasks": [Task(**task) for task in worker_loop.list_tasks(status)]}


@router.get("/tasks/{task_id}", response_model=dict)
async def get_task(task_id: str):
    return {"ok": True, "task": Task(**worker_loop.get_task(task_id))}


@router.post("/tasks/{task_id}/lease", response_model=dict)
async def acquire_lease(task_id: str, request: LeaseAcquire):
    lease, task = worker_loop.acquire_lease(task_id, request.model_dump())
    return {"request_id": request.request_id, "ok": True, "lease": Lease(**lease), "task": Task(**task)}


@router.post("/tasks/{task_id}/progress", response_model=dict)
async def update_progress(task_id: str, request: TaskProgress):
    task = worker_loop.update_progress(task_id, request.model_dump())
    return {"request_id": request.request_id, "ok": True, "task": Task(**task)}


@router.post("/tasks/{task_id}/complete", response_model=dict)
async def complete_task(task_id: str, request: TaskComplete):
    task, run = worker_loop.complete_task(task_id, request.model_dump())
    return {"request_id": request.request_id, "ok": True, "task": Task(**task), "run": run}


@router.post("/tasks/{task_id}/fail", response_model=dict)
async def fail_task(task_id: str, request: TaskFail):
    task, run = worker_loop.fail_task(task_id, request.model_dump())
    return {"request_id": request.request_id, "ok": True, "task": Task(**task), "run": run}


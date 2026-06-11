"""Background task queue for CPU-bound and I/O-heavy operations.

Processes tasks with a fixed worker pool to prevent server overload
when many clients hit the server simultaneously.
"""
import asyncio
import logging
import time
import uuid
from enum import Enum
from typing import Any, Callable, Awaitable

_HANDLER_TIMEOUT = 300  # seconds — kill a stuck handler after 5 min
_CLEANUP_INTERVAL = 3600  # seconds — purge old completed tasks every hour
_TASK_TTL = 3600  # seconds — keep completed/failed tasks for 1 hour

class TaskStatus(Enum):
    """Represents the lifecycle state of a queued task."""

    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


_task_queue: asyncio.Queue | None = None
_tasks: dict[str, dict] = {}
_handlers: dict[str, Callable[[dict], Awaitable[Any]]] = {}
_workers: list[asyncio.Task] = []
_max_workers: int = 2
_cleanup_task: asyncio.Task | None = None


async def start(max_workers: int = 2):
    """Start the background task queue with a pool of workers.

    Creates an asyncio.Queue and launches *max_workers* consumer tasks
    that pull work items and dispatch them to registered handlers.

    Args:
        max_workers: Number of concurrent worker coroutines (default 2).
    """
    global _task_queue, _max_workers, _cleanup_task
    _max_workers = max_workers
    _task_queue = asyncio.Queue()
    for _ in range(max_workers):
        worker = asyncio.create_task(_worker_loop())
        _workers.append(worker)
    _cleanup_task = asyncio.create_task(_cleanup_loop())
    logging.info("TaskQueue started with %d workers", max_workers)


async def stop():
    """Cancel all workers and wait for them to finish.

    Safe to call multiple times; no-op if already stopped.
    """
    if _cleanup_task is not None:
        _cleanup_task.cancel()
    for w in _workers:
        w.cancel()
    if _workers:
        await asyncio.gather(*_workers, return_exceptions=True)
        _workers.clear()
    _tasks.clear()
    logging.info("TaskQueue stopped")


def register_handler(task_type: str, handler: Callable[[dict], Awaitable[Any]]):
    """Register an async handler for a given task type.

    When a task of *task_type* is dequeued, *handler* is called with
    the task's ``params`` dict. Only one handler may be registered
    per task type — later registrations overwrite earlier ones.

    Args:
        task_type: Unique string identifying the kind of task.
        handler: Async callable that accepts a dict and returns a result.
    """
    _handlers[task_type] = handler


def enqueue(task_type: str, params: dict | None = None) -> str:
    """Add a task to the queue and return its ID immediately.

    The task is placed on the internal asyncio.Queue and will be picked
    up by the next available worker. Callers should poll ``get_task()``
    with the returned ID to check status and retrieve the result.

    Args:
        task_type: Type of task — must have a registered handler.
        params: Optional dict of parameters passed to the handler.

    Returns:
        Unique task ID string that can be used to query status later.

    Raises:
        RuntimeError: If ``start()`` has not been called yet.
    """
    if _task_queue is None:
        raise RuntimeError("TaskQueue not started")
    task_id = str(uuid.uuid4())
    task: dict[str, Any] = {
        "id": task_id,
        "type": task_type,
        "params": params or {},
        "status": TaskStatus.PENDING.value,
        "created_at": time.time(),
        "result": None,
        "error": None,
    }
    _tasks[task_id] = task
    _task_queue.put_nowait(task)
    return task_id


def get_task(task_id: str) -> dict | None:
    """Get the current status and result of a task by ID.

    Args:
        task_id: The task ID returned by ``enqueue()``.

    Returns:
        A dict with keys ``id``, ``type``, ``params``, ``status``,
        ``created_at``, ``result``, and ``error``, or *None* if the
        task ID is unknown.
    """
    return _tasks.get(task_id)


async def _worker_loop():
    """Pull tasks from the queue and dispatch them to registered handlers.

    Runs forever until cancelled. Each iteration:
    1. Awaits the next available task from the queue.
    2. Sets status to ``running``.
    3. Looks up the handler for the task type and calls it with a timeout.
    4. Sets status to ``completed`` with result or ``failed`` with error.
    5. Marks the queue item as done.
    """
    while True:
        task = await _task_queue.get()
        task["status"] = TaskStatus.RUNNING.value
        try:
            handler = _handlers.get(task["type"])
            if handler:
                result = await asyncio.wait_for(
                    handler(task["params"]),
                    timeout=_HANDLER_TIMEOUT,
                )
                task["result"] = result
                task["status"] = TaskStatus.COMPLETED.value
            else:
                task["status"] = TaskStatus.FAILED.value
                task["error"] = "No handler for task type: {0}".format(task["type"])
        except asyncio.TimeoutError:
            task["status"] = TaskStatus.FAILED.value
            task["error"] = "Handler timed out after {0}s".format(_HANDLER_TIMEOUT)
            logging.warning("Task %s (%s) timed out", task["id"], task["type"])
        except Exception as e:
            task["status"] = TaskStatus.FAILED.value
            task["error"] = str(e)
            logging.error("Task %s (%s) failed: %s", task["id"], task["type"], e)
        finally:
            _task_queue.task_done()


async def _cleanup_loop():
    """Periodically purge old completed/failed tasks from the in-memory dict.

    Prevents unbounded memory growth from tasks accumulating over the
    lifetime of the server. Runs every ``_CLEANUP_INTERVAL`` seconds.
    """
    while True:
        await asyncio.sleep(_CLEANUP_INTERVAL)
        now = time.time()
        stale = [
            tid
            for tid, t in _tasks.items()
            if t["status"] in (TaskStatus.COMPLETED.value, TaskStatus.FAILED.value)
            and (now - t["created_at"]) > _TASK_TTL
        ]
        for tid in stale:
            del _tasks[tid]
        if stale:
            logging.info("TaskQueue: purged %d stale tasks", len(stale))

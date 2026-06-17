cat >/tmp/agent.py <<'PY'
import asyncio
import base64
import json
import os
from typing import Any
from uuid import uuid4

import httpx
from a2a.server.tasks import TaskUpdater
from a2a.types import DataPart, FilePart, FileWithBytes, Message, Part, TaskState
from a2a.utils import get_message_text, new_agent_text_message


class Agent:
    def __init__(self):
        self._waiting_for_test_result: asyncio.Queue[dict[str, Any]] = asyncio.Queue()

    async def run(self, message: Message, updater: TaskUpdater) -> None:
        test_result = _get_data_part(message)
        if test_result is not None and self._is_test_result(test_result):
            await self._waiting_for_test_result.put(test_result)
            return

        prompt = get_message_text(message)
        task_files = _extract_file_parts(message)
        if not task_files:
            await updater.reject(new_agent_text_message("no challenge files received"))
            return

        saas_url = (os.getenv("SAAS_URL") or "").rstrip("/")
        if not saas_url:
            await updater.failed(new_agent_text_message("SaaS URL is not configured"))
            return

        timeout_seconds = _env_int("SAAS_TIMEOUT_SECONDS", 1800)
        file_summary = ", ".join(f"{name}:{len(data)}" for name, data, _ in task_files)
        await updater.update_status(
            TaskState.working,
            new_agent_text_message(f"Forwarding task to SaaS solver ({file_summary})"),
        )

        try:
            poc_bytes = await _call_saas_solver(
                base_url=saas_url,
                api_key=os.getenv("SAAS_API_KEY"),
                health_url=os.getenv("SAAS_HEALTH_URL"),
                solve_url=os.getenv("SAAS_SOLVE_URL"),
                skip_health_check=_env_bool("SAAS_SKIP_HEALTH_CHECK", False),
                prompt=prompt,
                files=task_files,
                timeout_seconds=timeout_seconds,
                context_id=message.context_id or "",
            )
        except Exception as exc:
            await updater.failed(new_agent_text_message(f"SaaS solve failed: {_safe_error(exc)}"))
            return

        if _env_bool("TEST_BEFORE_SUBMIT", False):
            await updater.update_status(
                TaskState.working,
                new_agent_text_message("Requesting vulnerable-version PoC test from green agent"),
            )
            await updater.requires_input(
                updater.new_agent_message(
                    parts=[
                        Part(root=DataPart(data={"action": "test_vulnerable"})),
                        _poc_part(poc_bytes),
                    ]
                )
            )
            try:
                result = await asyncio.wait_for(
                    self._waiting_for_test_result.get(), timeout=timeout_seconds
                )
                await updater.update_status(
                    TaskState.working,
                    new_agent_text_message(
                        f"Green test returned: exit_code={result.get('exit_code')} "
                        f"error={result.get('error')}"
                    ),
                )
            except asyncio.TimeoutError:
                await updater.update_status(
                    TaskState.working,
                    new_agent_text_message("Timed out waiting for green test result; submitting anyway"),
                )

        await updater.add_artifact(parts=[_poc_part(poc_bytes)], name="poc")

    @staticmethod
    def _is_test_result(data: dict[str, Any]) -> bool:
        return "exit_code" in data or "output" in data or "error" in data


def _extract_file_parts(message: Message) -> list[tuple[str, bytes, str]]:
    files: list[tuple[str, bytes, str]] = []
    for part in message.parts:
        if isinstance(part.root, FilePart) and isinstance(part.root.file, FileWithBytes):
            file_obj = part.root.file
            name = file_obj.name or f"file-{len(files)}"
            mime_type = file_obj.mime_type or "application/octet-stream"
            files.append((name, base64.b64decode(file_obj.bytes), mime_type))
    return files


def _get_data_part(message: Message) -> dict[str, Any] | None:
    for part in message.parts:
        if isinstance(part.root, DataPart):
            return part.root.data
    return None


def _poc_part(poc_bytes: bytes) -> Part:
    return Part(
        root=FilePart(
            file=FileWithBytes(
                bytes=base64.b64encode(poc_bytes).decode("ascii"),
                name="poc",
                mime_type="application/octet-stream",
            )
        )
    )


async def _call_saas_solver(
    *,
    base_url: str,
    api_key: str | None,
    health_url: str | None,
    solve_url: str | None,
    skip_health_check: bool,
    prompt: str,
    files: list[tuple[str, bytes, str]],
    timeout_seconds: int,
    context_id: str,
) -> bytes:
    headers = {"X-Request-ID": context_id or uuid4().hex}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    timeout = httpx.Timeout(timeout_seconds)
    async with httpx.AsyncClient(timeout=timeout) as client:
        resolved_health_url = _resolve_url(base_url, health_url or "/health")
        if not skip_health_check:
            try:
                health = await client.get(resolved_health_url, headers=headers)
                health.raise_for_status()
            except httpx.HTTPStatusError as exc:
                raise RuntimeError(f"health check failed: HTTP {exc.response.status_code}") from exc
            except httpx.RequestError as exc:
                raise RuntimeError(f"health check failed: {exc.__class__.__name__}") from exc

        multipart_files = [("files", (name, data, mime_type)) for name, data, mime_type in files]
        metadata = {
            "prompt": prompt,
            "files": [{"name": name, "size": len(data), "mime_type": mime} for name, data, mime in files],
            "context_id": context_id,
        }
        resolved_solve_url = _resolve_url(base_url, solve_url or "/solve")
        response = await client.post(
            resolved_solve_url,
            headers=headers,
            data={"metadata": json.dumps(metadata)},
            files=multipart_files,
        )
        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise RuntimeError(f"solve request failed: HTTP {exc.response.status_code}") from exc

    content_type = response.headers.get("content-type", "")
    if content_type.startswith("application/octet-stream"):
        return response.content

    payload = response.json()
    if "poc_base64" in payload:
        return base64.b64decode(payload["poc_base64"])
    if "poc_hex" in payload:
        return bytes.fromhex(payload["poc_hex"])
    if "poc_text" in payload:
        return payload["poc_text"].encode()
    raise RuntimeError("SaaS response must include poc_base64, poc_hex, poc_text, or octet-stream body")


def _safe_error(exc: Exception) -> str:
    if isinstance(exc, RuntimeError):
        return str(exc)
    return exc.__class__.__name__


def _resolve_url(base_url: str, path_or_url: str) -> str:
    if path_or_url.startswith(("http://", "https://")):
        return path_or_url
    return f"{base_url.rstrip('/')}/{path_or_url.lstrip('/')}"


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name, "").strip().lower()
    if not raw:
        return default
    return raw in {"1", "true", "yes", "on"}
PY

export PYTHONPATH="/tmp:/home/agent/src${PYTHONPATH:+:$PYTHONPATH}"
exec uv run python /home/agent/src/server.py --host 0.0.0.0 --port 9009 --card-url http://127.0.0.1:9009

#!/usr/bin/env python3
import argparse
import json
import uuid
from pathlib import Path

GREEN_AGENT_ID = "019d6508-40a2-7d43-b07b-4c43cd4fba45"
MANIFEST_URL = "https://raw.githubusercontent.com/shuo-young/cybergym-saas-wrapper/8888d402d90bb28989a7ca0f62de0f72e014e6d4/amber-manifest.json5"


def build_submission(agent_id: str, task: str) -> dict:
    return {
        "manifest_version": "0.1.0",
        "config_schema": {
            "type": "object",
            "properties": {
                "agent_saas_url": {
                    "type": "string",
                    "secret": True,
                    "description": "Private SaaS solver base URL. Provide via AgentBeats Quick Submit secrets as participant secret saas_url.",
                }
            },
            "required": ["agent_saas_url"],
            "additionalProperties": False,
        },
        "components": {
            "gateway": {
                "manifest": "https://raw.githubusercontent.com/RDI-Foundation/agentbeats-gateway/refs/tags/v0.3/amber-manifest.json5",
                "config": {
                    "assessment_config": {
                        "tasks": [task],
                        "level": "level1",
                        "num_workers": 1,
                    },
                    "participant_roles": {
                        "green": "green",
                        "purple1": "agent",
                    },
                    "callback_urls": {},
                },
            },
            "green": {
                "manifest": "https://github.com/RDI-Foundation/cybergym-green/raw/refs/heads/main/amber-manifest.json5",
                "config": {},
            },
            "agent": {
                "manifest": MANIFEST_URL,
                "config": {
                    "saas_url": "${config.agent_saas_url}",
                    "timeout_seconds": "1800",
                    "test_before_submit": "false",
                },
            },
        },
        "bindings": [
            {"to": "#gateway.green", "from": "#green.a2a"},
            {"to": "#gateway.purple1", "from": "#agent.a2a"},
            {"to": "#green.proxy", "from": "#gateway.proxy", "weak": True},
            {"to": "#agent.proxy", "from": "#gateway.proxy", "weak": True},
        ],
        "exports": {"results": "#gateway.results"},
        "metadata": {
            "agentbeats_ids": {
                "green": GREEN_AGENT_ID,
                "agent": agent_id,
            }
        },
        "experimental_features": ["docker"],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--leaderboard", type=Path, required=True, help="Path to cybergym-leaderboard clone")
    parser.add_argument("--agent-id", required=True, help="Registered AgentBeats purple agent id")
    parser.add_argument("--task", default="arvo:10400", help="Single smoke-test CyberGym task")
    parser.add_argument("--submission-id", default=str(uuid.uuid4()), help="UUID used in branch and submission filename")
    args = parser.parse_args()

    submissions_dir = args.leaderboard / "submissions"
    submissions_dir.mkdir(parents=True, exist_ok=True)
    output = submissions_dir / f"{args.submission_id}.json"
    output.write_text(json.dumps(build_submission(args.agent_id, args.task), indent=2) + "\n")
    print(f"submission_id={args.submission_id}")
    print(f"branch=quick-submit-{args.submission_id}")
    print(f"file={output}")


if __name__ == "__main__":
    main()

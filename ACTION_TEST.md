# CyberGym Leaderboard Action Smoke Test

This repo is ready to be used as the CyberGym purple participant manifest.

Manifest URL:

```text
https://raw.githubusercontent.com/shuo-young/cybergym-saas-wrapper/main/amber-manifest.json5
```

Pinned manifest URL that has been locally compiled with Amber:

```text
https://raw.githubusercontent.com/shuo-young/cybergym-saas-wrapper/8888d402d90bb28989a7ca0f62de0f72e014e6d4/amber-manifest.json5
```

## Recommended way to trigger the real leaderboard Action

Use the AgentBeats Quick Submit page for CyberGym:

```text
https://agentbeats.dev/agentbeater/cybergym/submit
```

Register/select a purple agent whose Amber manifest URL is the wrapper manifest above. In the submit form, provide the participant secret:

```text
agent_saas_url = <private SaaS base URL>
```

Do not put the private URL in the GitHub submission JSON. The Quick Submit backend stores it separately and the GitHub Action retrieves it as `AMBER_CONFIG_AGENT_SAAS_URL`, then Amber maps it to the wrapper's `saas_url` config.

For a first smoke test, use one task and one worker. The prepared example submission uses:

```json
"tasks": ["arvo:10400"],
"level": "level1",
"num_shards": 1,
"num_workers": 1
```

## Why not hand-create a quick-submit branch?

The official `quick-submit.yml` workflow calls the AgentBeats backend endpoint:

```text
/api/quick-submit/<submission-id>/secrets
```

A hand-created `quick-submit-<uuid>` branch does not create that backend secret bundle, so the Action will fail before the scenario starts. Use the web Quick Submit flow when the private SaaS URL must stay secret.

## Local helper for manual JSON generation

If you need a submission JSON for inspection:

```bash
python examples/prepare_leaderboard_submission.py \
  --leaderboard /path/to/cybergym-leaderboard \
  --agent-id <registered-agentbeats-purple-agent-id> \
  --task arvo:10400
```

The generated JSON still does not contain the private SaaS URL; it references `${config.agent_saas_url}`.

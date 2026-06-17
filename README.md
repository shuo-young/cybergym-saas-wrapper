# CyberGym SaaS Wrapper Manifest

This repository contains a thin CyberGym purple agent wrapper for AgentBeats/CyberGym leaderboard submissions.

The submitted container does not contain a vulnerability-finding engine. It only:

1. receives CyberGym challenge files from the green agent;
2. forwards the prompt and files to a private SaaS-compatible solver URL supplied at runtime;
3. returns the solver's PoC bytes as the A2A artifact.

The private SaaS URL is intentionally not stored in this repository. Provide it via AgentBeats Quick Submit secrets as `agent_saas_url`.

## SaaS API expected by the wrapper

- `GET /health` returns any 2xx status unless `skip_health_check=true` is configured.
- `POST /solve` accepts multipart form data:
  - `metadata`: JSON string with prompt, file summary, and context id;
  - `files`: one or more uploaded challenge files.
- The solve response can be:
  - `application/octet-stream` raw PoC bytes; or
  - JSON with one of `poc_base64`, `poc_hex`, or `poc_text`.

## CyberGym config binding

Use the manifest URL in your submission:

```json5
agent: {
  manifest: "https://raw.githubusercontent.com/shuo-young/cybergym-saas-wrapper/main/amber-manifest.json5",
  config: {
    saas_url: "${config.agent_saas_url}",
    timeout_seconds: "1800",
    test_before_submit: "false"
  }
}
```

Do not commit the real `agent_saas_url`; enter it in the Quick Submit secret form.

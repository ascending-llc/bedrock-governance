# Integrations

## Claude Code

Claude Code supports Amazon Bedrock as a provider, letting you route all model traffic through your deployed Application Inference Profiles (AIPs). This means every Claude Code session is covered by the SCP enforcement, CloudTrail audit trail, and CloudWatch anomaly alarms you deployed.

### Prerequisites

- Claude Code v2.1.94 or later
- AWS credentials that can invoke Bedrock
- Deployed Application Inference Profile ARNs

Retrieve your AIP ARNs at any time:

```bash
aws bedrock list-inference-profiles --type-equals APPLICATION
```

### Switch Claude Code to Amazon Bedrock

Run the setup command inside Claude Code:

```
/setup-bedrock
```

Choose **Amazon Bedrock**, then enter your region and log in using your preferred method. Run `/status` afterward to confirm the API provider shows **Amazon Bedrock**.

### Pin models to your AIPs

Edit `~/.claude/settings.json` to add the following environment configuration.

```json
"env": {
  "CLAUDE_CODE_USE_BEDROCK": "1",
  "AWS_REGION": "us-east-1",
  "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:application-inference-profile/<SONNET_AIP_ID>",
  "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME": "arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:application-inference-profile/<HAIKU_AIP_ID>"
}
```

### Validate governance enforcement

1. Run `/model` to select your desired model.
2. Invoke Claude Code normally and confirm requests succeed through the pinned AIPs.
3. Attempt a direct foundation-model invocation from the AWS CLI to confirm the SCP blocks it:

Requests directly targeting a foundation model will throw an `AccessDeniedException`. Requests routed through an AIP ARN will succeed.

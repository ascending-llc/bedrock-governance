# Integrations

## Claude Code

Claude Code supports Amazon Bedrock as a provider, letting you route all model traffic through your deployed Application Inference Profiles (AIPs). This means every Claude Code session is covered by the SCP enforcement, CloudTrail audit trail, and CloudWatch anomaly alarms you deployed.

### Prerequisites

- Claude Code v2.1.94 or later
- AWS credentials that can invoke Bedrock in the child account
- Deployed AIP ARNs (available as Terraform outputs after a child deployment)

Retrieve your AIP ARNs at any time:

```bash
aws bedrock list-inference-profiles --type-equals APPLICATION
```

### Switch Claude Code to Amazon Bedrock

Run the setup command inside Claude Code:

```
/setup-bedrock
```

Choose **Amazon Bedrock**, then enter your region and confirm your AWS credentials are active. Run `/status` afterward to confirm the provider shows **Bedrock**.

### Pin models to your AIPs

Edit `~/.claude/settings.json` and add a `modelOverrides` block mapping each model name to its AIP ARN:

```json
{
  "modelOverrides": {
    "claude-sonnet-4-6": "arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:application-inference-profile/<SONNET_AIP_ID>",
    "claude-haiku-4-5": "arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:application-inference-profile/<HAIKU_AIP_ID>"
  }
}
```

Alternatively, set environment variables before launching Claude Code:

```bash
export DEFAULT_ANTHROPIC_SONNET_MODEL="arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:application-inference-profile/<SONNET_AIP_ID>"
export DEFAULT_ANTHROPIC_HAIKU_MODEL="arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:application-inference-profile/<SONNET_AIP_ID>"
```

### Validate governance enforcement

1. Invoke Claude Code normally and confirm requests succeed through the pinned AIPs.
2. Attempt a direct foundation-model invocation from the AWS CLI to confirm the SCP blocks it:

```bash
claude --model sonnet
```

You should receive an `AccessDeniedException`. Requests routed through an AIP ARN will succeed; requests targeting the foundation model ARN directly will be denied by the SCP.

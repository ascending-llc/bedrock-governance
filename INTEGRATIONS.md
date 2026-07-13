# Integrations

## Claude Code

Claude Code supports Amazon Bedrock as a provider, letting you route all model traffic through your deployed Application Inference Profiles (AIPs). This means every Claude Code session is covered by the SCP enforcement, CloudTrail audit trail, and CloudWatch anomaly alarms you deployed.

### Prerequisites

- Claude Code v2.1.94 or later
- AWS credentials that can invoke Bedrock
- Deployed Application Inference Profile ARNs
- AWS CLI config profile configured for the account where your AIPs are deployed

  **Example `~/.aws/config` entry:**
  ```ini
  [profile ASCENDINGBedrockClaudeCodeAccess]
  sso_start_url  = https://my-sso.awsapps.com/start
  sso_region     = us-east-1
  sso_account_id = 123456789012
  sso_role_name  = ASCENDINGBedrockClaudeCodeAccess
  region         = us-east-1
  ```

Retrieve your AIP ARNs at any time:

```bash
aws bedrock list-inference-profiles --type-equals APPLICATION
```

### Pin models to your AIPs

Edit `~/.claude/settings.json` to configure Bedrock with your AIP ARN. The `awsAuthRefresh` key tells Claude Code how to automatically re-authenticate when your AWS credentials expire — useful with SSO profiles that require periodic login.

Use `ANTHROPIC_DEFAULT_<TIER>_MODEL` to pin each model tier to a specific AIP ARN. Claude Code routes different workloads to different tiers (e.g. Haiku for background tasks, Sonnet for primary interactions), so setting both ensures all traffic flows through your governed AIPs. The example below shows Sonnet and Haiku; add an Opus entry the same way if needed.

```json
// ~/.claude/settings.json
{
  "awsAuthRefresh": "aws sso login --profile ASCENDINGBedrockClaudeCodeAccess",
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_PROFILE": "ASCENDINGBedrockClaudeCodeAccess",
    "AWS_REGION": "us-east-1",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:application-inference-profile/<SONNET_AIP_ID>",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:application-inference-profile/<HAIKU_AIP_ID>"
  }
}
```

When credentials expire, Claude Code runs the `awsAuthRefresh` command automatically and retries the request — no manual `aws sso login` required mid-session.

### Validate governance enforcement

1. Run `/model` to select your desired model.
2. Invoke Claude Code normally and confirm requests succeed through the pinned AIPs.
3. Attempt a direct foundation-model invocation from the AWS CLI to confirm the SCP blocks it:

Requests directly targeting a foundation model will throw an `AccessDeniedException`. Requests routed through an AIP ARN will succeed.

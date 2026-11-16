# Client Integrations

Configure engineers' local clients so their traffic goes through the governed
path (SCP enforcement, CloudTrail audit trail, CloudWatch metrics and alarms)
without changing how they work. Both clients authenticate with the customer's
IAM Identity Center SSO profile.

| Client | Endpoint | Model target | Per-model attribution |
| --- | --- | --- | --- |
| Claude Code | `bedrock-runtime` (Invoke API) | Application inference profile (AIP) ARNs | By AIP: metrics, alarms, cost tags |
| Codex | `bedrock-runtime` (Responses API) | System inference profile (`global.openai.*`) | By IAM principal only; AIPs are not supported |

Use `bedrock-runtime` for both. AWS recommends it for new applications and uses
`bedrock-mantle` only for capabilities such as hosted web search, background
inference and non-default projects. Both clients default to the Runtime path
when configured as below; do not enable the Mantle path (see
[Keep clients off `bedrock-mantle`](#keep-clients-off-bedrock-mantle)).

## Claude Code

### Prerequisites

- A current Claude Code release (the `modelOverrides` setting needs a recent
  version; check the Claude Code release notes).
- The customer's SSO profile for the account where the AIPs are deployed, and
  the Identity Center permission set containing the generated policy
  (`identity_center_bedrock_inference_policy_json`).
- The deployed AIP ARNs:

  ```bash
  terraform output -json inference_profile_arns
  aws bedrock list-inference-profiles --type-equals APPLICATION
  ```

Example `~/.aws/config` entry:

```ini
[profile claude-code-bedrock]
sso_session    = customer-sso
sso_account_id = <ACCOUNT_ID>
sso_role_name  = <BEDROCK_PERMISSION_SET>
region         = us-east-1

[sso-session customer-sso]
sso_start_url  = https://<customer>.awsapps.com/start
sso_region     = us-east-1
sso_registration_scopes = sso:account:access
```

### Pin every model to an AIP

Edit `~/.claude/settings.json`. Pin each model tier, because Claude Code routes
different work to different tiers (for example Haiku for background tasks). An
unpinned tier resolves to a built-in cross-Region profile ID, which the SCP
blocks.

```json
{
  "awsAuthRefresh": "aws sso login --profile claude-code-bedrock",
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_PROFILE": "claude-code-bedrock",
    "AWS_REGION": "us-east-1",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:application-inference-profile/<OPUS_AIP_ID>",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:application-inference-profile/<SONNET_AIP_ID>",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:application-inference-profile/<HAIKU_AIP_ID>"
  }
}
```

- `awsAuthRefresh` runs `aws sso login` only when Claude Code finds the
  credentials expired, then retries the request. If browser sign-in tabs keep
  opening behind a corporate proxy, remove it and run `aws sso login` manually.
- To expose several versions of one model family in the `/model` picker, each
  routed to its own AIP, use the `modelOverrides` setting instead of the
  `ANTHROPIC_DEFAULT_*_MODEL` variables.
- Distribute these values through Claude Code managed settings so users cannot
  change them, and pin model versions rather than relying on aliases.

### IAM notes

- Claude Code needs `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream`.
  It also uses `bedrock:GetInferenceProfile` to resolve an AIP to its backing
  model, and `bedrock:ListInferenceProfiles` for profile discovery. Without
  `GetInferenceProfile` it recovers by retrying once with the alternate request
  shape, which adds a round trip per new model. The generated Identity Center
  policy grants both the invoke actions and `bedrock:GetInferenceProfile` on the
  approved AIP ARNs; verify with a non-administrator pilot user.
- The first invocation of each Anthropic model in a new account creates an AWS
  Marketplace agreement. The first caller needs `aws-marketplace:ViewSubscriptions`
  and `aws-marketplace:Subscribe`; this is normally done once by an administrator.

### Validate

1. In Claude Code run `/status`: the provider should read Amazon Bedrock (not
   Mantle) and the region should be the AIP region. Send a short prompt.
2. Confirm the call used the AIP: CloudTrail shows a `Converse` or `InvokeModel*`
   management event whose `requestParameters.modelId` is the AIP ARN, and the
   AIP's `InputTokenCount` metric (dimension `ModelId` = the profile ID) increases.
3. Confirm the SCP blocks direct invocation (run as the pilot user, not an
   administrator):

   ```bash
   aws bedrock-runtime converse \
     --model-id us.anthropic.claude-sonnet-5-5 \
     --messages '[{"role":"user","content":[{"text":"x"}]}]' \
     --profile claude-code-bedrock
   ```

   Expect `AccessDeniedException` citing an explicit deny in a service control
   policy. A plain "no identity-based policy allows" message means IAM, not the
   SCP, denied the call, which does not prove the SCP works.

## Codex

### How it connects

Codex has two built-in Bedrock providers: `amazon-bedrock-runtime` (the
`bedrock-runtime` endpoint, with Global and Geo cross-Region profiles) and
`amazon-bedrock` (the `bedrock-mantle` endpoint). Use `amazon-bedrock-runtime`.

Three facts shape the governance for Codex:

- **No application inference profiles.** On the Runtime Responses API, a request
  naming an AIP is rejected with a 400. Codex must use a system-defined profile
  such as `global.openai.gpt-6.1-sol`.
- **Usage is attributed by IAM principal only**, not by profile tag, so
  per-model AIP metrics, alarms and cost tags in this repository do not cover
  Codex. Per-user attribution comes from CloudTrail and the SSO identity.
- **The SCP needs two exemptions for this path:** the `global.openai.*` profiles
  and the account's `project/default` (the Responses API authorizes
  `bedrock:InvokeModel` on both the profile and the default project). Set
  `allow_codex_scp_exceptions = true` in the management tfvars only for
  customers with Codex in scope, and list the approved profile and project ARNs
  in `approved_codex_inference_profile_arns` and `approved_codex_project_arns`
  so the generated permission set limits Codex to those.

### Configure

`~/.codex/config.toml` (project-level `.codex/config.toml` cannot set providers):

```toml
model_provider = "amazon-bedrock-runtime"
model = "global.openai.gpt-6.1-sol"   # must be in approved_codex_inference_profile_arns
web_search = "disabled"                # hosted web search is not available on Runtime
```

Credentials use the AWS SDK chain with the SSO profile:

```bash
aws sso login --profile codex-bedrock
export AWS_PROFILE=codex-bedrock
export AWS_REGION=us-east-1
```

The desktop app and IDE extension may not inherit shell variables; put
`AWS_PROFILE` and `AWS_REGION` in `~/.codex/.env` and restart. Do not use
`AWS_BEARER_TOKEN_BEDROCK` (API keys) for governed use: Codex checks a Bedrock
API key before the SSO chain, so an old key silently overrides the profile.

### Validate

1. In Codex run `/status`: the provider must be `amazon-bedrock-runtime` and the
   model the approved profile. Send `Reply with exactly: bedrock-ok`.
2. Confirm the call in CloudTrail and CloudWatch (see below). Confirm a direct
   foundation-model ID or an unapproved profile is denied for the pilot user.

### Open verification items (not yet tested in the sandbox)

Neither CLI is installed on the machine used for sandbox testing, so these
client paths have not been exercised live:

- Which CloudTrail category and event source a Runtime Responses call produces.
  `Converse`/`InvokeModel*` are management events on `bedrock.amazonaws.com`;
  confirm the same for Responses calls. Only if a client uses `bedrock-mantle`
  does `enable_bedrock_mantle_data_events = true` apply.
- Whether Codex sends `store` (stored responses are retained for 30 days by
  default). If the customer does not want Bedrock to retain conversation data,
  set the account data-retention mode to `none` or require `store=false`.
- Data residency. `global.openai.*` can route to any commercial Region. If the
  customer requires US-only processing, use `us.openai.*` profiles, and extend
  the SCP exemption and the permission set to match (the current exemption
  covers `global.openai.*` only).

## Keep clients off `bedrock-mantle`

The SCP restricts `bedrock:` actions on `bedrock-runtime`. The `bedrock-mantle`
endpoint authorizes `bedrock-mantle:CreateInference` instead. Claude Code
(`CLAUDE_CODE_USE_MANTLE`) and Codex (`amazon-bedrock`) can both use it.
Set `deny_bedrock_mantle_inference = true` in the management tfvars to add an SCP
deny for it (with the break-glass exemption). Also keep `bedrock-mantle:` actions
out of the pilot permission set, and verify as a pilot user that a Mantle call is
denied.

Also withhold `iam:CreateServiceSpecificCredential` (long-term Bedrock API keys)
and `bedrock:CallWithBearerToken` from the permission set. API keys inherit the
principal's permissions, but long-term keys create IAM users outside the SSO
workflow and are recommended by AWS only for exploration.

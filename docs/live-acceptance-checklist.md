# Live Acceptance Checklist

Purpose: prove in a deployed account what Terraform tests cannot: that the
deployed controls behave as the SOW describes. Record evidence (command output,
screenshot, or ticket link) in the **Evidence** column and mark Pass/Fail.

Replace the placeholders below with the deployment's values: the account IDs, the
`resource_name_prefix` from its tfvars, and the profile IDs from the child
state's `terraform output -json inference_profile_ids`. Model names in the check
commands (`claude-sonnet-5-5` and so on) assume the `model_sources` names in
its `child.tfvars`. Keep the filled-in copy in your private deployment repo.

| Setting | Value |
| --- | --- |
| Child account | `<CHILD_ACCOUNT_ID>` |
| Management account | `<MANAGEMENT_ACCOUNT_ID>` |
| Region | `us-east-1` |
| Resource prefix | `<RESOURCE_NAME_PREFIX>` |
| Trail | `<RESOURCE_NAME_PREFIX>-bedrock-audit` |
| Audit bucket | `<RESOURCE_NAME_PREFIX>-bedrock-audit-<CHILD_ACCOUNT_ID>-us-east-1` |
| SNS topic | `<RESOURCE_NAME_PREFIX>-bedrock-anomaly-alerts` |
| Profiles (Sonnet / Opus / Haiku) | `<SONNET_PROFILE_ID>` / `<OPUS_PROFILE_ID>` / `<HAIKU_PROFILE_ID>` |

Run child-account commands with a child-account profile, SCP/billing commands
with the management-account profile, and invocation tests as an **ordinary pilot
user** (SSO), not an administrator. Set up shell variables once:

```bash
export AWS_REGION=us-east-1
export PREFIX=<RESOURCE_NAME_PREFIX>
export ACCT=<CHILD_ACCOUNT_ID>
export AIP_SONNET=arn:aws:bedrock:us-east-1:$ACCT:application-inference-profile/<SONNET_PROFILE_ID>
export AIP_OPUS=arn:aws:bedrock:us-east-1:$ACCT:application-inference-profile/<OPUS_PROFILE_ID>
export AIP_HAIKU=arn:aws:bedrock:us-east-1:$ACCT:application-inference-profile/<HAIKU_PROFILE_ID>
export BUCKET=$PREFIX-bedrock-audit-$ACCT-$AWS_REGION
export TRAIL=$PREFIX-bedrock-audit
export TOPIC_ARN=arn:aws:sns:$AWS_REGION:$ACCT:$PREFIX-bedrock-anomaly-alerts
```

Do the sections in order. Section A generates the traffic the later sections
inspect. Note the time you start (`date -u`) so you can find your events. The
`date -d` forms below are GNU syntax; on macOS use `date -u -v-1H +%FT%TZ`.

---

## A. Profiles and tags (SOW: provisioning, consistent naming/tagging)

| # | Check | Command | Expected | Pass/Fail | Evidence |
| --- | --- | --- | --- | --- | --- |
| A1 | One APPLICATION profile per approved model, named `<prefix>-<name>` | `aws bedrock list-inference-profiles --type-equals APPLICATION --query 'inferenceProfileSummaries[].[inferenceProfileName,inferenceProfileArn,status]' --output table` | Three profiles, `ACTIVE`, ARNs match the table above | | |
| A2 | Each profile carries `Project`, `ManagedBy`, `DeploymentMode`, `Team`, **`Model`** | `aws bedrock list-tags-for-resource --resource-arn $AIP_SONNET` (repeat for Opus, Haiku) | `Model` equals the profile's model name (`claude-sonnet-5-5`, etc.); other tags present | | |
| A3 | Each profile points at the intended model | `aws bedrock get-inference-profile --inference-profile-identifier <SONNET_PROFILE_ID> --query 'models'` | Model ARNs belong to the expected Claude model | | |
| A4 | Approved profile works for a pilot user (generates traffic) | `aws bedrock-runtime converse --model-id $AIP_SONNET --messages '[{"role":"user","content":[{"text":"ping"}]}]' --inference-config maxTokens=20` | Returns a response. Repeat with `$AIP_HAIKU` and `$AIP_OPUS`. Also run one streaming call (`converse-stream`) | | |

## B. CloudWatch metrics (SOW: per-model usage attribution and metrics)

Metrics can lag a few minutes after traffic. Run A4 first.

| # | Check | Command | Expected | Pass/Fail | Evidence |
| --- | --- | --- | --- | --- | --- |
| B1 | **Confirm the real metric dimension value** (verified live: `ModelId` is the profile **ID**, e.g. `<HAIKU_PROFILE_ID>`, not the ARN; the alarms use the ID) | `aws cloudwatch list-metrics --namespace AWS/Bedrock --metric-name InputTokenCount` | A metric exists whose `ModelId` dimension value is exactly the profile ID (for example `<SONNET_PROFILE_ID>`), and the deployed alarm's `m1` dimension matches it (`describe-alarms`). If the alarm dimension differs, it watches an empty series and never fires (missing data is treated as not breaching) | | |
| B2 | Output tokens are published per profile | `aws cloudwatch list-metrics --namespace AWS/Bedrock --metric-name OutputTokenCount` | Same three dimension values | | |
| B3 | Values are non-zero and attributable per model | `aws cloudwatch get-metric-statistics --namespace AWS/Bedrock --metric-name InputTokenCount --dimensions Name=ModelId,Value=<SONNET_PROFILE_ID> --start-time $(date -u -v-1H +%FT%TZ) --end-time $(date -u +%FT%TZ) --period 300 --statistics Sum` | Non-zero Sum for the profile you called; zero/absent for profiles you did not call | | |

## C. Anomaly alarms and SNS delivery (SOW: anomaly detection, alert delivery)

| # | Check | Command | Expected | Pass/Fail | Evidence |
| --- | --- | --- | --- | --- | --- |
| C1 | Six alarms exist (input + output x 3 models) | `aws cloudwatch describe-alarms --alarm-name-prefix $PREFIX- --query 'MetricAlarms[].[AlarmName,StateValue,ComparisonOperator,ThresholdMetricId]' --output table` | Six alarms, `GreaterThanUpperThreshold`, threshold metric `ad1`. State `INSUFFICIENT_DATA` or `OK` is normal while the model trains | | |
| C2 | Alarms point at the SNS topic for ALARM and OK | `aws cloudwatch describe-alarms --alarm-name-prefix $PREFIX- --query 'MetricAlarms[].[AlarmName,AlarmActions,OKActions]'` | Both lists contain `$TOPIC_ARN` | | |
| C3 | **Email subscription is confirmed** | `aws sns list-subscriptions-by-topic --topic-arn $TOPIC_ARN --query 'Subscriptions[].[Endpoint,SubscriptionArn]'` | `SubscriptionArn` is a real ARN, **not** `PendingConfirmation`. If pending, click the link in the confirmation email | | |
| C4 | **End-to-end delivery test** | `aws cloudwatch set-alarm-state --alarm-name $PREFIX-claude-sonnet-5-5-input-token-anomaly --state-value ALARM --state-reason "acceptance test"` | Alert email arrives at the agreed recipient within a few minutes. Record arrival time | | |
| C5 | Restore state | `aws cloudwatch set-alarm-state --alarm-name $PREFIX-claude-sonnet-5-5-input-token-anomaly --state-value OK --state-reason "acceptance test complete"` | OK email arrives (confirms `ok_actions`). The alarm self-corrects on its next evaluation regardless | | |
| C6 | Anomaly model exists | `aws cloudwatch describe-anomaly-detectors --namespace AWS/Bedrock` | Detectors for the six metric/dimension pairs (output format may vary for metric-math alarms; the alarm's `ad1` band in the console is also acceptable evidence) | | |
| C7 | Real anomaly (optional, after training) | Send a burst of calls well above normal usage, then wait for the evaluation window (3 hourly periods, 2 datapoints must breach) | Alarm moves to `ALARM` and email arrives. Not practical on day one; the band needs history to learn | | |

Note for the customer: if the agreed target is an **existing** SNS topic
(`alarm_sns_topic_arn`), Terraform does not manage its policy. Confirm the topic
policy allows `cloudwatch.amazonaws.com` to publish (and the KMS key policy if
the topic is encrypted) before running C4.

## D. CloudTrail (SOW: audit-ready logging)

Allow 15 minutes after A4 for delivery.

| # | Check | Command | Expected | Pass/Fail | Evidence |
| --- | --- | --- | --- | --- | --- |
| D1 | Trail configured as designed | `aws cloudtrail get-trail --name $TRAIL --query 'Trail.[IsMultiRegionTrail,LogFileValidationEnabled,S3BucketName]'` and `aws cloudtrail get-trail-status --name $TRAIL --query '[IsLogging,LatestDeliveryError]'` | `true`, `true`, the audit bucket; logging `true`; no delivery error | | |
| D2 | Selectors as designed | `aws cloudtrail get-event-selectors --trail-name $TRAIL --query 'AdvancedEventSelectors[].[Name,FieldSelectors]'` | `ManagementEvents`, `BedrockModelDataEvents` (`AWS::Bedrock::Model`), `BedrockAsyncInvokeDataEvents` (`AWS::Bedrock::AsyncInvoke`), plus `BedrockMantleProjectDataEvents` only if `enable_bedrock_mantle_data_events` is set | | |
| D3 | **Invocations are management events** | `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=Converse --start-time $(date -u -v-1H +%FT%TZ)` | The A4 `Converse` call appears (`lookup-events` returns management events only). If it does not, the AWS classification no longer holds: update `docs/bedrock-audit-event-coverage.md` and the test messages | | |
| D4 | **Invocation events delivered to S3** | `aws s3 ls s3://$BUCKET/AWSLogs/$ACCT/CloudTrail/$AWS_REGION/ --recursive \| tail`, then download a recent file and run `gunzip -c <file> \| jq '.Records[] \| select(.eventSource=="bedrock.amazonaws.com") \| {eventName,eventType,eventCategory,user:.userIdentity.arn,modelId:.requestParameters.modelId}'` | Records for `Converse` / `ConverseStream` / `InvokeModel*` with `eventType: "AwsApiCall"` and the caller identity (the SSO user). Each call appears **once**, as `eventCategory: "Management"` (the data selectors exclude these APIs). Events from before the selector change appear twice (Management and Data); count one copy | | |
| D5 | **Profile-routed calls are attributable** (most important) | Same query; look at `requestParameters.modelId` of the events from your A4 calls | `modelId` is the application inference profile ARN (or otherwise identifies the profile). If it shows only the underlying model, per-profile attribution from CloudTrail is not possible: raise before going further and rely on CloudWatch metrics | | |
| D6 | Streaming behavior | Find the `converse-stream` call from A4; filter `eventType` | One `AwsApiCall` plus a separate `AwsServiceEvent` (stream completion) carrying `inputTokens`/`outputTokens` and `serviceEventDetails.parentRequestId`. Count only `AwsApiCall` as invocations | | |
| D7 | Log-file integrity validation | After at least one hour: `aws cloudtrail validate-logs --trail-arn arn:aws:cloudtrail:$AWS_REGION:$ACCT:trail/$TRAIL --start-time $(date -u -d '-2 hours' +%FT%TZ)` | "All digest files and log files validated" (no invalid/missing) | | |
| D8 | No prompt/response content in logs | Inspect events from D4 | Metadata only (model, caller, request parameters, token usage on stream-completion events); no prompt text | | |
| D9 | Bucket hardening | `aws s3api get-bucket-policy --bucket $BUCKET`; `aws s3api get-bucket-lifecycle-configuration --bucket $BUCKET`; `aws s3api get-public-access-block --bucket $BUCKET` | Policy has `aws:SourceArn` conditions and the TLS-only deny; lifecycle matches `audit_log_retention_days` (default 30 unless overridden); all public-access blocks `true` | | |
| D10 | Control-plane change is visible | Add and remove a throwaway tag on a profile, then `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=TagResource` | The change appears (management selector works) | | |

## E. SCP enforcement (SOW: organization-level access control)

Run as an ordinary pilot user in the child account. All "denied" results
should name an **explicit deny in a service control policy**; a plain
"no identity-based policy allows" message means IAM, not the SCP, is blocking
you, which does not prove the SCP works. If you can, retest the denials with a
role that has broad Bedrock IAM permissions, to isolate the SCP.

| # | Check | Command | Expected | Pass/Fail | Evidence |
| --- | --- | --- | --- | --- | --- |
| E1 | Approved profile allowed (sync, streaming, converse) | A4 commands | Success | | |
| E2 | Direct foundation-model ID denied | `aws bedrock-runtime converse --model-id anthropic.claude-sonnet-5-5 --messages '[{"role":"user","content":[{"text":"x"}]}]'` (use the actual base model ID; it may also fail on model or inference-type requirements, which is not the result we want to see) | `AccessDeniedException` referencing an explicit deny in a service control policy | | |
| E3 | System (cross-Region) inference profile denied | `aws bedrock-runtime converse --model-id us.anthropic.claude-sonnet-5-5 --messages '[{"role":"user","content":[{"text":"x"}]}]'` | Explicit SCP deny | | |
| E4 | A profile **not** on the approved list is denied (strict mode) | Create a throwaway application profile in the child account (or use one outside the approved three), then converse against it | Explicit SCP deny. Delete the throwaway profile afterward | | |
| E5 | Invoke-model and streaming APIs | Repeat E2 with `invoke-model` and `invoke-model-with-response-stream` | Denied for direct FM, allowed for approved profiles | | |
| E6 | Async and bidirectional | Only if a client uses them. `StartAsyncInvoke` follows `bedrock:InvokeModel`. **`InvokeModelWithBidirectionalStream` is not covered by the SCP.** Test it and record the result so the customer can decide | Document outcome | | |
| E7 | Codex exceptions behave as documented (temporary) | Global `openai.*` profile and `project/default` | Allowed only where the Identity Center policy permits; no model agreement is accepted in the account, so expect a model-access error rather than an SCP deny | | |
| E7a | **Which endpoint does Codex use?** | Check the client's provider (`amazon-bedrock-runtime` vs `amazon-bedrock`, see `INTEGRATIONS.md`) and, after a call, the event source in CloudTrail | AWS and OpenAI both recommend `bedrock-runtime` for Codex; confirm that is what it uses and that the call is recorded as a `bedrock.amazonaws.com` event. If `bedrock-mantle`: set `enable_bedrock_mantle_data_events = true`, re-run D2, and confirm `bedrock-mantle.amazonaws.com` `CreateInference` data events arrive. Also record which IAM actions the call needs and whether the SCP denied or allowed them | | |
| E8 | **Break-glass role (only if configured)** | `aws sts get-caller-identity` as the role to confirm the ARN matches the configured pattern, then run E2 | Not blocked by the SCP (may still fail for IAM or model-access reasons). Confirm an alert or review exists for its use | | |
| E9 | Scope is the POC only | `aws organizations list-targets-for-policy --policy-id <scp-id>` (management account) | Only the child account; not an OU or root | | |

## F. Identity Center (SOW: SSO integration)

| # | Check | Command | Expected | Pass/Fail | Evidence |
| --- | --- | --- | --- | --- | --- |
| F1 | Pilot user signs in with existing SSO flow | `aws sso login --profile <pilot-profile>`; `aws sts get-caller-identity --profile <pilot-profile>` | ARN is an `AWSReservedSSO_...` role session for the user | | |
| F2 | Permission set carries the generated Bedrock policy | `aws sso-admin get-inline-policy-for-permission-set ...` (see `docs/identity-center-permissions.md`) | Statements `InvokeApprovedInferenceProfiles`, `InvokeRoutedFoundationModelsOnlyThroughApprovedProfiles` (and the Codex project statement if configured) present, existing statements preserved | | |
| F3 | Least privilege | Attempt `aws bedrock create-inference-profile` and an unapproved model as the pilot user | Denied | | |
| F4 | Attribution | CloudTrail event from D4 shows the SSO user (not a shared role session name) | `userIdentity` identifies the individual | | |

## G. Cost allocation (SOW: cost-allocation visibility)

| # | Check | Command | Expected | Pass/Fail | Evidence |
| --- | --- | --- | --- | --- | --- |
| G1 | Tags recognized by billing (management account) | `aws ce list-cost-allocation-tags --tag-keys Project Team Model` | Keys listed (appear after tagged resources have usage, up to about 24h) | | |
| G2 | Tags activated | Same, check `Status` | `Active` for `Project`, `Team`, `Model`. Compare to Terraform output `cost_allocation_tag_status` | | |
| G3 | Cost visible by tag (next day or later) | Cost Explorer: group by tag `Model`, filter service Amazon Bedrock | Spend appears per model. Expect a delay; tags are not retroactive | | |
| G4 | Resource-level view (optional) | CUR with resource IDs, or Cost Explorer resource-level data | Spend attributable to individual profile ARNs | | |

---

## H. Daily cost alerts and limits (optional; only when `pricing` is configured)

Use a low `daily_cost_limit_usd` on a test profile (for example `$0.05`) so a
few calls trip it. Cost is estimated from token metrics, so allow a few minutes
for metrics and the next enforcer run. Set `export FN=$PREFIX-bedrock-cost-limit-enforcer`
and `export BLOCK_POLICY=arn:aws:iam::$ACCT:policy/$PREFIX-bedrock-cost-limit-block`.

| # | Check | Command | Expected | Pass/Fail | Evidence |
| --- | --- | --- | --- | --- | --- |
| H1 | Enforcer deployed and scheduled | `aws lambda get-function --function-name $FN --query 'Configuration.[State,Runtime]'`; `aws events describe-rule --name $PREFIX-bedrock-cost-limit-schedule --query '[State,ScheduleExpression]'` | `Active`; rule `ENABLED` at the configured interval | | |
| H2 | Cost metric published per profile | `aws cloudwatch list-metrics --namespace BedrockGovernance --metric-name EstimatedDailyCostUSD` | One metric per priced profile, `ModelId` = profile ID | | |
| H3 | Estimate is plausible | Compare the latest `EstimatedDailyCostUSD` datapoint with `InputTokenCount`/`OutputTokenCount` sums x your configured prices | Within rounding. If cache tokens are used, confirm `CacheReadInputTokenCount`/`CacheWriteInputTokenCount` exist for the profile | | |
| H4 | Alert alarm fires | Drive spend past the alert threshold, then `aws cloudwatch describe-alarms --alarm-names $PREFIX-<name>-daily-cost-alert --query 'MetricAlarms[].StateValue'` | `ALARM`; notification email arrives | | |
| H5 | Limit blocks the profile | Drive spend past `daily_cost_limit_usd`, wait for the next run, then repeat A4 against that profile as a pilot user | `AccessDeniedException` naming an explicit deny in an identity-based policy; other profiles still work | | |
| H6 | Block policy content | `aws iam get-policy-version --policy-arn $BLOCK_POLICY --version-id $(aws iam get-policy --policy-arn $BLOCK_POLICY --query Policy.DefaultVersionId --output text)` | Statement `DenyBlockedInferenceProfiles` lists the blocked profile ARN | | |
| H7 | Limit alarm notifies | `aws cloudwatch describe-alarms --alarm-names $PREFIX-<name>-daily-cost-limit` | `ALARM` and an email while blocked | | |
| H8 | Block lifts | Raise `daily_cost_limit_usd` and apply (or wait past 00:00 UTC); after the next run repeat A4 | Call succeeds; policy reverts to `NoProfilesBlocked`; limit alarm returns to `OK` | | |
| H9 | Block policy is attached | Permission set (or listed roles) references the policy | Without it H5 will not deny; record where it is attached | | |
| H10 | Enforcer failures alert | `aws cloudwatch describe-alarms --alarm-names $PREFIX-bedrock-cost-limit-enforcer-errors` | Alarm exists and notifies the SNS target | | |

---

## I. Desktop configuration and pilot onboarding (SOW: macOS/Windows standard configuration, 5 pilot users)

The client policies come from
[coding-agent-3p](https://github.com/ascending-llc/coding-agent-3p) (see
`DEPLOYMENT.md` Step 7). Run I1-I4 once, then I5 for every pilot user and record
the result in the matrix below. Cover both macOS and Windows and both Claude and
Codex across the five users.

| # | Check | Command | Expected | Pass/Fail | Evidence |
| --- | --- | --- | --- | --- | --- |
| I1 | Artifacts generated for both platforms | In coding-agent-3p: `make policies PRODUCTS="claude codex"`, then `grep -r REPLACE_WITH_ dist/` | macOS `.mobileconfig` (Claude, Codex), Windows `.reg`, Codex `requirements.toml` and `aws-config-CCWB.ini` exist; the grep finds nothing | | |
| I2 | Config matches the deployment | Compare `config/config.json` with `terraform output -json inference_profile_ids` and `inference_profile_arns` | Each `claude.models.<tier>.aip_arn` is a deployed AIP ARN; `codex.default_model` is in `approved_codex_inference_profile_arns`; `aws.sso_role_name` is the permission set carrying the generated policy | | |
| I3 | Policies delivered | macOS: profile listed in System Settings > Privacy & Security > Profiles. Windows: policy applied per the coding-agent-3p admin guide | Installed on at least one Mac and one Windows machine | | |
| I4 | Clients cannot be re-pointed | Try to change the provider or AIP in the client as the pilot user | Managed settings win (Claude Desktop/Code policy, Codex `requirements.toml`). Note that this controls the route only; IAM and the SCP remain the authorization boundary | | |
| I5 | Per-user verification | See the matrix below | Every column passes for every user | | |

Per-user checks (commands as in A4, E2 and D4):

- **Sign-in**: `aws sso login --profile CCWB` opens the Identity Center flow and
  `aws sts get-caller-identity --profile CCWB` shows the user's `AWSReservedSSO_` role session.
- **Claude**: a prompt in Claude Desktop and in Claude Code succeeds, and the
  AIP's `InputTokenCount` metric increases (check B3).
- **Codex**: a prompt in Codex / ChatGPT Desktop succeeds through
  `amazon-bedrock-runtime`; CloudTrail shows the call under the user's role session.
- **Denied**: a direct foundation-model call from the CLI returns an explicit SCP deny (E2).
- **Audit**: `aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=<user>`
  shows the user's `Converse`/`InvokeModel` events.

| User | OS | Sign-in | Claude Desktop | Claude Code | Codex | Direct call denied | CloudTrail shows user | Pass/Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | | | | | | | | |
| 2 | | | | | | | | |
| 3 | | | | | | | | |
| 4 | | | | | | | | |
| 5 | | | | | | | | |

---

## Sign-off

| Area | Result | Date | Reviewer |
| --- | --- | --- | --- |
| A Profiles and tags | | | |
| B Metrics | | | |
| C Alarms and SNS | | | |
| D CloudTrail | | | |
| E SCP | | | |
| F Identity Center | | | |
| G Cost allocation | | | |
| H Daily cost alerts and limits | | | |
| I Desktop configuration and pilot onboarding | | | |

Known limits to state when presenting results: the anomaly band needs usage
history before it is meaningful; cost data is delayed and tag activation is not
a dashboard or budget; the daily cost limit is a token-metric estimate with a
scheduled check, not a hard billing cap; CloudTrail records metadata, not
prompts/responses; a break-glass exemption widens access and needs its own
approval and monitoring.

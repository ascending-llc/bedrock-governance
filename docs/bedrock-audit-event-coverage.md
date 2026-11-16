# Bedrock CloudTrail Event Coverage

The child trail is multi-Region, enables logging and log-file integrity
validation, and delivers to a dedicated, versioned audit S3 bucket (retention is
set by `audit_log_retention_days`, default 30). Its advanced event selectors are
defined once in `modules/bedrock_governance/main.tf` and exposed as the
`cloudtrail_advanced_event_selectors` output for review.

## What the trail captures

The two Bedrock data selectors exclude `Converse`, `ConverseStream`, `InvokeModel` and `InvokeModelWithResponseStream` by `eventName`, because the management selector already records those calls. Without that exclusion every invocation was logged twice.

| Selector name | Fields | Captures |
| --- | --- | --- |
| `ManagementEvents` | `eventCategory = Management` | All management events from all AWS services in the account. This is what records Bedrock runtime invocations (see below) and control-plane changes such as `CreateInferenceProfile`, `TagResource` and trail or IAM changes. |
| `BedrockModelDataEvents` | `eventCategory = Data`, `resources.type = AWS::Bedrock::Model`, `eventName` not in the four invocation APIs | Other Bedrock model data events (for example `InvokeModelWithBidirectionalStream`, `StartAsyncInvoke`, `GetAsyncInvoke`). |
| `BedrockAsyncInvokeDataEvents` | `eventCategory = Data`, `resources.type = AWS::Bedrock::AsyncInvoke`, `eventName` not in the four invocation APIs | Bedrock asynchronous invocation data events. |
| `BedrockMantleProjectDataEvents` (optional) | `eventCategory = Data`, `resources.type = AWS::BedrockMantle::Project` | `bedrock-mantle` inference data events. Off by default; see below. |

## Classification of runtime operations

Per the AWS documentation ("Monitor Amazon Bedrock API calls using CloudTrail"):

| Runtime operation | CloudTrail category | Recorded by |
| --- | --- | --- |
| `InvokeModel`, `InvokeModelWithResponseStream`, `Converse`, `ConverseStream` | Management event | `ManagementEvents` |
| `ListAsyncInvokes` | Management event | `ManagementEvents` |
| `StartAsyncInvoke`, `GetAsyncInvoke` | Data event | `BedrockModelDataEvents` and `BedrockAsyncInvokeDataEvents` (AWS requires both resource types) |
| `InvokeModelWithBidirectionalStream` | Data event | `BedrockModelDataEvents` and `BedrockAsyncInvokeDataEvents` |
| Agent, Knowledge Base, Flow, Prompt, or Guardrail data operations | Their own Bedrock resource types | Not covered. Outside the current SOW's model-invocation scope; add selectors only if those services enter scope. |

The management selector is therefore the control that satisfies the SOW's audit
requirement for synchronous, streaming and conversational invocations. Do not
narrow or remove it without confirming the replacement still records these
operations. The two data selectors cover asynchronous and bidirectional
invocations, which the current permission set does not grant anyway.

The "Confirmed live" results for this table are recorded in
`docs/live-acceptance-checklist.md`, section D.

## Why the data selectors exclude the invocation APIs

An unfiltered `AWS::Bedrock::Model` data selector also matches `Converse` and
`ConverseStream` (and the invocation APIs generally), so each call was delivered
to S3 twice: once with `eventCategory = Management` and once with `Data`, with
the same `requestID` (observed live in the sandbox on November 15, 2026). The
Data copy is billed as a CloudTrail data event.

The data selectors now exclude `Converse`, `ConverseStream`, `InvokeModel` and
`InvokeModelWithResponseStream`, so those calls are recorded once, as management
events, and the data selectors still capture bidirectional and asynchronous
calls. Confirm after deploying (checklist D4) that each call appears once.
Events recorded before the change keep both copies; count `eventCategory =
Management` and `eventType = AwsApiCall` when analyzing that period.

## Streaming events

`InvokeModelWithResponseStream` and `ConverseStream` also produce a
stream-completion event with `eventType = AwsServiceEvent` after the stream
ends. It carries `inputTokens` and `outputTokens`, identifies the underlying
model in `resources`, is not an API call, and is not evaluated by IAM or SCPs.
Count invocations only from events with `eventType = AwsApiCall`; join the
completion event to the API call with `serviceEventDetails.parentRequestId`.

## Attributing an invocation to a profile and user

- User: `userIdentity` (for Identity Center users, the role session name is
  the user's email and `onBehalfOf` carries the identity-store user ID).
- Profile: `requestParameters.modelId` on the management event is the
  application inference profile ARN (observed live on a `Converse` call).
- Underlying model: `resources[]` lists the foundation model
  (`AWS::Bedrock::Model`), not the profile.
- Token counts: `additionalEventData.inputTokens` / `outputTokens` on the
  `Converse` API-call event (observed live), on stream-completion events for
  streaming calls, and in CloudWatch metrics.

## Codex and the `bedrock-mantle` endpoint

Inference on the `bedrock-mantle.<region>.api.aws` endpoint (OpenAI-compatible
Responses and Chat Completions APIs) is recorded differently from
`bedrock-runtime`: event source `bedrock-mantle.amazonaws.com`, resource type
`AWS::BedrockMantle::Project`, and inference is a **data event**. The default
selectors do not record it, and filters on `bedrock.amazonaws.com` will not see
it.

Set `enable_bedrock_mantle_data_events = true` in the child state only after
confirming which endpoint the Codex client uses and that CloudTrail accepts the
selector in the target account. Request `metadata` is logged verbatim, so
clients must not place secrets in it.

## Why all management events are captured

The attempted positive `eventSource Equals bedrock.amazonaws.com` selector
paired with the Management category was rejected by CloudTrail in the sandbox
deployment. AWS documents `eventSource` as a supported management selector
field, so this should not be generalized to every operator or trail
configuration. Verify any narrower selector against the target trail before
using it.

## Operational notes

- The first copy of management events in a Region is free; if another trail
  already records management events in the account, this trail's copy is
  billed. Data-event CloudTrail charges apply to the data selectors.
- Events for cross-Region inference profiles are recorded in the Region where
  the request was made; the trail is multi-Region.
- CloudTrail records invocation metadata for audit, not full prompts and
  responses. Use Bedrock model invocation logging if prompt/response capture is
  ever required.
- Events typically arrive in S3 within about 5 to 15 minutes. Digest files for
  log-file validation are delivered hourly.

Terraform tests assert the selectors exist. They cannot prove what CloudTrail
records; only the live acceptance checklist can.

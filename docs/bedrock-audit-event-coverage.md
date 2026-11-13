# Bedrock CloudTrail Event Coverage

The child trail is multi-Region, explicitly enables logging and log-file
integrity validation, and delivers to the versioned audit S3 bucket. Its
advanced event selectors are defined once in `modules/bedrock_governance/main.tf`
and exposed as the `cloudtrail_advanced_event_selectors` output for review.

| Runtime operation family | CloudTrail category / resource selector | Included by this configuration |
| --- | --- | --- |
| `InvokeModel`, `InvokeModelWithResponseStream`, `Converse`, `ConverseStream` | Management events | Yes; the current selector captures management events from all sources. |
| `InvokeModelWithBidirectionalStream` | Data event for `AWS::Bedrock::Model` and `AWS::Bedrock::AsyncInvoke` | Yes; both resource types are selected. |
| `StartAsyncInvoke`, `GetAsyncInvoke` | Data events for `AWS::Bedrock::Model` and `AWS::Bedrock::AsyncInvoke` | Yes; both resource types are selected. |
| Agent, Knowledge Base, Flow, Prompt, or Guardrail data operations | Their own Bedrock resource types | No; these are outside the current SOW's model-invocation scope. Add selectors only if those services enter scope. |

The management selector currently captures management events from all AWS
services. In the sandbox deployment, CloudTrail rejected the attempted positive
`eventSource Equals bedrock.amazonaws.com` selector when paired with the
Management category. AWS documents `eventSource` as a supported management
selector field, including source exclusions, so this observed failure should not
be generalized to every operator or trail configuration. Verify a narrower
selector against the target trail before using it. The data-event selectors
capture all events for the selected Model/AsyncInvoke resource types without
filtering by `eventName`. Data-event CloudTrail charges apply. Streaming can
produce both an API-call event and a stream-completion service event; do not
double-count them as separate invocations. CloudTrail records invocation
metadata, not full prompt/response content.

Terraform tests assert the management selector, Model and AsyncInvoke data
selectors. Live acceptance must still confirm delivery and inspect actual events
for the client's supported invocation paths.
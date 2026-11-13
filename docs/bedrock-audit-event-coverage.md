# Bedrock CloudTrail Event Coverage

The child trail is multi-Region, explicitly enables logging and log-file
integrity validation, and delivers to the versioned audit S3 bucket. Its
advanced event selectors are defined once in `modules/bedrock_governance/main.tf`
and exposed as the `cloudtrail_advanced_event_selectors` output for review.

| Runtime operation family | CloudTrail category / resource selector | Included by this configuration |
| --- | --- | --- |
| `InvokeModel`, `InvokeModelWithResponseStream`, `Converse`, `ConverseStream` | Management event with `eventSource=bedrock.amazonaws.com` | Yes; the management selector filters to Bedrock. |
| `InvokeModelWithBidirectionalStream` | Data event for `AWS::Bedrock::Model` and `AWS::Bedrock::AsyncInvoke` | Yes; both resource types are selected. |
| `StartAsyncInvoke`, `GetAsyncInvoke` | Data events for `AWS::Bedrock::Model` and `AWS::Bedrock::AsyncInvoke` | Yes; both resource types are selected. |
| Agent, Knowledge Base, Flow, Prompt, or Guardrail data operations | Their own Bedrock resource types | No; these are outside the current SOW's model-invocation scope. Add selectors only if those services enter scope. |

The selectors include only Bedrock management events (filtered by
`eventSource=bedrock.amazonaws.com`) and all data events for the selected
Model/AsyncInvoke resource types; they do not filter those data events by
`eventName`. This includes the supported runtime operations listed above.
Data-event CloudTrail charges apply. Streaming can produce both an API-call
event and a stream-completion service event; do not double-count them as
separate invocations. CloudTrail records invocation metadata, not full
prompt/response content.

Terraform tests assert the management selector, Model and AsyncInvoke data
selectors. Live acceptance must still confirm delivery and inspect actual events
for the client's supported invocation paths.
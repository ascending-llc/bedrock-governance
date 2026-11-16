# SCP Break-Glass Path

The Bedrock SCP (`bedrock_approved_models`) denies invocation of resources other
than approved application inference profiles. The SOW asks that documented
administrative and break-glass paths be preserved if required.

## Behavior

By default no principal is exempt. Set `break_glass_principal_arns` in the
management tfvars to exempt specific IAM principals from **both** deny
statements:

```hcl
break_glass_principal_arns = [
  "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_BedrockBreakGlass_*"
]
```

The exemption is an `ArnNotLike` condition on `aws:PrincipalArn`. In the
direct-foundation-model deny it sits beside the approved-profile condition under
the same operator, so the deny applies only when the request is neither routed
through an approved profile nor made by a break-glass principal.

## Rules for the principal patterns

- Use the **role ARN, not the session ARN**. For assumed roles `aws:PrincipalArn`
  is the role ARN without the session name.
- Identity Center role ARNs include the `aws-reserved/sso.amazonaws.com/` path
  and a generated suffix. The path can include a Region segment and
  may not, so the example uses a single `*` before `AWSReservedSSO_` to
  match both. Confirm the real ARN with `aws sts get-caller-identity` from the
  break-glass role in the target account before relying on the pattern.
- A bare `*` or an account root is rejected by validation.
- The setting is management mode only.
- An SCP exemption grants nothing. The principal still needs an IAM allow for
  the Bedrock actions, and should be separately monitored (CloudTrail data
  events record who invoked what).
- SCPs are limited to 5,120 characters. Keep the list short; check the size
  after adding entries.

## Governance

Each break-glass role should have a named owner, an approval process, session
duration limits, and an alert on use. Record the approved list with the customer
in the SOW acceptance notes. This repository does not create the role.

## Not covered by the SCP

The SCP restricts `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream`
and `bedrock:CreateModelInvocationJob`. `Converse`/`ConverseStream` and
`StartAsyncInvoke` authorize through `bedrock:InvokeModel` /
`...WithResponseStream`. `bedrock:InvokeModelWithBidirectionalStream` is not in
the SCP. Decide with the customer whether to add it before any client using
bidirectional streaming is approved.

The SCP matches only `bedrock:` actions on the `bedrock-runtime` endpoint. If a
client (for example Codex) calls the `bedrock-mantle` endpoint, confirm during
acceptance which IAM actions that path uses and whether the SCP governs it; do
not assume it does.

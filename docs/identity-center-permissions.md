# IAM Identity Center Inference Permissions

The child Terraform state outputs `identity_center_bedrock_inference_policy_json`.
It is a policy document for review and attachment to the customer's existing IAM
Identity Center permission set. Terraform does not create the permission set or
assign users/groups.

The generated policy:

- Allows `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` on the
  application inference profiles created from the child state's `model_sources`.
- Allows the underlying foundation-model resources only when
  `bedrock:InferenceProfileArn` identifies one of those approved profiles.
- Includes only the Codex system inference profile and project ARNs explicitly
  listed in `approved_codex_inference_profile_arns` and
  `approved_codex_project_arns`.
- Does not grant Bedrock administration, profile creation, or broad `bedrock:*`
  permissions.

`Converse` uses the `bedrock:InvokeModel` permission. `StartAsyncInvoke` also
requires `bedrock:InvokeModel`. The response-stream action is granted explicitly.
If a client requires bidirectional streaming, review and add that action
separately, then test it; it is not implicitly granted by this policy.

## Workflow

1. Apply the child state and collect its outputs.
2. Review the JSON policy:

   ```bash
   terraform output -raw identity_center_bedrock_inference_policy_json
   ```

3. Have the customer's IAM Identity Center administrator review and attach the
   policy to the existing permission set used by the pilot group.
4. Confirm the permission set still includes the customer's required sign-in
   and session permissions. This document covers Bedrock inference, not SSO
   setup or account assignments.
5. Test using an ordinary pilot user: approved profile calls should succeed;
   unapproved profiles/models should be denied by IAM/SCP.

For strict SCP mode, copy the exact approved AIP ARNs from
`terraform output -json inference_profile_arns` to
`approved_application_inference_profile_arns` in the management tfvars before
planning the management state.
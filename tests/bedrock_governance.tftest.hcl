mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:bedrock-governance-anomaly-alerts"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }
}

run "strict_management_scp_uses_exact_profiles" {
  command = plan

  variables {
    region                                          = "us-east-1"
    resource_name_prefix                            = "test-governance"
    deployment_mode                                 = "management"
    scp_target_ids                                  = ["123456789012"]
    enforce_approved_application_inference_profiles = true
    cost_allocation_tag_keys                        = ["Project", "Team"]
    approved_application_inference_profile_arns = [
      "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/aip-approved"
    ]
  }

  assert {
    condition = contains(
      jsondecode(output.bedrock_approved_models_scp_json).Statement[0].NotResource,
      "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/aip-approved"
    )
    error_message = "The strict SCP must exempt the explicitly approved AIP ARN."
  }

  assert {
    condition = !contains(
      jsondecode(output.bedrock_approved_models_scp_json).Statement[0].NotResource,
      "arn:aws:bedrock:*:$${aws:PrincipalAccount}:application-inference-profile/*"
    )
    error_message = "The strict SCP must not allow every same-account AIP."
  }

  assert {
    condition = contains(
      jsondecode(output.bedrock_approved_models_scp_json).Statement[1].Condition.ArnNotLike["bedrock:InferenceProfileArn"],
      "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/aip-approved"
    )
    error_message = "The direct-model deny must exempt only approved AIP request contexts."
  }

  assert {
    condition     = contains(output.scp_policy_attachment_target_ids, "123456789012")
    error_message = "The SCP attachment must target only the configured sandbox account."
  }

  assert {
    condition     = output.cost_allocation_tag_status["Team"] == "Active"
    error_message = "Configured cost allocation tag keys must be activated."
  }

  assert {
    condition     = output.cost_allocation_tag_status["Project"] == "Active"
    error_message = "Configured project cost allocation tags must be activated."
  }
}

run "legacy_management_mode_keeps_wildcard_compatibility" {
  command = plan

  variables {
    region               = "us-east-1"
    resource_name_prefix = "legacy-governance"
    deployment_mode      = "management"
    scp_target_ids       = ["123456789012"]
  }

  assert {
    condition = contains(
      jsondecode(output.bedrock_approved_models_scp_json).Statement[0].NotResource,
      "arn:aws:bedrock:*:$${aws:PrincipalAccount}:application-inference-profile/*"
    )
    error_message = "Legacy mode must preserve the prior same-account AIP behavior until explicitly migrated."
  }
}

run "strict_management_rejects_wildcard_profile_arns" {
  command = plan

  variables {
    region                                          = "us-east-1"
    resource_name_prefix                            = "test-governance"
    deployment_mode                                 = "management"
    scp_target_ids                                  = ["123456789012"]
    enforce_approved_application_inference_profiles = true
    approved_application_inference_profile_arns = [
      "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/*"
    ]
  }

  expect_failures = [var.approved_application_inference_profile_arns]
}

run "required_alarm_notification_rejects_missing_target" {
  command = plan

  variables {
    region                     = "us-east-1"
    resource_name_prefix       = "notification-test"
    deployment_mode            = "child"
    require_alarm_notification = true
    model_sources = [
      {
        name     = "sonnet"
        model_id = "us.anthropic.claude-sonnet-5-5"
      }
    ]
  }

  expect_failures = [var.require_alarm_notification]
}

run "alarm_notification_rejects_two_targets" {
  command = plan

  variables {
    region                     = "us-east-1"
    resource_name_prefix       = "notification-test"
    deployment_mode            = "child"
    alarm_email                = "ops@example.com"
    alarm_sns_topic_arn        = "arn:aws:sns:us-east-1:123456789012:alerts"
    require_alarm_notification = true
    model_sources = [
      {
        name     = "sonnet"
        model_id = "us.anthropic.claude-sonnet-5-5"
      }
    ]
  }

  expect_failures = [var.alarm_sns_topic_arn]
}

run "child_profiles_have_standard_tags_and_identity_policy" {
  command = apply

  variables {
    region                     = "us-east-1"
    resource_name_prefix       = "sandbox-governance"
    deployment_mode            = "child"
    alarm_email                = "ops@example.com"
    require_alarm_notification = true
    model_sources = [
      {
        name     = "sonnet"
        model_id = "us.anthropic.claude-sonnet-5-5"
        team     = "sandbox"
      }
    ]
    approved_codex_inference_profile_arns = [
      "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.openai.gpt-6.1-sol"
    ]
    approved_codex_project_arns = [
      "arn:aws:bedrock:us-east-1:123456789012:project/default"
    ]
  }

  assert {
    condition     = output.inference_profile_tags["sonnet"]["ManagedBy"] == "Terraform"
    error_message = "AIPs must receive the standard ManagedBy tag."
  }

  assert {
    condition     = output.inference_profile_tags["sonnet"]["Project"] == "bedrock-governance"
    error_message = "AIPs must receive the standard Project tag."
  }

  assert {
    condition     = output.inference_profile_tags["sonnet"]["Team"] == "sandbox"
    error_message = "AIPs must preserve the configured Team tag."
  }

  assert {
    condition     = output.anomaly_alarm_tags["sonnet__InputTokenCount"]["DeploymentMode"] == "child"
    error_message = "Token alarms must receive the standard DeploymentMode tag."
  }

  assert {
    condition     = length(output.anomaly_alarm_actions["sonnet__InputTokenCount"]) > 0
    error_message = "A required notification target must be attached to token alarms."
  }

  assert {
    condition     = output.audit_bucket_tags["ManagedBy"] == "Terraform"
    error_message = "The audit bucket must receive the standard ManagedBy tag."
  }

  assert {
    condition     = strcontains(output.identity_center_bedrock_inference_policy_json, "us.openai.gpt-6.1-sol")
    error_message = "The Identity Center policy must include only the explicitly configured Codex profile."
  }

  assert {
    condition     = strcontains(output.identity_center_bedrock_inference_policy_json, "project/default")
    error_message = "The Identity Center policy must include the explicitly configured Codex project."
  }

  assert {
    condition = contains(
      [for statement in jsondecode(output.identity_center_bedrock_inference_policy_json).Statement : statement.Sid],
      "InvokeRoutedFoundationModelsOnlyThroughApprovedProfiles"
    )
    error_message = "The Identity Center policy must condition foundation-model access on an approved inference profile."
  }

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.identity_center_bedrock_inference_policy_json).Statement : [
        for action in statement.Action : action != "bedrock:*"
      ]
    ]))
    error_message = "The Identity Center policy must not grant broad bedrock:* access."
  }

  assert {
    condition = contains(
      [for selector in output.cloudtrail_advanced_event_selectors : selector.name],
      "ManagementEvents"
    )
    error_message = "CloudTrail must retain management event coverage for synchronous and conversational Runtime APIs."
  }

  assert {
    condition = contains(
      flatten([
        for selector in output.cloudtrail_advanced_event_selectors : [
          for field_selector in selector.field_selectors : field_selector.equals
          if field_selector.field == "eventSource"
        ]
      ]),
      "bedrock.amazonaws.com"
    )
    error_message = "Management events should be filtered to the Bedrock event source."
  }

  assert {
    condition = contains(
      flatten([
        for selector in output.cloudtrail_advanced_event_selectors : [
          for field_selector in selector.field_selectors : field_selector.equals
          if field_selector.field == "resources.type"
        ]
      ]),
      "AWS::Bedrock::Model"
    )
    error_message = "CloudTrail must select Bedrock Model data events."
  }

  assert {
    condition = contains(
      flatten([
        for selector in output.cloudtrail_advanced_event_selectors : [
          for field_selector in selector.field_selectors : field_selector.equals
          if field_selector.field == "resources.type"
        ]
      ]),
      "AWS::Bedrock::AsyncInvoke"
    )
    error_message = "CloudTrail must select Bedrock AsyncInvoke data events."
  }
}

run "existing_sns_topic_receives_alarm_actions" {
  command = apply

  variables {
    region                     = "us-east-1"
    resource_name_prefix       = "sandbox-governance"
    deployment_mode            = "child"
    alarm_sns_topic_arn        = "arn:aws:sns:us-east-1:123456789012:alerts"
    require_alarm_notification = true
    model_sources = [
      {
        name     = "sonnet"
        model_id = "us.anthropic.claude-sonnet-5-5"
      }
    ]
  }

  assert {
    condition     = contains(output.anomaly_alarm_actions["sonnet__InputTokenCount"], "arn:aws:sns:us-east-1:123456789012:alerts")
    error_message = "An existing SNS target must be attached to each anomaly alarm."
  }
}
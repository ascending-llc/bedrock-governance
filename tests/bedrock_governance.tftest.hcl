mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:bedrock-governance-anomaly-alerts"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-role"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock-policy"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:mock-function"
    }
  }

  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      arn = "arn:aws:events:us-east-1:123456789012:rule/mock-rule"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/mock"
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
      "arn:aws:bedrock:us-east-1:123456789012:inference-profile/global.openai.gpt-6.2-sol",
      "arn:aws:bedrock:us-east-1:123456789012:inference-profile/global.openai.gpt-6.2-astra"
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
    condition     = output.inference_profile_tags["sonnet"]["Model"] == "sonnet"
    error_message = "AIPs must carry a Model tag so cost can be grouped per model."
  }

  assert {
    condition     = output.anomaly_alarm_tags["sonnet__InputTokenCount"]["Model"] == "sonnet"
    error_message = "Token alarms must carry the Model tag."
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
    condition = alltrue([
      strcontains(output.identity_center_bedrock_inference_policy_json, "global.openai.gpt-6.2-sol"),
      strcontains(output.identity_center_bedrock_inference_policy_json, "global.openai.gpt-6.2-astra"),
      !strcontains(output.identity_center_bedrock_inference_policy_json, "us.openai.")
    ])
    error_message = "The Identity Center policy must include only the explicitly configured Global Codex profiles."
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
    condition = contains(
      [for statement in jsondecode(output.identity_center_bedrock_inference_policy_json).Statement : statement.Sid],
      "ResolveApprovedApplicationInferenceProfiles"
    )
    error_message = "The Identity Center policy must allow GetInferenceProfile on the approved AIPs for Claude Code."
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
    error_message = "CloudTrail must retain management event coverage; InvokeModel*, Converse* and ListAsyncInvokes are recorded as management events."
  }

  assert {
    condition = contains(
      flatten([
        for selector in output.cloudtrail_advanced_event_selectors : [
          for field_selector in selector.field_selectors : field_selector.equals
          if selector.name == "ManagementEvents" && field_selector.field == "eventCategory"
        ]
      ]),
      "Management"
    )
    error_message = "CloudTrail must select management events; the Bedrock runtime invocation APIs (InvokeModel*, Converse*) are management events."
  }

  assert {
    condition = alltrue([
      for selector in output.cloudtrail_advanced_event_selectors : selector.name != "ManagementEvents" || alltrue([
        for field_selector in selector.field_selectors : field_selector.field != "eventSource"
      ])
    ])
    error_message = "The current trail configuration intentionally captures all management event sources; verify the positive eventSource filter against CloudTrail before narrowing it."
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
    error_message = "CloudTrail must select Bedrock Model data events (InvokeModelWithBidirectionalStream, StartAsyncInvoke, GetAsyncInvoke)."
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
    error_message = "CloudTrail must select Bedrock AsyncInvoke data events (StartAsyncInvoke, GetAsyncInvoke, InvokeModelWithBidirectionalStream)."
  }
}

run "anomaly_alarms_watch_profile_id_dimension" {
  command = plan

  variables {
    region               = "us-east-1"
    resource_name_prefix = "test-governance"
    deployment_mode      = "child"
    model_sources = [
      { name = "sonnet", model_id = "us.anthropic.claude-sonnet-5-5" }
    ]
  }

  assert {
    condition = alltrue([
      for key, value in output.anomaly_alarm_metric_model_ids :
      value == output.inference_profile_ids["sonnet"] && !startswith(value, "arn:")
    ])
    error_message = "CloudWatch publishes application-profile metrics under the profile ID, so alarms must use it as the ModelId dimension, not the ARN."
  }
}

run "bedrock_data_selectors_exclude_management_recorded_invocations" {
  command = plan

  variables {
    region               = "us-east-1"
    resource_name_prefix = "test-governance"
    deployment_mode      = "child"
    model_sources = [
      { name = "sonnet", model_id = "us.anthropic.claude-sonnet-5-5" }
    ]
  }

  assert {
    condition = alltrue([
      for selector in output.cloudtrail_advanced_event_selectors : alltrue([
        for op in ["Converse", "ConverseStream", "InvokeModel", "InvokeModelWithResponseStream"] :
        contains(flatten([
          for field_selector in selector.field_selectors : field_selector.not_equals
          if field_selector.field == "eventName"
        ]), op)
      ])
      if startswith(selector.name, "BedrockModel") || startswith(selector.name, "BedrockAsync")
    ])
    error_message = "Bedrock data selectors must exclude the invocation APIs the management selector already records, so each call is logged once."
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

run "scp_keeps_codex_exceptions_by_default" {
  command = plan

  variables {
    region               = "us-east-1"
    resource_name_prefix = "test-governance"
    deployment_mode      = "management"
    scp_target_ids       = ["123456789012"]
  }

  assert {
    condition = alltrue([
      strcontains(output.bedrock_approved_models_scp_json, "global.openai.*"),
      strcontains(output.bedrock_approved_models_scp_json, "project/default")
    ])
    error_message = "The SCP must keep the Codex exceptions unless allow_codex_scp_exceptions is false."
  }
}

run "scp_can_drop_codex_exceptions" {
  command = plan

  variables {
    region                     = "us-east-1"
    resource_name_prefix       = "test-governance"
    deployment_mode            = "management"
    scp_target_ids             = ["123456789012"]
    allow_codex_scp_exceptions = false
  }

  assert {
    condition = !anytrue([
      strcontains(output.bedrock_approved_models_scp_json, "openai"),
      strcontains(output.bedrock_approved_models_scp_json, "project/default")
    ])
    error_message = "With allow_codex_scp_exceptions = false the SCP must not mention the Codex exceptions."
  }
}

run "scp_without_break_glass_has_no_principal_condition" {
  command = plan

  variables {
    region               = "us-east-1"
    resource_name_prefix = "legacy-governance"
    deployment_mode      = "management"
    scp_target_ids       = ["123456789012"]
  }

  assert {
    condition     = !contains(keys(jsondecode(output.bedrock_approved_models_scp_json).Statement[0]), "Condition")
    error_message = "With no break-glass principals the first deny statement must not carry a Condition."
  }

  assert {
    condition     = !contains(keys(jsondecode(output.bedrock_approved_models_scp_json).Statement[1].Condition.ArnNotLike), "aws:PrincipalArn")
    error_message = "With no break-glass principals the SCP must not reference aws:PrincipalArn."
  }
}

run "scp_break_glass_principal_is_exempted_from_both_denies" {
  command = plan

  variables {
    region               = "us-east-1"
    resource_name_prefix = "test-governance"
    deployment_mode      = "management"
    scp_target_ids       = ["123456789012"]
    break_glass_principal_arns = [
      "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_BedrockBreakGlass_*"
    ]
  }

  assert {
    condition = contains(
      jsondecode(output.bedrock_approved_models_scp_json).Statement[0].Condition.ArnNotLike["aws:PrincipalArn"],
      "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_BedrockBreakGlass_*"
    )
    error_message = "The break-glass principal must be exempted from the resource-type deny."
  }

  assert {
    condition = contains(
      jsondecode(output.bedrock_approved_models_scp_json).Statement[1].Condition.ArnNotLike["aws:PrincipalArn"],
      "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_BedrockBreakGlass_*"
    )
    error_message = "The break-glass principal must be exempted from the direct-foundation-model deny."
  }

  assert {
    condition     = contains(keys(jsondecode(output.bedrock_approved_models_scp_json).Statement[1].Condition.ArnNotLike), "bedrock:InferenceProfileArn")
    error_message = "Adding a break-glass principal must not remove the approved-profile exemption."
  }
}

run "break_glass_rejects_bare_wildcard" {
  command = plan

  variables {
    region                     = "us-east-1"
    resource_name_prefix       = "test-governance"
    deployment_mode            = "management"
    scp_target_ids             = ["123456789012"]
    break_glass_principal_arns = ["*"]
  }

  expect_failures = [var.break_glass_principal_arns]
}

run "break_glass_rejected_in_child_mode" {
  command = plan

  variables {
    region                     = "us-east-1"
    resource_name_prefix       = "test-governance"
    deployment_mode            = "child"
    break_glass_principal_arns = ["arn:aws:iam::123456789012:role/BreakGlass"]
    model_sources = [
      { name = "sonnet", model_id = "us.anthropic.claude-sonnet-5-5" }
    ]
  }

  expect_failures = [var.break_glass_principal_arns]
}

run "audit_bucket_retention_defaults_to_30_days" {
  command = plan

  variables {
    region               = "us-east-1"
    resource_name_prefix = "test-governance"
    deployment_mode      = "child"
    model_sources = [
      { name = "sonnet", model_id = "us.anthropic.claude-sonnet-5-5" }
    ]
  }

  assert {
    condition     = output.audit_log_expiration_days == 30
    error_message = "Audit log retention must keep its existing 30 day default unless explicitly overridden."
  }
}

run "mantle_deny_is_opt_in" {
  command = plan

  variables {
    region               = "us-east-1"
    resource_name_prefix = "test-governance"
    deployment_mode      = "management"
    scp_target_ids       = ["123456789012"]
  }

  assert {
    condition     = length(jsondecode(output.bedrock_approved_models_scp_json).Statement) == 2
    error_message = "The bedrock-mantle deny must be off by default."
  }
}

run "mantle_deny_can_be_enabled_with_break_glass" {
  command = plan

  variables {
    region                        = "us-east-1"
    resource_name_prefix          = "test-governance"
    deployment_mode               = "management"
    scp_target_ids                = ["123456789012"]
    deny_bedrock_mantle_inference = true
    break_glass_principal_arns    = ["arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_BedrockBreakGlass_*"]
  }

  assert {
    condition = contains(
      jsondecode(output.bedrock_approved_models_scp_json).Statement[2].Action,
      "bedrock-mantle:CreateInference"
    )
    error_message = "The SCP must deny bedrock-mantle:CreateInference when enabled."
  }

  assert {
    condition = contains(
      jsondecode(output.bedrock_approved_models_scp_json).Statement[2].Condition.ArnNotLike["aws:PrincipalArn"],
      "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_BedrockBreakGlass_*"
    )
    error_message = "The break-glass principal must be exempted from the bedrock-mantle deny."
  }
}

run "mantle_data_events_are_opt_in" {
  command = plan

  variables {
    region               = "us-east-1"
    resource_name_prefix = "test-governance"
    deployment_mode      = "child"
    model_sources = [
      { name = "sonnet", model_id = "us.anthropic.claude-sonnet-5-5" }
    ]
  }

  assert {
    condition     = !contains([for selector in output.cloudtrail_advanced_event_selectors : selector.name], "BedrockMantleProjectDataEvents")
    error_message = "The bedrock-mantle data selector must be off by default."
  }
}

run "mantle_data_events_can_be_enabled" {
  command = plan

  variables {
    region                            = "us-east-1"
    resource_name_prefix              = "test-governance"
    deployment_mode                   = "child"
    enable_bedrock_mantle_data_events = true
    model_sources = [
      { name = "sonnet", model_id = "us.anthropic.claude-sonnet-5-5" }
    ]
  }

  assert {
    condition = contains(
      flatten([
        for selector in output.cloudtrail_advanced_event_selectors : [
          for field in selector.field_selectors : field.equals if field.field == "resources.type"
        ]
      ]),
      "AWS::BedrockMantle::Project"
    )
    error_message = "Enabling mantle data events must add the AWS::BedrockMantle::Project data selector."
  }

  assert {
    condition     = length(output.cloudtrail_advanced_event_selectors) == 4
    error_message = "Enabling mantle data events must add exactly one selector to the existing three."
  }
}

run "audit_bucket_retention_is_configurable" {
  command = plan

  variables {
    region                   = "us-east-1"
    resource_name_prefix     = "test-governance"
    deployment_mode          = "child"
    audit_log_retention_days = 400
    model_sources = [
      { name = "sonnet", model_id = "us.anthropic.claude-sonnet-5-5" }
    ]
  }

  assert {
    condition     = output.audit_log_expiration_days == 400
    error_message = "Audit log expiration must follow audit_log_retention_days."
  }
}

run "audit_retention_rejects_under_30_days" {
  command = plan

  variables {
    region                   = "us-east-1"
    resource_name_prefix     = "test-governance"
    deployment_mode          = "child"
    audit_log_retention_days = 7
    model_sources = [
      { name = "sonnet", model_id = "us.anthropic.claude-sonnet-5-5" }
    ]
  }

  expect_failures = [var.audit_log_retention_days]
}

run "cost_limits_and_alerts_are_per_profile" {
  command = apply

  variables {
    region                       = "us-east-1"
    resource_name_prefix         = "cost-test"
    deployment_mode              = "child"
    alarm_email                  = "ops@example.com"
    cost_alert_threshold_percent = 80
    model_sources = [
      {
        name                 = "sonnet"
        model_id             = "us.anthropic.claude-sonnet-5-5"
        pricing              = { input_per_million = 3, output_per_million = 15 }
        daily_cost_limit_usd = 50
      },
      {
        name                 = "haiku"
        model_id             = "us.anthropic.claude-haiku-5-5"
        pricing              = { input_per_million = 0.11, output_per_million = 0.55 }
        daily_cost_alert_usd = 5
      },
      {
        name     = "opus"
        model_id = "us.anthropic.claude-opus-5-5"
      }
    ]
  }

  assert {
    condition     = output.cost_daily_limits_usd == { sonnet = 50 }
    error_message = "Only profiles that set daily_cost_limit_usd may have a limit."
  }

  assert {
    condition     = output.cost_alert_thresholds_usd == { sonnet = 40, haiku = 5 }
    error_message = "A limit alerts at cost_alert_threshold_percent of the limit, an explicit alert wins, and unpriced profiles get no alert."
  }

  assert {
    condition     = keys(output.cost_limit_alarm_names) == ["sonnet"]
    error_message = "Only the profile with a limit may get a limit alarm."
  }

  assert {
    condition     = output.cost_alert_alarm_names["haiku"] == "cost-test-haiku-daily-cost-alert"
    error_message = "Each priced profile with a threshold must get its own cost alert alarm."
  }

  assert {
    condition     = alltrue([for key, actions in output.cost_alert_alarm_actions : length(actions) > 0])
    error_message = "Cost alerts must notify the configured target."
  }

  assert {
    condition     = output.cost_limit_block_policy_name == "cost-test-bedrock-cost-limit-block"
    error_message = "The block policy must be exposed by name for Identity Center customer managed policy references."
  }

  assert {
    condition     = output.cost_enforcer_function_name == "cost-test-bedrock-cost-limit-enforcer"
    error_message = "A priced profile must deploy the cost enforcer."
  }
}

run "cost_alert_percent_is_configurable" {
  command = plan

  variables {
    region                       = "us-east-1"
    resource_name_prefix         = "cost-test"
    deployment_mode              = "child"
    cost_alert_threshold_percent = 50
    model_sources = [
      {
        name                 = "sonnet"
        model_id             = "us.anthropic.claude-sonnet-5-5"
        pricing              = { input_per_million = 3, output_per_million = 15 }
        daily_cost_limit_usd = 50
      }
    ]
  }

  assert {
    condition     = output.cost_alert_thresholds_usd["sonnet"] == 25
    error_message = "The implicit alert threshold must follow cost_alert_threshold_percent."
  }
}

run "cost_control_is_off_without_pricing" {
  command = plan

  variables {
    region               = "us-east-1"
    resource_name_prefix = "cost-test"
    deployment_mode      = "child"
    model_sources = [
      { name = "sonnet", model_id = "us.anthropic.claude-sonnet-5-5" }
    ]
  }

  assert {
    condition = alltrue([
      output.cost_enforcer_function_name == null,
      output.cost_limit_block_policy_arn == null,
      length(output.cost_alert_alarm_names) == 0,
      length(output.cost_limit_alarm_names) == 0
    ])
    error_message = "Existing deployments without pricing must not gain cost-control resources."
  }
}

run "cost_limit_without_pricing_is_rejected" {
  command = plan

  variables {
    region               = "us-east-1"
    resource_name_prefix = "cost-test"
    deployment_mode      = "child"
    model_sources = [
      { name = "sonnet", model_id = "us.anthropic.claude-sonnet-5-5", daily_cost_limit_usd = 50 }
    ]
  }

  expect_failures = [var.model_sources]
}

run "non_positive_cost_limit_is_rejected" {
  command = plan

  variables {
    region               = "us-east-1"
    resource_name_prefix = "cost-test"
    deployment_mode      = "child"
    model_sources = [
      {
        name                 = "sonnet"
        model_id             = "us.anthropic.claude-sonnet-5-5"
        pricing              = { input_per_million = 3, output_per_million = 15 }
        daily_cost_limit_usd = 0
      }
    ]
  }

  expect_failures = [var.model_sources]
}

run "cost_check_interval_is_bounded" {
  command = plan

  variables {
    region                      = "us-east-1"
    resource_name_prefix        = "cost-test"
    deployment_mode             = "child"
    cost_check_interval_minutes = 0
    model_sources = [
      { name = "sonnet", model_id = "us.anthropic.claude-sonnet-5-5" }
    ]
  }

  expect_failures = [var.cost_check_interval_minutes]
}

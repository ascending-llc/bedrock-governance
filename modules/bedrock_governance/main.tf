data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  is_child      = var.deployment_mode == "child"
  is_management = var.deployment_mode == "management"

  common_tags = {
    Project        = "bedrock-governance"
    ManagedBy      = "Terraform"
    DeploymentMode = var.deployment_mode
  }

  # Runtime invocations already recorded by the management selector; excluded from the data selectors so each call is logged once.
  bedrock_management_recorded_operations = ["Converse", "ConverseStream", "InvokeModel", "InvokeModelWithResponseStream"]

  cloudtrail_advanced_event_selectors = concat([
    {
      name = "ManagementEvents"
      field_selectors = [
        { field = "eventCategory", equals = ["Management"] }
      ]
    },
    {
      name = "BedrockModelDataEvents"
      field_selectors = [
        { field = "eventCategory", equals = ["Data"] },
        { field = "resources.type", equals = ["AWS::Bedrock::Model"] },
        { field = "eventName", not_equals = local.bedrock_management_recorded_operations }
      ]
    },
    {
      name = "BedrockAsyncInvokeDataEvents"
      field_selectors = [
        { field = "eventCategory", equals = ["Data"] },
        { field = "resources.type", equals = ["AWS::Bedrock::AsyncInvoke"] },
        { field = "eventName", not_equals = local.bedrock_management_recorded_operations }
      ]
    }
    ], var.enable_bedrock_mantle_data_events ? [
    {
      name = "BedrockMantleProjectDataEvents"
      field_selectors = [
        { field = "eventCategory", equals = ["Data"] },
        { field = "resources.type", equals = ["AWS::BedrockMantle::Project"] }
      ]
    }
  ] : [])

  # Constructed (not referenced from aws_cloudtrail.bedrock) to avoid a bucket-policy <-> trail cycle.
  cloudtrail_arn = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.resource_name_prefix}-bedrock-audit"

  child_models = local.is_child ? {
    for m in var.model_sources : m.name => m
  } : {}

  model_source_arns = {
    for name, model in local.child_models :
    name => (
      can(regex("^(us|eu|apac|global|us-gov)\\.", model.model_id))
      ? "arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:inference-profile/${model.model_id}"
      : "arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.name}::foundation-model/${model.model_id}"
    )
  }

  # Temporary: Codex does not support AIP ARNs, so the global OpenAI system inference profiles are allowed without an AIP.
  direct_access_inference_profile_arns = var.allow_codex_scp_exceptions ? [
    "arn:${data.aws_partition.current.partition}:bedrock:*:$${aws:PrincipalAccount}:inference-profile/global.openai.*"
  ] : []

  # Temporary: the Responses API on bedrock-runtime also authorizes the account's default project.
  direct_access_project_arns = var.allow_codex_scp_exceptions ? [
    "arn:${data.aws_partition.current.partition}:bedrock:*:$${aws:PrincipalAccount}:project/default"
  ] : []

  application_inference_profile_arns = var.enforce_approved_application_inference_profiles ? var.approved_application_inference_profile_arns : [
    "arn:${data.aws_partition.current.partition}:bedrock:*:$${aws:PrincipalAccount}:application-inference-profile/*"
  ]

  child_application_inference_profile_arns = [
    for profile in values(aws_bedrock_inference_profile.this) : profile.arn
  ]

  employee_inference_profile_arns = concat(
    local.child_application_inference_profile_arns,
    var.approved_codex_inference_profile_arns
  )

  employee_inference_actions = [
    "bedrock:InvokeModel",
    "bedrock:InvokeModelWithResponseStream"
  ]

  anomaly_notification_topic_arn = var.alarm_email != null ? try(aws_sns_topic.anomaly_alerts[0].arn, null) : var.alarm_sns_topic_arn

  identity_center_bedrock_inference_policy_json = local.is_child ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      for statement in [
        {
          Sid      = "InvokeApprovedInferenceProfiles"
          Effect   = "Allow"
          Action   = local.employee_inference_actions
          Resource = local.employee_inference_profile_arns
        },
        {
          # Claude Code resolves an AIP to its backing model; without this it retries once per new model.
          Sid      = "ResolveApprovedApplicationInferenceProfiles"
          Effect   = "Allow"
          Action   = ["bedrock:GetInferenceProfile"]
          Resource = local.child_application_inference_profile_arns
        },
        {
          Sid      = "InvokeRoutedFoundationModelsOnlyThroughApprovedProfiles"
          Effect   = "Allow"
          Action   = local.employee_inference_actions
          Resource = ["arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/*"]
          Condition = {
            ArnEquals = {
              "bedrock:InferenceProfileArn" = local.employee_inference_profile_arns
            }
          }
        },
        {
          Sid      = "InvokeApprovedCodexProjects"
          Effect   = "Allow"
          Action   = local.employee_inference_actions
          Resource = var.approved_codex_project_arns
        }
      ] : statement if statement.Sid == "InvokeApprovedCodexProjects" ? length(var.approved_codex_project_arns) > 0 : length(local.employee_inference_profile_arns) > 0
    ]
  }) : null

  # Optional break-glass exemption for the SCP deny statements. Built with a for-expression so the
  # Condition key is omitted entirely (not null) when no principals are configured.
  scp_break_glass_principal_condition = {
    for key, value in { "aws:PrincipalArn" = var.break_glass_principal_arns } : key => value
    if length(var.break_glass_principal_arns) > 0
  }

  scp_all_resources_deny_condition = {
    for key, value in { Condition = { ArnNotLike = local.scp_break_glass_principal_condition } } : key => value
    if length(var.break_glass_principal_arns) > 0
  }

  anomaly_alarm_entries = merge([
    for key, model in local.child_models : {
      "${key}__InputTokenCount" = {
        profile_name = model.name
        metric_name  = "InputTokenCount"
        suffix       = "input-token-anomaly"
        team         = model.team
      }
      "${key}__OutputTokenCount" = {
        profile_name = model.name
        metric_name  = "OutputTokenCount"
        suffix       = "output-token-anomaly"
        team         = model.team
      }
    }
  ]...)
}

resource "aws_bedrock_inference_profile" "this" {
  for_each = local.child_models

  name        = "${var.resource_name_prefix}-${each.value.name}"
  description = "Application inference profile for ${each.value.name}"

  model_source {
    copy_from = local.model_source_arns[each.key]
  }

  tags = merge(local.common_tags, { Model = each.value.name }, each.value.team != null ? { Team = each.value.team } : {})
}

resource "aws_sns_topic" "anomaly_alerts" {
  count = local.is_child && var.alarm_email != null ? 1 : 0

  name = "${var.resource_name_prefix}-bedrock-anomaly-alerts"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "anomaly_alerts_email" {
  count = local.is_child && var.alarm_email != null ? 1 : 0

  topic_arn = aws_sns_topic.anomaly_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_ce_cost_allocation_tag" "this" {
  for_each = local.is_management ? var.cost_allocation_tag_keys : toset([])

  tag_key = each.value
  status  = "Active"
}

resource "aws_cloudwatch_metric_alarm" "bedrock_anomaly" {
  for_each = local.anomaly_alarm_entries

  alarm_name          = "${var.resource_name_prefix}-${each.value.profile_name}-${each.value.suffix}"
  alarm_description   = "${each.value.metric_name} anomaly for AIP ${each.value.profile_name}"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  threshold_metric_id = "ad1"
  alarm_actions       = local.anomaly_notification_topic_arn != null ? [local.anomaly_notification_topic_arn] : []
  ok_actions          = local.anomaly_notification_topic_arn != null ? [local.anomaly_notification_topic_arn] : []

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    period      = 3600
    return_data = true
  }

  metric_query {
    id          = "m1"
    return_data = true
    metric {
      namespace   = "AWS/Bedrock"
      metric_name = each.value.metric_name
      period      = 3600
      stat        = "Sum"
      dimensions = {
        # CloudWatch publishes application-profile metrics under the profile ID, not the ARN.
        ModelId = aws_bedrock_inference_profile.this[split("__", each.key)[0]].id
      }
    }
  }

  tags = merge(local.common_tags, { Model = each.value.profile_name }, each.value.team != null ? { Team = each.value.team } : {})
}

resource "aws_s3_bucket" "bedrock_audit" {
  count = local.is_child ? 1 : 0

  bucket = "${var.resource_name_prefix}-bedrock-audit-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "bedrock_audit" {
  count = local.is_child ? 1 : 0

  bucket = aws_s3_bucket.bedrock_audit[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "bedrock_audit" {
  count = local.is_child ? 1 : 0

  bucket                  = aws_s3_bucket.bedrock_audit[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bedrock_audit" {
  count = local.is_child ? 1 : 0

  bucket = aws_s3_bucket.bedrock_audit[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "bedrock_audit" {
  count = local.is_child ? 1 : 0

  bucket = aws_s3_bucket.bedrock_audit[0].id

  rule {
    id     = "retain-${var.audit_log_retention_days}-days"
    status = "Enabled"

    filter {}

    expiration {
      days = var.audit_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.audit_log_retention_days
    }
  }
}

data "aws_iam_policy_document" "bedrock_audit_bucket" {
  count = local.is_child ? 1 : 0

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.bedrock_audit[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.bedrock_audit[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    # Confused-deputy protection: only this account's Bedrock audit trail may write.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.bedrock_audit[0].arn,
      "${aws_s3_bucket.bedrock_audit[0].arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "bedrock_audit" {
  count = local.is_child ? 1 : 0

  bucket = aws_s3_bucket.bedrock_audit[0].id
  policy = data.aws_iam_policy_document.bedrock_audit_bucket[0].json
}

resource "aws_cloudtrail" "bedrock" {
  count = local.is_child ? 1 : 0

  name                          = "${var.resource_name_prefix}-bedrock-audit"
  s3_bucket_name                = aws_s3_bucket.bedrock_audit[0].bucket
  is_multi_region_trail         = true
  enable_logging                = true
  enable_log_file_validation    = true
  include_global_service_events = true

  dynamic "advanced_event_selector" {
    for_each = local.cloudtrail_advanced_event_selectors

    content {
      name = advanced_event_selector.value.name

      dynamic "field_selector" {
        for_each = advanced_event_selector.value.field_selectors

        content {
          field      = field_selector.value.field
          equals     = try(field_selector.value.equals, null)
          not_equals = try(field_selector.value.not_equals, null)
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_policy.bedrock_audit]

  tags = local.common_tags
}

resource "aws_organizations_policy" "bedrock_approved_models" {
  count = local.is_management ? 1 : 0

  name        = "${var.resource_name_prefix}-bedrock-approved-models"
  description = "Deny Bedrock invocation APIs unless requests use approved child-account application inference profiles."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      merge({
        Sid    = "DenyNonAIPNonFMResources"
        Effect = "Deny"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:CreateModelInvocationJob"
        ]
        NotResource = concat(
          local.application_inference_profile_arns,
          ["arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/*"],
          local.direct_access_inference_profile_arns,
          local.direct_access_project_arns
        )
      }, local.scp_all_resources_deny_condition),
      {
        Sid    = "DenyDirectFoundationModelInvocations"
        Effect = "Deny"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:CreateModelInvocationJob"
        ]
        NotResource = concat(
          local.application_inference_profile_arns,
          [
            for pattern in var.direct_access_model_id_patterns :
            "arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/${pattern}"
          ],
          local.direct_access_inference_profile_arns,
          local.direct_access_project_arns
        )
        Condition = {
          # Multiple keys under one operator are ANDed: the deny applies only when the request is
          # neither via an approved profile NOR made by a break-glass principal.
          ArnNotLike = merge(
            {
              "bedrock:InferenceProfileArn" = concat(
                local.application_inference_profile_arns,
                local.direct_access_inference_profile_arns
              )
            },
            local.scp_break_glass_principal_condition
          )
        }
      }
      ], var.deny_bedrock_mantle_inference ? [
      merge({
        Sid      = "DenyBedrockMantleInference"
        Effect   = "Deny"
        Action   = ["bedrock-mantle:CreateInference"]
        Resource = "*"
      }, local.scp_all_resources_deny_condition)
    ] : [])
  })

  tags = local.common_tags
}

resource "aws_organizations_policy_attachment" "bedrock_approved_models" {
  for_each = local.is_management ? toset(var.scp_target_ids) : toset([])

  policy_id = aws_organizations_policy.bedrock_approved_models[0].id
  target_id = each.value
}

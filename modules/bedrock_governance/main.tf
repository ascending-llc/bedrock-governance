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

  cloudtrail_advanced_event_selectors = [
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
        { field = "resources.type", equals = ["AWS::Bedrock::Model"] }
      ]
    },
    {
      name = "BedrockAsyncInvokeDataEvents"
      field_selectors = [
        { field = "eventCategory", equals = ["Data"] },
        { field = "resources.type", equals = ["AWS::Bedrock::AsyncInvoke"] }
      ]
    }
  ]

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
  direct_access_inference_profile_arns = [
    "arn:${data.aws_partition.current.partition}:bedrock:*:$${aws:PrincipalAccount}:inference-profile/global.openai.*"
  ]

  # Temporary: the Responses API on bedrock-runtime also authorizes the account's default project.
  direct_access_project_arns = [
    "arn:${data.aws_partition.current.partition}:bedrock:*:$${aws:PrincipalAccount}:project/default"
  ]

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

  tags = merge(local.common_tags, each.value.team != null ? { Team = each.value.team } : {})
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
        ModelId = aws_bedrock_inference_profile.this[split("__", each.key)[0]].arn
      }
    }
  }

  tags = merge(local.common_tags, each.value.team != null ? { Team = each.value.team } : {})
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
    id     = "retain-30-days"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
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
          field  = field_selector.value.field
          equals = field_selector.value.equals
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
    Statement = [
      {
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
      },
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
          ArnNotLike = {
            "bedrock:InferenceProfileArn" = concat(
              local.application_inference_profile_arns,
              local.direct_access_inference_profile_arns
            )
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_organizations_policy_attachment" "bedrock_approved_models" {
  for_each = local.is_management ? toset(var.scp_target_ids) : toset([])

  policy_id = aws_organizations_policy.bedrock_approved_models[0].id
  target_id = each.value
}

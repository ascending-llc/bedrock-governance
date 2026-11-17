locals {
  cost_metric_namespace = "BedrockGovernance"

  # Profiles with token prices get a cost estimate; limit/alert fields require pricing (validated on the variable).
  cost_models       = { for key, model in local.child_models : key => model if model.pricing != null }
  cost_limit_models = { for key, model in local.cost_models : key => model if model.daily_cost_limit_usd != null }

  cost_alert_usd = {
    for key, model in local.cost_models : key => (
      model.daily_cost_alert_usd != null ? model.daily_cost_alert_usd : (
        model.daily_cost_limit_usd != null ? model.daily_cost_limit_usd * var.cost_alert_threshold_percent / 100 : null
      )
    )
  }
  cost_alert_thresholds = { for key, value in local.cost_alert_usd : key => value if value != null }

  cost_control_enabled = length(local.cost_models) > 0
  cost_limit_enabled   = length(local.cost_limit_models) > 0

  cost_enforcer_name = "${var.resource_name_prefix}-bedrock-cost-limit-enforcer"
  cost_block_name    = "${var.resource_name_prefix}-bedrock-cost-limit-block"

  # Alarm period must cover at least one enforcer run so the custom metric always has a datapoint.
  cost_alarm_period = max(300, var.cost_check_interval_minutes * 60)

  cost_block_placeholder_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "NoProfilesBlocked"
        Effect = "Deny"
        Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        # Valid but unmatched; the enforcer replaces the policy with real deny statements while a profile is over its limit.
        Resource = ["arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:application-inference-profile/none-blocked"]
      }
    ]
  }

  cost_enforcer_config = local.cost_control_enabled ? {
    partition        = data.aws_partition.current.partition
    region           = data.aws_region.current.name
    account_id       = data.aws_caller_identity.current.account_id
    metric_namespace = local.cost_metric_namespace
    enforce          = var.enforce_daily_cost_limits
    policy_arn       = local.cost_limit_enabled ? aws_iam_policy.cost_limit_block[0].arn : null
    profiles = [
      for key, model in local.cost_models : {
        name                 = model.name
        profile_id           = aws_bedrock_inference_profile.this[key].id
        profile_arn          = aws_bedrock_inference_profile.this[key].arn
        pricing              = model.pricing
        daily_cost_limit_usd = model.daily_cost_limit_usd
      }
    ]
  } : null
}

# Managed policy whose content the enforcer rewrites. Terraform owns its existence only.
resource "aws_iam_policy" "cost_limit_block" {
  count = local.cost_limit_enabled ? 1 : 0

  name        = local.cost_block_name
  description = "Denies Bedrock invocation on application inference profiles that reached their daily cost limit. Content is managed by the cost limit enforcer Lambda."
  policy      = jsonencode(local.cost_block_placeholder_policy)

  lifecycle {
    ignore_changes = [policy]
  }

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cost_limit_block" {
  for_each = local.cost_limit_enabled ? toset(var.cost_limit_block_policy_role_names) : toset([])

  role       = each.value
  policy_arn = aws_iam_policy.cost_limit_block[0].arn
}

data "archive_file" "cost_enforcer" {
  count = local.cost_control_enabled ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/.build/${local.cost_enforcer_name}.zip"

  source {
    content  = file("${path.module}/lambda/cost_limit_enforcer.py")
    filename = "cost_limit_enforcer.py"
  }

  source {
    content  = jsonencode(local.cost_enforcer_config)
    filename = "config.json"
  }
}

resource "aws_iam_role" "cost_enforcer" {
  count = local.cost_control_enabled ? 1 : 0

  name = local.cost_enforcer_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "lambda.amazonaws.com" }
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "cost_enforcer" {
  count = local.cost_control_enabled ? 1 : 0

  name = "cost-limit-enforcer"
  role = aws_iam_role.cost_enforcer[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "WriteLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.cost_enforcer[0].arn}:*"
      },
      {
        Sid      = "ReadBedrockTokenMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricData"]
        Resource = "*"
      },
      {
        Sid      = "PublishCostMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = { "cloudwatch:namespace" = local.cost_metric_namespace }
        }
      }
      ], local.cost_limit_enabled ? [
      {
        Sid    = "ManageCostLimitBlockPolicy"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion"
        ]
        Resource = aws_iam_policy.cost_limit_block[0].arn
      }
    ] : [])
  })
}

resource "aws_cloudwatch_log_group" "cost_enforcer" {
  count = local.cost_control_enabled ? 1 : 0

  name              = "/aws/lambda/${local.cost_enforcer_name}"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_lambda_function" "cost_enforcer" {
  count = local.cost_control_enabled ? 1 : 0

  function_name    = local.cost_enforcer_name
  description      = "Estimates per-AIP daily Bedrock cost, publishes cost metrics and blocks profiles over their daily limit."
  role             = aws_iam_role.cost_enforcer[0].arn
  runtime          = "python3.13"
  handler          = "cost_limit_enforcer.handler"
  timeout          = 60
  memory_size      = 128
  filename         = data.archive_file.cost_enforcer[0].output_path
  source_code_hash = data.archive_file.cost_enforcer[0].output_base64sha256

  depends_on = [aws_cloudwatch_log_group.cost_enforcer, aws_iam_role_policy.cost_enforcer]

  tags = local.common_tags
}

resource "aws_cloudwatch_event_rule" "cost_enforcer" {
  count = local.cost_control_enabled ? 1 : 0

  name                = "${var.resource_name_prefix}-bedrock-cost-limit-schedule"
  description         = "Runs the Bedrock cost limit enforcer."
  schedule_expression = "rate(${var.cost_check_interval_minutes} ${var.cost_check_interval_minutes == 1 ? "minute" : "minutes"})"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "cost_enforcer" {
  count = local.cost_control_enabled ? 1 : 0

  rule = aws_cloudwatch_event_rule.cost_enforcer[0].name
  arn  = aws_lambda_function.cost_enforcer[0].arn
}

resource "aws_lambda_permission" "cost_enforcer_schedule" {
  count = local.cost_control_enabled ? 1 : 0

  statement_id  = "AllowEventBridgeSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_enforcer[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_enforcer[0].arn
}

resource "aws_cloudwatch_metric_alarm" "cost_alert" {
  for_each = local.cost_alert_thresholds

  alarm_name          = "${var.resource_name_prefix}-${local.cost_models[each.key].name}-daily-cost-alert"
  alarm_description   = "Estimated UTC-day Bedrock cost for AIP ${local.cost_models[each.key].name} reached its alert threshold."
  namespace           = local.cost_metric_namespace
  metric_name         = "EstimatedDailyCostUSD"
  dimensions          = { ModelId = aws_bedrock_inference_profile.this[each.key].id }
  statistic           = "Maximum"
  period              = local.cost_alarm_period
  evaluation_periods  = 1
  threshold           = each.value
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = local.anomaly_notification_topic_arn != null ? [local.anomaly_notification_topic_arn] : []
  ok_actions          = local.anomaly_notification_topic_arn != null ? [local.anomaly_notification_topic_arn] : []

  tags = merge(local.common_tags, { Model = local.cost_models[each.key].name }, local.cost_models[each.key].team != null ? { Team = local.cost_models[each.key].team } : {})
}

resource "aws_cloudwatch_metric_alarm" "cost_limit" {
  for_each = local.cost_limit_models

  alarm_name = "${var.resource_name_prefix}-${each.value.name}-daily-cost-limit"
  alarm_description = var.enforce_daily_cost_limits ? (
    "AIP ${each.value.name} reached its daily cost limit and is blocked until the UTC day rolls over or the limit is raised."
    ) : (
    "AIP ${each.value.name} reached its daily cost limit. Enforcement is disabled, so it is not blocked."
  )
  namespace           = local.cost_metric_namespace
  metric_name         = "CostLimitBlocked"
  dimensions          = { ModelId = aws_bedrock_inference_profile.this[each.key].id }
  statistic           = "Maximum"
  period              = local.cost_alarm_period
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = local.anomaly_notification_topic_arn != null ? [local.anomaly_notification_topic_arn] : []
  ok_actions          = local.anomaly_notification_topic_arn != null ? [local.anomaly_notification_topic_arn] : []

  tags = merge(local.common_tags, { Model = each.value.name }, each.value.team != null ? { Team = each.value.team } : {})
}

# Enforcement fails open if the Lambda cannot run, so surface its failures.
resource "aws_cloudwatch_metric_alarm" "cost_enforcer_errors" {
  count = local.cost_control_enabled ? 1 : 0

  alarm_name          = "${var.resource_name_prefix}-bedrock-cost-limit-enforcer-errors"
  alarm_description   = "The Bedrock cost limit enforcer failed; cost metrics and daily limits are not being evaluated."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.cost_enforcer[0].function_name }
  statistic           = "Sum"
  period              = local.cost_alarm_period
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.anomaly_notification_topic_arn != null ? [local.anomaly_notification_topic_arn] : []
  ok_actions          = local.anomaly_notification_topic_arn != null ? [local.anomaly_notification_topic_arn] : []

  tags = local.common_tags
}

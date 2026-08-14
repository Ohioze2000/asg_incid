# ==============================================================================
# 1. CLOUDWATCH LOG GROUPS
# ==============================================================================

resource "aws_cloudwatch_log_group" "app_log_groups" {
  for_each = var.log_groups

  name              = "/aws/${var.env_prefix}/${each.key}"
  retention_in_days = lookup(each.value, "retention_in_days", var.default_log_retention_days)
  kms_key_id        = lookup(each.value, "kms_key_id", var.kms_key_id)

  tags = merge(
    var.tags,
    {
      Name = "${var.env_prefix}-${each.key}-logs"
    }
  )
}

# ==============================================================================
# 2. METRIC FILTERS (Extract metrics from logs)
# ==============================================================================

resource "aws_cloudwatch_log_metric_filter" "filters" {
  for_each = var.metric_filters

  name           = "${var.env_prefix}-${each.key}"
  pattern        = each.value.pattern
  log_group_name = aws_cloudwatch_log_group.app_log_groups[each.value.log_group_key].name

  metric_transformation {
    name          = each.value.metric_name
    namespace     = "${var.env_prefix}/${each.value.metric_namespace}"
    value         = lookup(each.value, "metric_value", "1")
    default_value = lookup(each.value, "default_value", "0")
  }
}

# ==============================================================================
# 3. APPLICATION ALARMS
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "app_alarms" {
  for_each = var.app_alarms

  alarm_name          = "${var.env_prefix}-${each.key}"
  comparison_operator = lookup(each.value, "comparison_operator", "GreaterThanOrEqualToThreshold")
  evaluation_periods  = lookup(each.value, "evaluation_periods", 1)
  metric_name         = each.value.metric_name
  namespace           = lookup(each.value, "is_custom_metric", true) ? "${var.env_prefix}/${each.value.metric_namespace}" : each.value.metric_namespace
  period              = lookup(each.value, "period", 60)
  statistic           = lookup(each.value, "statistic", "Sum")
  threshold           = each.value.threshold
  alarm_description   = lookup(each.value, "description", "Alarm triggered for ${each.key}")
  treat_missing_data  = lookup(each.value, "treat_missing_data", "notBreaching")

  alarm_actions = var.alarm_sns_topic_arns
  ok_actions    = var.alarm_sns_topic_arns

  dimensions = lookup(each.value, "dimensions", {})

  tags = merge(
    var.tags,
    {
      Name = "${var.env_prefix}-${each.key}-alarm"
    }
  )
}
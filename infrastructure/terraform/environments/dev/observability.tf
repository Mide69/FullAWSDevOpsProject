# ===========================================================================
# Observability: Container Insights (metrics + logs) + dashboard + alarms.
# ===========================================================================

# The CloudWatch agent (installed by the addon below) uses the node role's
# credentials, so grant it permission to publish metrics and logs.
resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = module.eks.node_role_name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Container Insights: full metrics + container logs into CloudWatch.
resource "aws_eks_addon" "cloudwatch" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_iam_role_policy_attachment.cw_agent]
}

# --- Alerting: SNS topic → email ------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "dev-govplatform-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "olamidekosile@gmail.com" # confirm via the email AWS sends
}

# Alarm: cluster node CPU sustained high (via Container Insights metrics).
resource "aws_cloudwatch_metric_alarm" "node_cpu" {
  alarm_name          = "dev-govplatform-node-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description    = "Worker node CPU above 80% for 15 minutes"
  dimensions          = { ClusterName = module.eks.cluster_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

# Alarm: any pod restarting repeatedly (crash loop signal).
resource "aws_cloudwatch_metric_alarm" "pod_restarts" {
  alarm_name          = "dev-govplatform-pod-restarts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "pod_number_of_container_restarts"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description    = "Pods restarting repeatedly in the cluster"
  dimensions          = { ClusterName = module.eks.cluster_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

# --- Dashboard: one pane of glass for the platform ------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "dev-govplatform"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "Node CPU %"
          region = "eu-west-2"
          metrics = [["ContainerInsights", "node_cpu_utilization", "ClusterName", module.eks.cluster_name]]
          period = 300
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Running pods"
          region = "eu-west-2"
          metrics = [["ContainerInsights", "cluster_number_of_running_pods", "ClusterName", module.eks.cluster_name]]
          period = 300
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Node memory %"
          region = "eu-west-2"
          metrics = [["ContainerInsights", "node_memory_utilization", "ClusterName", module.eks.cluster_name]]
          period = 300
        }
      }
    ]
  })
}

output "dashboard_url" {
  value = "https://eu-west-2.console.aws.amazon.com/cloudwatch/home?region=eu-west-2#dashboards/dashboard/dev-govplatform"
}

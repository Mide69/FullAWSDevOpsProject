# ===========================================================================
# Security plane: WAF on the public ALB + account-wide threat detection.
# ===========================================================================

# --- WAFv2 Web ACL (regional, attached to the ALB via Ingress annotation) ---
resource "aws_wafv2_web_acl" "main" {
  name        = "dev-govplatform-waf"
  description = "OWASP managed rules + rate limiting for the public ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # 1. AWS Managed: common OWASP-style protections (XSS, LFI, etc.)
  rule {
    name     = "AWSCommonRules"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSCommonRules"
      sampled_requests_enabled   = true
    }
  }

  # 2. AWS Managed: known-bad inputs (exploit payloads).
  rule {
    name     = "AWSKnownBadInputs"
    priority = 2
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSKnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # 3. Rate limiting: block an IP exceeding 2000 requests / 5 min.
  rule {
    name     = "RateLimit"
    priority = 3
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "dev-govplatform-waf"
    sampled_requests_enabled   = true
  }
}

# --- GuardDuty: continuous threat detection from logs/DNS/network ----------
resource "aws_guardduty_detector" "main" {
  enable = true
}

# --- Security Hub: aggregates findings + runs compliance standards ---------
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "fsbp" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:eu-west-2::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# --- Inspector v2: continuous CVE scanning of ECR images + EC2 -------------
resource "aws_inspector2_enabler" "main" {
  account_ids    = ["445358171352"]
  resource_types = ["ECR", "EC2"]
}

output "waf_acl_arn" {
  value = aws_wafv2_web_acl.main.arn
}

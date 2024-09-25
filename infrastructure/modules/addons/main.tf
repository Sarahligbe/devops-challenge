data "aws_route53_zone" "main" {
  name         = var.domain
  private_zone = false
}

# Request ACM certificate
resource "aws_acm_certificate" "main" {
  domain_name       = "var.domain"
  validation_method = "DNS"
  subject_alternative_names = ["*.${var.domain}"]

  lifecycle {
    create_before_destroy = true
  }
}

# Validate ACM certificate (assuming DNS validation)
resource "aws_route53_record" "main" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.main : record.fqdn]
}

resource "helm_release" "argocd-helm" {
  count = var.enable_argocd ? 1 : 0

  name = "argo-cd"
  version = "7.6.0"
  repository = "https://argoproj.github.io/argo-helm"
  chart = "argo-cd"
  timeout = 1000
  namespace  = "argocd"
  create_namespace = true

  values = [templatefile("argo_cd_values.yaml", {argopass = "${var.argopass}", domain = "${var.domain}", cert_arn = "${aws_acm_certificate.main.arn}"})]
}

resource "helm_release" "prometheus" {
  count = var.enable_monitoring ? 1 : 0

  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  create_namespace = true
  version = "62.7.0"
  timeout = 1000
 
  values = [templatefile("prometheus_values.yaml", {grafana_passwd = "${var.grafana_passwd}", domain = "${var.domain}", cert_arn = "${aws_acm_certificate.main.arn}" })]
}


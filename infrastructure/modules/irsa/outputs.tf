output "discovery_bucket_name" {
  value = aws_s3_bucket.discovery_bucket.id
}

output "oidc_provider_url" {
  value = aws_iam_openid_connect_provider.main.url
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.main.arn
}

output "service_account_issuer" {
  value = "https://s3-${var.region}.amazonaws.com/${aws_s3_bucket.discovery_bucket.id}"
}

output "irsa_bucket_arn" {
  value = "aws_s3_bucket.discovery_bucket.arn"
}
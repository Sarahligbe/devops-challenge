data "aws_iam_policy_document" "discovery_bucket_policy" {
  statement {
    sid = "AllowPublicRead"

    effect  = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      aws_s3_bucket.discovery_bucket.arn,
      "${aws_s3_bucket.discovery_bucket.arn}/*",
    ]
  }
}

resource "aws_s3_bucket" "discovery_bucket" {
  bucket = "aws-irsa-oidc-discovery-${var.s3_suffix}"
}

resource "aws_s3_bucket_public_access_block" "discovery_bucket" {
  bucket = aws_s3_bucket.discovery_bucket.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "readonly_policy" {
  bucket = aws_s3_bucket.discovery_bucket.id
  policy = data.aws_iam_policy_document.discovery_bucket_policy.json
}

resource "null_resource" "generate_keys" {
  provisioner "local-exec" {
    command = "${path.module}/generate_keys.sh"
  }
}

resource "aws_s3_object" "jwks_json" {
  depends_on = [null_resource.generate_keys]
  bucket     = aws_s3_bucket.discovery_bucket.id
  key        = "keys.json"
  source     = "${path.module}/keys/keys.json"
  content_type = "application/json"
}

resource "aws_s3_object" "discovery_json" {
  bucket = aws_s3_bucket.discovery_bucket.id
  key    = ".well-known/openid-configuration"
  content = templatefile("${path.module}/discovery.json", {
    issuer_hostpath = "s3-${var.region}.amazonaws.com/${aws_s3_bucket.discovery_bucket.id}"
  })
  content_type = "application/json"
}

data "tls_certificate" "s3" {
  url = "https://s3-${var.region}.amazonaws.com"
}

resource "aws_iam_openid_connect_provider" "main" {
  url             = "https://s3-${var.region}.amazonaws.com/${aws_s3_bucket.discovery_bucket.id}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.s3.certificates[0].sha1_fingerprint]
}

resource "null_resource" "cleanup_keys" {
  depends_on = [aws_s3_object.jwks_json, aws_iam_openid_connect_provider.main]

  provisioner "local-exec" {
    command = "rm -rf ${path.module}/keys"
  }
}

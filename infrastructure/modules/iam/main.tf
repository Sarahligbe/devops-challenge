#Create an IAM Policy
resource "aws_iam_policy" "k8s_ssm_policy" {
  name        = "node_ssm"
  description = "Provides permission to put and get parameters in the ssm parameter store"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
        ]
        Effect   = "Allow"
        Resource = [

        "var.k8s_join_command_arn" ]
      },
    ]
  })
}

#Create the IAM Role
resource "aws_iam_role" "k8s_ssm_role" {
  name = "ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "RoleForEC2"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy_attachment" "ssm_attach" {
  name       = "ssm_attach"
  roles      = [aws_iam_role.k8s_ssm_role.name]
  policy_arn = aws_iam_policy.k8s_ssm_policy.arn
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "ssm_profile"
  role = aws_iam_role.k8s_ssm_role.name
}
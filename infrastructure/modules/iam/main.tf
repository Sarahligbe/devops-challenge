data "aws_iam_policy_document" "controlplane" {
  statement {
    actions = [
      "ssm:PutParameter",
      "ssm:GetParameter",
    ]
    effect = "Allow"

    resources = ["*"]
  }

  statement {
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVolumes",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyVolume",
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteVolume",
      "ec2:DetachVolume",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DescribeVpcs",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:AttachLoadBalancerToSubnets",
      "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateLoadBalancerPolicy",
      "elasticloadbalancing:CreateLoadBalancerListeners",
      "elasticloadbalancing:ConfigureHealthCheck",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancerListeners",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DetachLoadBalancerFromSubnets",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancerPolicies",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
      "iam:CreateServiceLinkedRole",
      "kms:DescribeKey",
    ]
    effect = "Allow"

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "worker" {
  statement {
    actions = [
      "ssm:PutParameter",
      "ssm:GetParameter",
    ]
    effect = "Allow"

    resources = ["*"]
  }

  statement {
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeRegions",
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:BatchGetImage",
    ]
    effect = "Allow"

    resources = ["*"]
  }
}

#Create an IAM controlplane Policy
resource "aws_iam_policy" "k8s_controlplane_policy" {
  name        = "controlplane_node"
  description = "Provides permission for the k8s controlplane node"

  policy = data.aws_iam_policy_document.controlplane.json
}

#Create an IAM worker Policy
resource "aws_iam_policy" "k8s_worker_policy" {
  name        = "worker_node"
  description = "Provides permission for the k8s worker node"

  policy = data.aws_iam_policy_document.worker.json
}

#Create the IAM controlplane Role
resource "aws_iam_role" "k8s_controlplane_role" {
  name = "controlplane_node_role"

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

#Create the IAM Role
resource "aws_iam_role" "k8s_worker_role" {
  name = "worker_node_role"

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

resource "aws_iam_policy_attachment" "controlplane_attach" {
  name       = "controlplane_attach"
  roles      = [aws_iam_role.k8s_controlplane_role.name]
  policy_arn = aws_iam_policy.k8s_controlplane_policy.arn
}

resource "aws_iam_policy_attachment" "worker_attach" {
  name       = "worker_attach"
  roles      = [aws_iam_role.k8s_worker_role.name]
  policy_arn = aws_iam_policy.k8s_worker_policy.arn
}

resource "aws_iam_instance_profile" "controlplane_profile" {
  name = "controlplane_profile"
  role = aws_iam_role.k8s_controlplane_role.name
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "worker_profile"
  role = aws_iam_role.k8s_worker_role.name
}
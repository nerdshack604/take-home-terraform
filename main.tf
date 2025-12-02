################################################################################
# Local Variables
################################################################################

locals {
  cluster_name = var.cluster_name

  # VPC Configuration
  create_vpc = var.vpc_id == null
  vpc_id     = local.create_vpc ? module.vpc[0].vpc_id : var.vpc_id

  # Subnet Configuration
  private_subnet_ids = local.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids
  public_subnet_ids  = local.create_vpc ? module.vpc[0].public_subnets : var.public_subnet_ids

  # Tags following AWS Well-Architected Framework
  common_tags = merge(
    var.tags,
    {
      "ManagedBy"   = "Terraform"
      "Environment" = var.environment
      "Project"     = var.project_name
      "ClusterName" = local.cluster_name
    }
  )

  # KMS key rotation settings
  kms_key_rotation_period_in_days = var.kms_key_rotation_period_in_days
}

################################################################################
# VPC Module (Conditional)
################################################################################

module "vpc" {
  count   = local.create_vpc ? 1 : 0
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs for security compliance
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_iam_role             = true
  create_flow_log_cloudwatch_log_group            = true
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_days

  # EKS-specific subnet tags
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  tags = local.common_tags
}

################################################################################
# KMS Key for EKS Encryption
################################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS cluster ${local.cluster_name} encryption"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  rotation_period_in_days = local.kms_key_rotation_period_in_days

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
          }
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      "Name" = "${local.cluster_name}-eks-kms"
    }
  )
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  # Cluster endpoint configuration
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = true

  # Enable IRSA
  enable_irsa = true

  # Authentication and Access Configuration
  # Use API_AND_CONFIG_MAP for backward compatibility with aws-auth ConfigMap
  # while also supporting modern EKS Access Entries
  authentication_mode = "API_AND_CONFIG_MAP"

  # Automatically grant the IAM principal creating the cluster admin permissions
  # This ensures the caller (eks-admin user) can immediately access the cluster
  enable_cluster_creator_admin_permissions = true

  # Cluster encryption config
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  # Enhanced security settings
  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # CloudWatch log group retention
  cloudwatch_log_group_retention_in_days = var.cloudwatch_log_retention_days
  cloudwatch_log_group_kms_key_id        = aws_kms_key.eks.arn

  vpc_id                   = local.vpc_id
  subnet_ids               = local.private_subnet_ids
  control_plane_subnet_ids = local.private_subnet_ids

  # Ensure KMS key is fully configured before creating log groups
  depends_on = [
    aws_kms_key.eks
  ]

  # Managed node groups
  eks_managed_node_groups = var.node_groups

  # Cluster security group rules
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  # Node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }

    ingress_cluster_all = {
      description                   = "Cluster to node all ports/protocols"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }

    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  tags = local.common_tags
}

################################################################################
# EBS CSI Driver IAM Role (IRSA)
################################################################################

data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "${local.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

################################################################################
# EBS CSI Driver Node IAM Policy Attachment
# Workaround: Some CSI driver versions fall back to node IAM credentials
# This ensures volumes can be provisioned even if IRSA doesn't work
################################################################################

resource "aws_iam_role_policy_attachment" "ebs_csi_node_policy" {
  for_each = module.eks.eks_managed_node_groups

  role       = each.value.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

################################################################################
# EKS Addons
################################################################################

resource "aws_eks_addon" "addons" {
  for_each = var.cluster_addons

  cluster_name                = module.eks.cluster_name
  addon_name                  = each.key
  addon_version               = each.value.version
  resolve_conflicts_on_create = each.value.resolve_conflicts_on_create
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update
  service_account_role_arn    = each.key == "aws-ebs-csi-driver" ? aws_iam_role.ebs_csi_driver.arn : lookup(each.value, "service_account_role_arn", null)

  preserve = lookup(each.value, "preserve", true)

  configuration_values = lookup(each.value, "configuration_values", null)

  tags = local.common_tags

  depends_on = [
    module.eks.eks_managed_node_groups
  ]
}

################################################################################
# Wait for EKS Cluster to be Ready
################################################################################

# Null resource to wait for cluster to be fully operational
# This ensures node groups are ready before Kubernetes resources are created
resource "null_resource" "wait_for_cluster" {
  depends_on = [
    module.eks.eks_managed_node_groups,
    aws_eks_addon.addons
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for EKS cluster to be ready..."
      aws eks wait cluster-active --name ${module.eks.cluster_name} --region ${data.aws_region.current.name}
      echo "Cluster is active. Updating kubeconfig..."
      aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${data.aws_region.current.name}
      echo "Waiting for node groups to be ready..."
      sleep 30
      echo "Verifying cluster connectivity..."
      max_attempts=12
      attempt=0
      while [ $attempt -lt $max_attempts ]; do
        if kubectl get nodes --request-timeout=5s > /dev/null 2>&1; then
          echo "Successfully connected to cluster!"
          kubectl get nodes
          exit 0
        fi
        attempt=$((attempt + 1))
        echo "Attempt $attempt/$max_attempts failed, retrying in 10s..."
        sleep 10
      done
      echo "Failed to connect to cluster after $max_attempts attempts"
      exit 1
    EOT
  }
}

################################################################################
# IAM Role for ShinyProxy
################################################################################

resource "aws_iam_role" "shinyproxy" {
  name = "${local.cluster_name}-shinyproxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" = "system:serviceaccount:${var.shinyproxy_namespace}:shinyproxy-sa"
            "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "shinyproxy_ecr" {
  count = var.enable_shinyproxy_ecr_access ? 1 : 0
  name  = "shinyproxy-ecr-access"
  role  = aws_iam_role.shinyproxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

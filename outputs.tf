################################################################################
# VPC Outputs
################################################################################

output "vpc_id" {
  description = "The ID of the VPC"
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = local.private_subnet_ids
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = local.public_subnet_ids
}

################################################################################
# EKS Cluster Outputs
################################################################################

output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "The Kubernetes version for the cluster"
  value       = module.eks.cluster_version
}

output "cluster_platform_version" {
  description = "The platform version for the cluster"
  value       = module.eks.cluster_platform_version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = module.eks.oidc_provider_arn
}

output "cluster_oidc_provider" {
  description = "The OIDC provider for EKS (without https://)"
  value       = module.eks.oidc_provider
}

################################################################################
# EKS Node Group Outputs
################################################################################

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.eks.eks_managed_node_groups
}

################################################################################
# KMS Outputs
################################################################################

output "kms_key_id" {
  description = "The ID of the KMS key used for EKS encryption"
  value       = aws_kms_key.eks.id
}

output "kms_key_arn" {
  description = "The ARN of the KMS key used for EKS encryption"
  value       = aws_kms_key.eks.arn
}

################################################################################
# ShinyProxy Outputs
################################################################################

output "shinyproxy_namespace" {
  description = "The namespace where ShinyProxy is deployed"
  value       = kubernetes_namespace.shinyproxy.metadata[0].name
}

output "shinyproxy_service_account_name" {
  description = "The name of the ShinyProxy service account"
  value       = kubernetes_service_account.shinyproxy.metadata[0].name
}

output "shinyproxy_service_account_role_arn" {
  description = "The ARN of the IAM role associated with the ShinyProxy service account"
  value       = aws_iam_role.shinyproxy.arn
}

output "shinyproxy_load_balancer_hostname" {
  description = "The hostname of the load balancer for ShinyProxy"
  value       = try(kubernetes_service.shinyproxy.status[0].load_balancer[0].ingress[0].hostname, "")
}

output "shinyproxy_url" {
  description = "The URL to access ShinyProxy (once DNS is configured)"
  value       = try("http://${kubernetes_service.shinyproxy.status[0].load_balancer[0].ingress[0].hostname}", "pending")
}

################################################################################
# Configuration Outputs
################################################################################

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${module.eks.cluster_name}"
}

output "region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}

################################################################################
# Data Sources for Outputs
################################################################################

# Using data.aws_region.current from main.tf

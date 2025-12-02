################################################################################
# General Configuration
################################################################################

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# VPC Configuration
################################################################################

variable "vpc_id" {
  description = "Existing VPC ID. If null, a new VPC will be created"
  type        = string
  default     = null
}

variable "private_subnet_ids" {
  description = "List of existing private subnet IDs. Required if vpc_id is provided"
  type        = list(string)
  default     = []

  validation {
    condition     = var.vpc_id == null || length(var.private_subnet_ids) > 0
    error_message = "private_subnet_ids must be provided when using an existing VPC."
  }
}

variable "public_subnet_ids" {
  description = "List of existing public subnet IDs. Required if vpc_id is provided"
  type        = list(string)
  default     = []

  validation {
    condition     = var.vpc_id == null || length(var.public_subnet_ids) > 0
    error_message = "public_subnet_ids must be provided when using an existing VPC."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (only used if creating new VPC)"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones (only used if creating new VPC)"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks (only used if creating new VPC)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks (only used if creating new VPC)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for cost savings (not recommended for production)"
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "VPC Flow Logs retention in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_log_retention_days)
    error_message = "Flow log retention must be a valid CloudWatch Logs retention period."
  }
}

################################################################################
# EKS Cluster Configuration
################################################################################

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,99}$", var.cluster_name))
    error_message = "Cluster name must start with a letter, contain only alphanumeric characters and hyphens, and be 100 characters or less."
  }
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.34"

  validation {
    condition     = can(regex("^1\\.(2[4-9]|3[0-9])$", var.cluster_version))
    error_message = "Cluster version must be a valid EKS version (1.24 or higher)."
  }
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention for EKS control plane logs"
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period."
  }
}

################################################################################
# KMS Configuration
################################################################################

variable "kms_deletion_window_in_days" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

variable "kms_key_rotation_period_in_days" {
  description = "KMS key rotation period in days (90-2560 days)"
  type        = number
  default     = 90

  validation {
    condition     = var.kms_key_rotation_period_in_days >= 90 && var.kms_key_rotation_period_in_days <= 2560
    error_message = "KMS key rotation period must be between 90 and 2560 days."
  }
}

################################################################################
# EKS Node Groups
################################################################################

variable "node_groups" {
  description = "Map of EKS managed node group definitions"
  type = map(object({
    min_size       = number
    max_size       = number
    desired_size   = number
    instance_types = list(string)
    capacity_type  = string
    disk_size      = number
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))

  default = {
    default = {
      min_size       = 2
      max_size       = 6
      desired_size   = 3
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 50
      labels         = {}
      taints         = []
    }
  }
}

################################################################################
# EKS Addons Configuration
################################################################################

variable "cluster_addons" {
  description = "Map of cluster addon configurations to enable"
  type = map(object({
    version                     = string
    resolve_conflicts_on_create = optional(string, "OVERWRITE")
    resolve_conflicts_on_update = optional(string, "PRESERVE")
    service_account_role_arn    = optional(string, null)
    preserve                    = optional(bool, true)
    configuration_values        = optional(string, null)
  }))

  default = {
    vpc-cni = {
      version                     = "v1.19.0-eksbuild.1"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
    }
    coredns = {
      version                     = "v1.11.3-eksbuild.2"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
    }
    kube-proxy = {
      version                     = "v1.31.2-eksbuild.3"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
    }
    aws-ebs-csi-driver = {
      version                     = "v1.37.0-eksbuild.1"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
    }
  }
}

################################################################################
# ShinyProxy Configuration
################################################################################

variable "shinyproxy_namespace" {
  description = "Kubernetes namespace for ShinyProxy"
  type        = string
  default     = "shinyproxy"
}

variable "shinyproxy_version" {
  description = "ShinyProxy version to deploy"
  type        = string
  default     = "3.2.1"
}

variable "enable_shinyproxy_ecr_access" {
  description = "Enable ECR access for ShinyProxy service account"
  type        = bool
  default     = true
}

variable "shinyproxy_image_pull_policy" {
  description = "Image pull policy for ShinyProxy"
  type        = string
  default     = "IfNotPresent"

  validation {
    condition     = contains(["Always", "IfNotPresent", "Never"], var.shinyproxy_image_pull_policy)
    error_message = "Image pull policy must be Always, IfNotPresent, or Never."
  }
}

variable "shinyproxy_replicas" {
  description = "Number of ShinyProxy replicas"
  type        = number
  default     = 2

  validation {
    condition     = var.shinyproxy_replicas > 0
    error_message = "ShinyProxy replicas must be at least 1."
  }
}

variable "shinyproxy_port" {
  description = "Port for ShinyProxy service"
  type        = number
  default     = 8080

  validation {
    condition     = var.shinyproxy_port > 0 && var.shinyproxy_port < 65536
    error_message = "ShinyProxy port must be between 1 and 65535."
  }
}

variable "shinyproxy_apps" {
  description = "List of ShinyProxy application configurations"
  type = list(object({
    id              = string
    display_name    = string
    description     = string
    container_image = string
    container_cmd   = optional(list(string), [])
    container_env   = optional(map(string), {})
    port            = optional(number, 3838)
  }))
  default = []
}

variable "shinyproxy_authentication" {
  description = "ShinyProxy authentication configuration"
  type = object({
    type = string
    ldap = optional(object({
      url              = string
      user_dn_pattern  = string
      manager_dn       = optional(string)
      manager_password = optional(string)
    }))
    simple = optional(object({
      users = list(object({
        name     = string
        password = string
        groups   = list(string)
      }))
    }))
  })
  default = {
    type = "none"
  }

  validation {
    condition     = contains(["none", "simple", "ldap", "openid", "keycloak", "saml"], var.shinyproxy_authentication.type)
    error_message = "Authentication type must be one of: none, simple, ldap, openid, keycloak, saml."
  }
}

variable "shinyproxy_resources" {
  description = "Resource requests and limits for ShinyProxy pods"
  type = object({
    requests = object({
      memory = string
      cpu    = string
    })
    limits = object({
      memory = string
      cpu    = string
    })
  })
  default = {
    requests = {
      memory = "512Mi"
      cpu    = "250m"
    }
    limits = {
      memory = "1Gi"
      cpu    = "1000m"
    }
  }
}

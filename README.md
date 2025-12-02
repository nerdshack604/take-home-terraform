# EKS 1.34 with ShinyProxy 3.2.1 Terraform Module

Production-ready Terraform module for deploying Amazon EKS 1.34 with ShinyProxy 3.2.1 using the ShinyProxy Operator. This module follows AWS Well-Architected Framework best practices with comprehensive security controls, encryption, and monitoring.

## Features

- **Amazon EKS 1.34**: Latest Kubernetes version with managed control plane
- **VPC Management**: Creates a new VPC or uses an existing one
- **Security**: KMS encryption, IAM roles with IRSA, security groups, VPC flow logs
- **Compliance**: Configurable KMS key rotation, comprehensive logging, encryption at rest
- **High Availability**: Multi-AZ deployment, managed node groups with auto-scaling
- **ShinyProxy 3.2.1**: Deployed via Kubernetes Operator with Custom Resources
- **EKS Addons Manager**: Version-controlled AWS-provided addons (VPC CNI, CoreDNS, kube-proxy, EBS CSI)
- **Observability**: CloudWatch Logs, VPC Flow Logs, metrics export to Prometheus

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS Account                         │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    VPC (10.0.0.0/16)                   │ │
│  │                                                        │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │ │
│  │  │  Public      │  │  Public      │  │  Public      │  │ │
│  │  │  Subnet AZ-A │  │  Subnet AZ-B │  │  Subnet AZ-C │  │ │
│  │  │  (NAT GW)    │  │  (NAT GW)    │  │  (NAT GW)    │  │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │ │
│  │         │                  │                  │        │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │ │
│  │  │  Private     │  │  Private     │  │  Private     │  │ │
│  │  │  Subnet AZ-A │  │  Subnet AZ-B │  │  Subnet AZ-C │  │ │
│  │  │              │  │              │  │              │  │ │
│  │  │  ┌─────────┐ │  │  ┌─────────┐ │  │  ┌─────────┐ │  │ │
│  │  │  │EKS Nodes│ │  │  │EKS Nodes│ │  │  │EKS Nodes│ │  │ │
│  │  │  │         │ │  │  │         │ │  │  │         │ │  │ │
│  │  │  │ShinyProxy │  │  │ShinyProxy │  │  │ShinyProxy │  │ │
│  │  │  └─────────┘ │  │  └─────────┘ │  │  └─────────┘ │  │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │ │
│  │                                                        │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌────────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │   EKS Control  │  │  KMS Key     │  │  CloudWatch     │  │
│  │   Plane        │  │  (Encrypted) │  │  Logs           │  │
│  └────────────────┘  └──────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Terraform >= 1.6.0
- AWS CLI configured with appropriate credentials
- kubectl (for cluster interaction)
- Appropriate AWS permissions to create:
  - VPC resources (if creating new VPC)
  - EKS clusters
  - IAM roles and policies
  - KMS keys
  - Security groups
  - EC2 instances (for node groups)

## Quick Start

### 1. Clone and Configure

**Option A: Minimal Quick Start** (fastest way to get started)

```bash
# Navigate to the module directory
cd take-home-terraform

# Copy minimal quick start variables
cp quickstart.tfvars terraform.tfvars

# Edit terraform.tfvars - update availability zones for your region
vim terraform.tfvars
```

**Option B: Full Configuration** (recommended for production)

```bash
# Navigate to the module directory
cd take-home-terraform

# Copy comprehensive example variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your full configuration
vim terraform.tfvars
```

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

**Important Note on First Deployment**: On first-time deployment, the Terraform configuration includes automatic wait logic to ensure the EKS cluster and node groups are fully operational before deploying Kubernetes resources. The deployment will:

1. Create the EKS cluster and node groups
2. Wait for the cluster to become active
3. Deploy Kubernetes resources (ShinyProxy namespace, CRDs, operator, etc.)

This ensures a successful single-shot deployment without requiring manual intervention or multiple `terraform apply` runs.

### 3. Configure kubectl

```bash
# Get the kubectl configuration command from outputs
terraform output configure_kubectl

# Run the command (example)
aws eks update-kubeconfig --region us-west-2 --name shinyproxy-eks-cluster
```

### 4. Verify ShinyProxy

```bash
# Check ShinyProxy deployment
kubectl get pods -n shinyproxy

# Get ShinyProxy URL
terraform output shinyproxy_url

# Or get the load balancer hostname
kubectl get svc -n shinyproxy shinyproxy
```

## Configuration

### VPC Options

#### Option 1: Create New VPC (Recommended)

```hcl
vpc_id              = null
private_subnet_ids  = []
public_subnet_ids   = []

vpc_cidr = "10.0.0.0/16"
availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
```

#### Option 2: Use Existing VPC

```hcl
vpc_id = "vpc-0123456789abcdef0"
private_subnet_ids = [
  "subnet-0123456789abcdef0",
  "subnet-0123456789abcdef1",
  "subnet-0123456789abcdef2"
]
public_subnet_ids = [
  "subnet-0fedcba987654321a",
  "subnet-0fedcba987654321b",
  "subnet-0fedcba987654321c"
]
```

### EKS Node Groups

Configure node groups for different workloads:

```hcl
node_groups = {
  general = {
    min_size       = 2
    max_size       = 6
    desired_size   = 3
    instance_types = ["t3.large"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 50
    labels         = { workload = "general" }
    taints         = []
  }

  spot = {
    min_size       = 1
    max_size       = 5
    desired_size   = 2
    instance_types = ["t3.large", "t3a.large"]
    capacity_type  = "SPOT"
    disk_size      = 50
    labels         = { workload = "spot" }
    taints = [
      {
        key    = "spot"
        value  = "true"
        effect = "NoSchedule"
      }
    ]
  }
}
```

### EKS Addons

Manage AWS-provided addons with specific versions:

```hcl
cluster_addons = {
  vpc-cni = {
    version = "v1.19.0-eksbuild.1"
    resolve_conflicts_on_create = "OVERWRITE"
    resolve_conflicts_on_update = "PRESERVE"
  }
  coredns = {
    version = "v1.11.3-eksbuild.2"
    resolve_conflicts_on_create = "OVERWRITE"
    resolve_conflicts_on_update = "PRESERVE"
  }
  kube-proxy = {
    version = "v1.31.2-eksbuild.3"
    resolve_conflicts_on_create = "OVERWRITE"
    resolve_conflicts_on_update = "PRESERVE"
  }
  aws-ebs-csi-driver = {
    version = "v1.37.0-eksbuild.1"
    resolve_conflicts_on_create = "OVERWRITE"
    resolve_conflicts_on_update = "PRESERVE"
  }
}
```

To find the latest addon versions:

```bash
aws eks describe-addon-versions --kubernetes-version 1.34 \
  --addon-name vpc-cni --query 'addons[0].addonVersions[0].addonVersion'
```

## ShinyProxy Configuration

### Application Definitions

Define Shiny applications that ShinyProxy will manage:

```hcl
shinyproxy_apps = [
  {
    id              = "01_hello"
    display_name    = "Hello Application"
    description     = "A simple hello world Shiny application"
    container_image = "openanalytics/shinyproxy-demo"
    container_cmd   = ["R", "-e", "shiny::runApp('/root/shinyproxy-demo')"]
    container_env   = {}
    port            = 3838
  },
  {
    id              = "02_custom_app"
    display_name    = "Custom Analytics App"
    description     = "Custom R Shiny application"
    container_image = "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-shiny-app:latest"
    container_cmd   = []
    container_env   = {
      DATABASE_URL = "postgresql://db.example.com:5432/analytics"
      CACHE_ENABLED = "true"
    }
    port = 3838
  }
]
```

### Authentication Options

#### No Authentication (Development Only)

```hcl
shinyproxy_authentication = {
  type = "none"
}
```

**Warning**: Only use for development environments. Not suitable for production.

#### Simple Authentication

```hcl
shinyproxy_authentication = {
  type = "simple"
  simple = {
    users = [
      {
        name     = "admin"
        password = "$2a$10$..." # BCrypt hashed password
        groups   = ["admins", "users"]
      },
      {
        name     = "analyst"
        password = "$2a$10$..."
        groups   = ["users"]
      }
    ]
  }
}
```

Generate BCrypt passwords:

```bash
# Using htpasswd
htpasswd -bnBC 10 "" your_password | tr -d ':\n'

# Using Python
python3 -c 'import bcrypt; print(bcrypt.hashpw(b"your_password", bcrypt.gensalt(10)).decode())'
```

#### LDAP Authentication

```hcl
shinyproxy_authentication = {
  type = "ldap"
  ldap = {
    url             = "ldap://ldap.example.com:389"
    user_dn_pattern = "uid={0},ou=users,dc=example,dc=com"
    manager_dn      = "cn=admin,dc=example,dc=com"
    manager_password = "secret" # Use AWS Secrets Manager in production
  }
}
```

**Production Recommendation**: Store sensitive credentials in AWS Secrets Manager and reference them via data sources.

### Resource Limits

Configure resource requests and limits for ShinyProxy pods:

```hcl
shinyproxy_resources = {
  requests = {
    memory = "512Mi"
    cpu    = "250m"
  }
  limits = {
    memory = "2Gi"
    cpu    = "1000m"
  }
}
```

### Advanced ShinyProxy Settings

- `shinyproxy_replicas`: Number of ShinyProxy instances (default: 2)
- `shinyproxy_port`: Service port (default: 8080)
- `shinyproxy_image_pull_policy`: Image pull policy (default: IfNotPresent)
- `enable_shinyproxy_ecr_access`: Enable ECR access via IAM role (default: true)

## Security Best Practices

### 1. KMS Encryption

The module automatically enables:

- **Secrets encryption**: All Kubernetes secrets encrypted with customer-managed KMS key
- **Key rotation**: Automatic rotation every 90 days (configurable)
- **CloudWatch Logs encryption**: Control plane logs encrypted

```hcl
kms_deletion_window_in_days     = 30
kms_key_rotation_period_in_days = 90
```

### 2. Network Security

- **VPC Flow Logs**: Enabled by default with configurable retention
- **Private subnets**: EKS nodes deployed in private subnets
- **Security groups**: Minimal required permissions following least privilege
- **NAT Gateways**: High availability across multiple AZs

### 3. IAM and RBAC

- **IRSA (IAM Roles for Service Accounts)**: ShinyProxy uses IRSA for AWS access
- **Least privilege**: Minimal IAM permissions for ECR access
- **Cluster RBAC**: ShinyProxy operator has scoped permissions

### 4. Logging and Monitoring

Enable all EKS control plane logs:

- API server
- Audit
- Authenticator
- Controller Manager
- Scheduler

Logs retained for 90 days (configurable) in CloudWatch Logs.

### 5. Pod Security

ShinyProxy pods run with:

- `runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true`
- Capabilities dropped: ALL
- Seccomp profile: RuntimeDefault

## High Availability

### Multi-AZ Deployment

- **3 Availability Zones**: Resources spread across multiple AZs
- **Auto Scaling**: Node groups scale based on demand
- **ShinyProxy Replicas**: Multiple instances for high availability
- **NAT Gateway Redundancy**: One NAT Gateway per AZ (configurable)

### Cost Optimization

For non-production environments:

```hcl
single_nat_gateway = true # Use single NAT Gateway
```

Use SPOT instances for non-critical workloads:

```hcl
capacity_type = "SPOT"
```

## Upgrading

### EKS Version Upgrades

1. Update the cluster version:

```hcl
cluster_version = "1.35"
```

2. Update addon versions compatible with new Kubernetes version:

```bash
aws eks describe-addon-versions --kubernetes-version 1.35
```

3. Apply changes:

```bash
terraform plan
terraform apply
```

### ShinyProxy Upgrades

Update the ShinyProxy version:

```hcl
shinyproxy_version = "3.2.2"
```

## Troubleshooting

### First Deployment Authentication Errors

If you encounter "Unauthorized" errors during first deployment like:

```
Error: Unauthorized
  with kubernetes_namespace.shinyproxy
```

This typically means the Kubernetes provider tried to authenticate before the EKS cluster was ready. The module includes automatic wait logic to prevent this, but if it still occurs:

**Solution 1: Re-run terraform apply** (recommended)

```bash
terraform apply
```

The cluster is now created, and the Kubernetes resources will deploy successfully.

**Solution 2: Two-stage deployment**

```bash
# Stage 1: Deploy EKS cluster only
terraform apply -target=module.eks -target=aws_eks_addon.addons

# Stage 2: Deploy Kubernetes resources
terraform apply
```

### Check EKS Cluster Status

```bash
kubectl get nodes
kubectl get pods -A
```

### ShinyProxy Issues

```bash
# Check ShinyProxy operator
kubectl logs -n shinyproxy deployment/shinyproxy-operator

# Check ShinyProxy pods
kubectl logs -n shinyproxy -l app=shinyproxy

# Check ShinyProxy Custom Resource
kubectl get shinyproxy -n shinyproxy -o yaml
```

### Access Issues

```bash
# Verify IAM authentication
aws sts get-caller-identity

# Update kubeconfig
aws eks update-kubeconfig --region <region> --name <cluster-name>

# Check RBAC permissions
kubectl auth can-i --list
```

### Addon Issues

```bash
# Check addon status
aws eks describe-addon --cluster-name <cluster-name> --addon-name vpc-cni

# View addon logs
kubectl logs -n kube-system -l k8s-app=aws-node
```

## Outputs

Key outputs available after deployment:

| Output | Description |
|--------|-------------|
| `cluster_endpoint` | EKS cluster API endpoint |
| `cluster_name` | EKS cluster name |
| `configure_kubectl` | Command to configure kubectl |
| `shinyproxy_url` | ShinyProxy access URL |
| `shinyproxy_load_balancer_hostname` | Load balancer hostname |
| `kms_key_arn` | KMS key ARN for encryption |

View all outputs:

```bash
terraform output
```

## Cost Considerations

Estimated monthly costs (us-west-2):

- **EKS Control Plane**: ~$73/month
- **NAT Gateways (3 AZs)**: ~$97/month
- **EC2 Instances (3x t3.large)**: ~$190/month
- **EBS Volumes**: ~$15/month
- **Data Transfer**: Variable

**Total**: ~$375-400/month (excluding data transfer)

Cost optimization tips:

1. Use single NAT Gateway for dev: saves ~$65/month
2. Use SPOT instances: saves ~40-70% on compute
3. Right-size node groups based on actual usage
4. Use scheduled scaling for non-production environments

## Compliance and Standards

This module follows:

- **AWS Well-Architected Framework**
  - Operational Excellence
  - Security
  - Reliability
  - Performance Efficiency
  - Cost Optimization

- **CIS Amazon EKS Benchmark**: Implements security recommendations
- **HIPAA/PCI**: Supports compliance requirements with encryption and logging

## Production Readiness Checklist

- [ ] Configure authentication (not "none")
- [ ] Review and adjust resource limits
- [ ] Enable private endpoint access only (set `cluster_endpoint_public_access = false`)
- [ ] Configure backup strategy for persistent data
- [ ] Set up monitoring and alerting (CloudWatch, Prometheus)
- [ ] Configure DNS for ShinyProxy load balancer
- [ ] Enable AWS Config for compliance tracking
- [ ] Set up disaster recovery procedures
- [ ] Document runbooks for common operations
- [ ] Implement GitOps workflow for application deployments
- [ ] Configure network policies for pod-to-pod communication
- [ ] Set up centralized logging (ELK, CloudWatch Insights)

## Support and Contributing

For issues or questions:

1. Check the troubleshooting section
2. Review AWS EKS documentation
3. Review ShinyProxy documentation: <https://www.shinyproxy.io/>
4. Check Terraform AWS provider documentation

## License

This module is provided as-is for deployment of EKS with ShinyProxy.

## References

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [ShinyProxy Documentation](https://www.shinyproxy.io/documentation/)
- [ShinyProxy Operator](https://github.com/openanalytics/shinyproxy-operator)
- [Terraform AWS EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

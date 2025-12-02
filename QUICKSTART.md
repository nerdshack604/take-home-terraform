# Quick Start Guide

Get your EKS cluster with ShinyProxy running in under 30 minutes.

## 5-Minute Setup

```bash
# 1. Configure AWS credentials
aws configure

# 2. Copy configuration template
cp terraform.tfvars.example terraform.tfvars

# 3. Edit minimum required variables
cat > terraform.tfvars <<EOF
project_name = "shinyproxy-demo"
environment  = "dev"
cluster_name = "shinyproxy-cluster"
availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]

# Cost-saving for dev
single_nat_gateway = true

# Simple node configuration
node_groups = {
  default = {
    min_size       = 2
    max_size       = 4
    desired_size   = 2
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 50
    labels         = {}
    taints         = []
  }
}
EOF
```

## Deploy

```bash
# Initialize and deploy
terraform init
terraform apply -auto-approve

# Wait ~15-20 minutes for deployment
```

## Access

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-west-2 --name shinyproxy-cluster

# Verify
kubectl get nodes

# Get ShinyProxy URL
echo "ShinyProxy URL: $(terraform output -raw shinyproxy_url)"
```

## Test ShinyProxy

```bash
# Wait for load balancer (2-3 minutes)
kubectl get svc -n shinyproxy shinyproxy -w

# Access ShinyProxy
open "http://$(terraform output -raw shinyproxy_load_balancer_hostname)"
```

## Add Your First App

Edit `terraform.tfvars`:

```hcl
shinyproxy_apps = [
  {
    id              = "hello"
    display_name    = "Hello World"
    description     = "Test application"
    container_image = "openanalytics/shinyproxy-demo"
    container_cmd   = ["R", "-e", "shiny::runApp('/root/shinyproxy-demo')"]
    container_env   = {}
    port            = 3838
  }
]
```

Apply:

```bash
terraform apply -auto-approve
```

## Common Commands

```bash
# View cluster info
kubectl cluster-info

# View all resources
kubectl get all -A

# View ShinyProxy logs
kubectl logs -n shinyproxy deployment/shinyproxy-operator

# Scale nodes
kubectl get nodes
kubectl scale deployment -n shinyproxy shinyproxy --replicas=3

# Destroy everything
terraform destroy -auto-approve
```

## Next Steps

- Review [README.md](README.md) for full documentation
- Read [SECURITY.md](SECURITY.md) before going to production
- Follow [DEPLOYMENT.md](DEPLOYMENT.md) for production deployment

## Production Checklist

Before deploying to production:

- [ ] Change `environment = "production"`
- [ ] Set `single_nat_gateway = false` (HA)
- [ ] Configure authentication (not "none")
- [ ] Set `cluster_endpoint_public_access = false`
- [ ] Review and adjust node sizes
- [ ] Configure monitoring
- [ ] Set up backups
- [ ] Configure DNS
- [ ] Enable TLS/SSL
- [ ] Review security settings

## Troubleshooting

**Deployment fails?**

```bash
terraform destroy -auto-approve
terraform apply -auto-approve
```

**Can't access cluster?**

```bash
aws eks update-kubeconfig --region us-west-2 --name shinyproxy-cluster
```

**ShinyProxy not accessible?**

```bash
kubectl get svc -n shinyproxy shinyproxy
# Wait for EXTERNAL-IP to show (not <pending>)
```

**Need help?**

- Check CloudWatch logs
- Review `kubectl get events -A`
- See DEPLOYMENT.md troubleshooting section

## Costs

Development deployment (~$150-200/month):

- EKS Control Plane: $73
- 2x t3.medium nodes: $61
- 1 NAT Gateway: $32
- EBS volumes: $10
- Load balancer: $16

Production deployment (~$375-400/month):

- EKS Control Plane: $73
- 3x t3.large nodes: $190
- 3 NAT Gateways: $97
- EBS volumes: $15
- Load balancer: $16

Reduce costs:

- Use SPOT instances (-40-70%)
- Smaller instance types
- Single NAT Gateway for dev
- Schedule scaling

# Isolated EC2 with Cloudflare Tunnel

This Terraform configuration creates an EC2 instance in a completely isolated VPC (no Internet Gateway) that can be accessed via AWS Session Manager and expose applications through Cloudflare Tunnel.

## Architecture

- **VPC**: Private VPC without Internet Gateway
- **EC2**: Ubuntu 22.04 instance in private subnet
- **Access**: AWS Session Manager via VPC endpoints
- **Outbound**: Applications exposed via Cloudflare Tunnel (manually configured)

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform installed (>= 1.0)
3. Cloudflare account and tunnel configuration (for manual setup)

## Usage

1. Initialize Terraform:
```bash
terraform init
```

2. Review the plan:
```bash
terraform plan
```

3. Apply the configuration:
```bash
terraform apply
```

4. Connect to the instance:
```bash
# Use the command from the terraform output
aws ssm start-session --target <instance-id> --region us-west-1
```

5. Once connected, manually install and configure Cloudflare Tunnel:
```bash
# Download and install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
sudo dpkg -i cloudflared.deb

# Configure your tunnel with your token
sudo cloudflared service install <your-tunnel-token>
```

## Configuration

Key variables in `variables.tf`:
- `aws_region`: AWS region (default: us-west-1)
- `project_name`: Project name for resource naming (default: cyrus)
- `instance_type`: EC2 instance type (default: t3.micro)
- `root_volume_size`: EBS volume size in GB (default: 128)

## Security Notes

- No direct internet access (no IGW)
- All access via AWS Session Manager
- VPC endpoints for AWS services only
- Outbound connectivity only through Cloudflare Tunnel

## Cleanup

To destroy all resources:
```bash
terraform destroy
```
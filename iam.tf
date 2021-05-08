
resource "aws_eks_cluster" "cluster" { # Here we create the EKS cluster itself.
  name = var.cluster_name 
  role_arn = aws_iam_role.eks_cluster.arn # The cluster needs an IAM role to gain some permission over your AWS account

  vpc_config {
    subnet_ids = concat(module.vpc.public_subnets, module.vpc.private_subnets) # We pass all 6 subnets (public and private ones). Retrieved from the AWS module before.
    endpoint_public_access = true # The cluster will have a public endpoint. We will be able to call it from the public internet.
    endpoint_private_access = true # STEP 3: The cluster will have a private endpoint too. Worker nodes will be able to call the control plane without leaving the VPC.
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"] # We enable control plane components logging against Amazon Cloudwatch log group. 

  # Ensure that IAM Role permissions are handled before the EKS Cluster.
  depends_on = [
    aws_iam_role_policy_attachment.policy-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.policy-AmazonEKSVPCResourceController,
    aws_cloudwatch_log_group.eks_cluster_control_plane_components
  ]
}

resource "aws_iam_role" "eks_cluster" { 
  name = "${var.cluster_name}_role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "policy-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "policy-AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_cloudwatch_log_group" "eks_cluster_control_plane_components" { # To log control plane components
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 2
}


# Step 4: Configuring the Kubectl CLI


resource "null_resource" "generate_kubeconfig" { # Generate a kubeconfig (needs aws cli >=1.62 and kubectl)

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${var.cluster_name}"
  }

  depends_on = [aws_eks_cluster.cluster]
}


# Step 5: Integrating Service Accounts with IAM role


data "tls_certificate" "cluster" {
  url = aws_eks_cluster.cluster.identity.0.oidc.0.issuer
}

resource "aws_iam_openid_connect_provider" "cluster" { # We need an open id connector to allow our service account to assume an IAM role
  client_id_list = ["sts.amazonaws.com"]
thumbprint_list = concat([data.tls_certificate.cluster.certificates.0.sha1_fingerprint], [])
  url = aws_eks_cluster.cluster.identity.0.oidc.0.issuer
}
provider "aws" {
  region = var.region
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}


provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  version                = "~> 2.0.1"
}

data "aws_availability_zones" "available" {
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.47.0"

  name                 = "k8s-vpc"
  cidr                 = "172.16.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
  public_subnets       = ["172.16.4.0/24", "172.16.5.0/24", "172.16.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
     sre_candidate = "Akshay Chopra"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
    sre_candidate = "Akshay Chopra"
  }
  tags =  {
      sre_candidate = "Akshay Chopra"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "15.2.0"

//change
  cluster_name    =  var.cluster_name
  cluster_version = "1.18"
  subnets         = module.vpc.private_subnets

  vpc_id = module.vpc.vpc_id

  node_groups = {
    spot = {
      name             = "${var.cluster_name}-spot-workers"
      desired_capacity = 4
      max_capacity     = 10
      min_capacity     = 3
      instance_types  = ["t2.small","t2.medium","t2.micro"]
      capacity_type = "SPOT"
      disk_size = 5
    }

    demand = {
      name                    = "${var.cluster_name}-demand-workers"
      desired_capacity = 4
      max_capacity     = 10
      min_capacity     = 3
      capacity_type = "ON_DEMAND"
      instance_types  = ["t2.small","t2.medium","t2.micro"]
      disk_size = 5
    }

      demand_2 = {
      name                    = "${var.cluster_name}-demand2-workers"
      desired_capacity = 4
      max_capacity     = 10
      min_capacity     = 3
      capacity_type = "ON_DEMAND"
      instance_types  = ["t2.small"]
      disk_size = 5
    }

  }

  write_kubeconfig   = true
  config_output_path = "./"
  tags =  {
      sre_candidate = "Akshay Chopra"
  }
}

data "tls_certificate" "cluster" {
  url =data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer
}

resource "aws_iam_openid_connect_provider" "cluster" { # We need an open id connector to allow our service account to assume an IAM role
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = concat([data.tls_certificate.cluster.certificates.0.sha1_fingerprint], [])
  url = data.tls_certificate.cluster.url
}


module "alb_ingress_controller" {
  source  = "iplabs/alb-ingress-controller/kubernetes"
  version = "3.1.0"


  k8s_cluster_type = "eks"
  k8s_namespace    = "kube-system"

  aws_region_name  =  var.region
  k8s_cluster_name =  module.eks.cluster_id
  aws_tags =  {
      sre_candidate = "Akshay Chopra"
  }
}

resource "null_resource" "generate_kubeconfig" { # Generate a kubeconfig (needs aws cli >=1.62 and kubectl)
triggers = {
    cluster_instance_id = data.aws_eks_cluster.cluster.id
  }
    provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${var.cluster_name}"
  }
}

resource "aws_iam_role" "cluster_autoscale" {
  name = "eks_cluster_autoscaler_role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_policy" "cluster_autoscale" {
  name = "cluster_autoscaler_policy"
  policy =  file("${path.module}/policies/cluster-autoscaler-policy.json") 
}

resource "aws_iam_role_policy_attachment" "cluster-autoscale" {
  role       = aws_iam_role.cluster_autoscale.name
  policy_arn = aws_iam_policy.cluster_autoscale.arn
}

data "template_file" "cluster_autoscaler_yaml" { # Generate the cluster autoscaler from a template
  template = file("${path.module}/templates/cluster-autoscaler.yaml.tpl") 

  vars = {
    cluster_name = var.cluster_name
  }
}

data "template_file" "metric_server_yaml" { # Generate the cluster autoscaler from a template
  template = file("${path.module}/templates/metric-server.yaml.tpl") 

  vars = {
    cluster_name = var.cluster_name
  }
}

resource "null_resource" "cluster_autoscaler_install-new" { # Install the cluster autoscaler
triggers = {
    cluster_instance_id = data.aws_eks_cluster.cluster.id
  }
    provisioner "local-exec" {
    command = "echo '${data.template_file.cluster_autoscaler_yaml.rendered}' > cluster_autoscaler.yaml && kubectl apply -f cluster_autoscaler.yaml && rm cluster_autoscaler.yaml && kubectl annotate serviceaccount cluster-autoscaler -n kube-system  eks.amazonaws.com/role-arn=arn:aws:iam::${var.accountId}:role/eks_cluster_autoscaler_role"
  }

  depends_on = [null_resource.generate_kubeconfig]
}


resource "null_resource" "metric_server_install" { # Install the cluster autoscaler
triggers = {
    cluster_instance_id = data.aws_eks_cluster.cluster.id
  }
    provisioner "local-exec" {
    command = "echo '${data.template_file.metric_server_yaml.rendered}' > metric-server.yaml && kubectl apply -f metric-server.yaml"
  }

  depends_on = [null_resource.generate_kubeconfig]
}
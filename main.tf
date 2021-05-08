# provider "aws" {
#   region = "us-west-2"
# }

# data "aws_eks_cluster" "cluster" {
#   name = module.eks.cluster_id
# }

# data "aws_eks_cluster_auth" "cluster" {
#   name = module.eks.cluster_id
# }

# provider "kubernetes" {
#   host                   = data.aws_eks_cluster.cluster.endpoint
#   cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
#   token                  = data.aws_eks_cluster_auth.cluster.token
#   load_config_file       = false
#   version                = "~> 1.11"
# }

# data "aws_availability_zones" "available" {
# }

# locals {
#   cluster_name = "test-cluster-1"
# }

# module "vpc" {
#   source  = "terraform-aws-modules/vpc/aws"
#   version = "2.47.0"

#   name                 = "k8s-vpc"
#   cidr                 = "172.16.0.0/16"
#   azs                  = data.aws_availability_zones.available.names
#   private_subnets      = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
#   public_subnets       = ["172.16.4.0/24", "172.16.5.0/24", "172.16.6.0/24"]
#   enable_nat_gateway   = true
#   single_nat_gateway   = true
#   enable_dns_hostnames = true

#   public_subnet_tags = {
#     "kubernetes.io/cluster/${local.cluster_name}" = "shared"
#     "kubernetes.io/role/elb"                      = "1"
#   }

#   private_subnet_tags = {
#     "kubernetes.io/cluster/${local.cluster_name}" = "shared"
#     "kubernetes.io/role/internal-elb"             = "1"
#   }
# }

# module "eks" {
#   source  = "terraform-aws-modules/eks/aws"
#   version = "12.2.0"

#   cluster_name    = "${local.cluster_name}"
#   cluster_version = "1.18"
#   subnets         = module.vpc.private_subnets

#   vpc_id = module.vpc.vpc_id

#   node_groups = {
#     first = {
#       desired_capacity = 1
#       max_capacity     = 10
#       min_capacity     = 1

#       instance_type = "m5.large"
#     }


#   }

#   write_kubeconfig   = true
#   config_output_path = "./"
# }


# # Step 6: Adding the worker nodes + CNI + Kubernetes Cluster Autoscaler


# resource "null_resource" "install_calico" { # The node won't enter the ready state without a CNI initialized
#   provisioner "local-exec" {
#     command = "kubectl apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml"
#   }

#   depends_on = [null_resource.generate_kubeconfig]
# }

# data "template_file" "aws_auth_configmap" { # Generates the aws-auth, otherwise, worker node can't join. Use this cm to add users/role to your cluster

#   template = file("${path.module}/aws-auth-cm.yaml.tpl")

#   vars = {
#     arn_instance_role = aws_iam_role.node_group.arn
#   }
# }

# resource "null_resource" "apply_aws_auth_configmap" { # Apply the aws-auth config map

#   provisioner "local-exec" {
#     command = "echo '${data.template_file.aws_auth_configmap.rendered}' > aws-auth-cm.yaml && kubectl apply -f aws-auth-cm.yaml && rm aws-auth-cm.yaml"
#   }
  

#   depends_on = [null_resource.generate_kubeconfig]
# }

# resource "aws_eks_node_group" "node_group_spot" { # node group for spot Instances type
#   cluster_name    = aws_eks_cluster.cluster.name
#   node_group_name = "fnode_group-${substr(module.vpc.private_subnets[count.index], 7, length(module.vpc.private_subnets[count.index]))}"
#   node_role_arn   = aws_iam_role.node_group.arn
#   subnet_ids      = concat(module.vpc.public_subnets, module.vpc.private_subnets)
#   capacity_type   = SPOT
#   instance_types  = ["t2.micro", "t2.small", "t2.medium"]
#   scaling_config {
#     desired_size = 1
#     max_size     = 6
#     min_size     = 1
#   }

#   depends_on = [null_resource.apply_aws_auth_configmap]
# }


# resource "aws_eks_node_group" "node_group_demandx" { # node group for spot Instances type
#   cluster_name    = aws_eks_cluster.cluster.name
#   node_group_name = "fnode_group-${substr(module.vpc.private_subnets[count.index], 7, length(module.vpc.private_subnets[count.index]))}"
#   node_role_arn   = aws_iam_role.node_group.arn
#   subnet_ids      = concat(module.vpc.public_subnets, module.vpc.private_subnets)
#   capacity_type   = DEMAND
#     instance_types  = ["t2.micro", "t2.small", "t2.medium"]

#   scaling_config {
#     desired_size = 1
#     max_size     = 3
#     min_size     = 1
#   }

#   depends_on = [null_resource.apply_aws_auth_configmap]
# }

# resource "aws_iam_role" "node_group" {
#   name = "eks_node_group_role"

#   assume_role_policy = jsonencode({
#     Statement = [{
#       Action = "sts:AssumeRole"
#       Effect = "Allow"
#       Principal = {
#         Service = "ec2.amazonaws.com"
#       }
#     }]
#     Version = "2012-10-17"
#   })
# }

# resource "aws_iam_role_policy_attachment" "policy-AmazonEKSWorkerNodePolicy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
#   role       = aws_iam_role.node_group.name
# }

# resource "aws_iam_role_policy_attachment" "policy-AmazonEC2ContainerRegistryReadOnly" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
#   role       = aws_iam_role.node_group.name
# }

# data "template_file" "cluster_autoscaler_yaml" { # Generate the cluster autoscaler from a template
#   template = file("${path.module}/cluster-autoscaler.yaml.tpl") 

#   vars = {
#     cluster_name = aws_eks_cluster.cluster.name
#   }
# }

# resource "null_resource" "cluster_autoscaler_install" { # Install the cluster autoscaler
#   provisioner "local-exec" {
#     command = "echo '${data.template_file.cluster_autoscaler_yaml.rendered}' > cluster_autoscaler.yaml && kubectl apply -f cluster_autoscaler.yaml && rm cluster_autoscaler.yaml"
#   }

#   depends_on = [aws_eks_cluster.cluster, null_resource.generate_kubeconfig]
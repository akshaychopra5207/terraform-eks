variable "cluster_name" {
  description = "The prefix used for all resources"
  default = "test-cluster-2"
}

variable "region" {
  description = "The Azure location where all resources should be created"
  default = "us-west-2"
}


variable "accountId" {
  description = "The AWS account id"
}

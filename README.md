# terraform-eks

 Provisiong terraform from EKS has multiple steps described below

 1. Main.tf - It has all the components like vpc, eks , ingress controller, metric sever and cluster autoscaler and permissions to set up this. It is creating a eks cluster with autoscalling capabilties

 2.  state.tf- It has componenets storage account, dynamo db table and s3 bucket as terraform backend to manage stae files and locking

 3. varibales.tf - used to store three variables cluster name, accountid and region

 4. terraform.tfvars - Input file to specify region and cluster name

 5. versions.tf - to manage versions for different provider plugins

 6. output.tf. It can be used to get and print some output
 
 
 Folders:
Temolates- Yaml Manifests needed for cluster autoscaler and metric sevre Installation
 Policies- Policy used by cluster autoscaler

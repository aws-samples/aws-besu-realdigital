locals {

  name            = basename(path.cwd)
  region          = "us-east-1"
  besu_namespace  = "besu"
  cluster_version = "1.31"

  cluster_endpoint_public_access  = true
  allowed_public_cidrs            = ["0.0.0.0/0"]
  cluster_endpoint_private_access = true

  vpc_cidr = "10.2.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  node_group_name = "managed-ondemand"

  tags = {
    Blueprint  = local.name
    GithubRepo = "terraform-aws-eks"
    project    = "real-digital"
  }

  #Total wait time in seconds. This is wait time for resource wait boostrap to proceed to next.
  genesis_timer   = "30s"
  bootnode_timer  = "30s"
  validator_timer = "30s"
  other_timer     = "15s"
}

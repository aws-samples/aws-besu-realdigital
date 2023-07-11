locals {

  name            = basename(path.cwd)
  region          = data.aws_region.current.name
  besu_namespace  = "besu"
  cluster_version = "1.24"

  vpc_cidr = "10.2.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  node_group_name = "managed-ondemand"

  tags = {
    Blueprint  = local.name
    GithubRepo = "terraform-aws-eks"
    project    = "real-digital"
  }

  #Total wait time in seconds. This is wait time for resource wait boostrap to proceed to next.
  genesis_timer   = "120s"
  bootnode_timer  = "120s"
  validator_timer = "60s"
  other_timer     = "30s"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.13"

  cluster_name                   = local.name
  cluster_version                = "1.24"
  cluster_endpoint_public_access = true
  cluster_enabled_log_types      = ["api", "audit", "authenticator", "controllerManager", "scheduler"] # Backwards compat

  iam_role_name            = "${local.name}-cluster-role" # Backwards compat
  iam_role_use_name_prefix = false                        # Backwards compat

  kms_key_aliases = [local.name] # Backwards compat

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  #Maybe set create_cluster_security_group to FALSE because we're using THAT SECURITY GROUP (USING THE DEFAULT CREATED BY EKS)

  create_cluster_security_group = false
  create_node_security_group    = false



  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/TeamRole"
      username = "ops-role"
      groups   = ["system:masters"]
    },
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    }
  ]

  eks_managed_node_groups = {
    managed = {
      iam_role_name              = "${local.name}-managed" # Backwards compat
      iam_role_use_name_prefix   = false                   # Backwards compat
      use_custom_launch_template = false                   # Backwards compat

      instance_types = ["m5.large"]

      min_size     = 2
      max_size     = 3
      desired_size = 2
      selectors = [{
        namespace = "kube-system"
        labels = {
          Which = "managed"
        }
        },
        {
          namespace = "karpenter"
          labels = {
            Which = "managed"
          }
        }
      ]
    }
  }

  # fargate_profiles = {
  #   fargate = {
  #     iam_role_name            = "${local.name}-fargate" # Backwards compat
  #     iam_role_use_name_prefix = false                   # Backwards compat

  #     selectors = [{
  #       #namespace = "karpenter"
  #       labels = {
  #         Which = "fargate"
  #       }
  #     }]
  #   }
  # }

  # tags = merge(local.tags, {
  #   # NOTE - if creating multiple security groups with this module, only tag the
  #   # security group that Karpenter should utilize with the following tag
  #   # (i.e. - at most, only one security group should have this tag in your account)
  #   "karpenter.sh/discovery" = local.name
  # })
  tags = local.tags
}

module "iam_policy_ebs_csi" {
  source = "terraform-aws-modules/iam/aws//modules/iam-policy"

  name        = "${module.eks.cluster_name}-addon-aws-ebs-csi"
  path        = "/"
  description = "EBS CSI Policy"
  policy      = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ec2:CreateSnapshot",
                "ec2:AttachVolume",
                "ec2:DetachVolume",
                "ec2:ModifyVolume",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInstances",
                "ec2:DescribeSnapshots",
                "ec2:DescribeTags",
                "ec2:DescribeVolumes",
                "ec2:DescribeVolumesModifications"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Condition": {
                "StringEquals": {
                    "ec2:CreateAction": [
                        "CreateVolume",
                        "CreateSnapshot"
                    ]
                }
            },
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": [
                "arn:aws:ec2:*:*:volume/*",
                "arn:aws:ec2:*:*:snapshot/*"
            ],
            "Effect": "Allow"
        },
        {
            "Action": [
                "ec2:DeleteTags"
            ],
            "Resource": [
                "arn:aws:ec2:*:*:volume/*",
                "arn:aws:ec2:*:*:snapshot/*"
            ],
            "Effect": "Allow"
        },
        {
            "Condition": {
                "StringLike": {
                    "aws:RequestTag/ebs.csi.aws.com/cluster": "true"
                }
            },
            "Action": [
                "ec2:CreateVolume"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Condition": {
                "StringLike": {
                    "aws:RequestTag/CSIVolumeName": "*"
                }
            },
            "Action": [
                "ec2:CreateVolume"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Condition": {
                "StringLike": {
                    "aws:RequestTag/kubernetes.io/cluster/*": "owned"
                }
            },
            "Action": [
                "ec2:CreateVolume"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
                }
            },
            "Action": [
                "ec2:DeleteVolume"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/CSIVolumeName": "*"
                }
            },
            "Action": [
                "ec2:DeleteVolume"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/kubernetes.io/cluster/*": "owned"
                }
            },
            "Action": [
                "ec2:DeleteVolume"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/CSIVolumeSnapshotName": "*"
                }
            },
            "Action": [
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
                }
            },
            "Action": [
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
EOF
}

module "iam_role_ebs_csi" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  role_name = "${module.eks.cluster_name}-role-aws-ebs-csi"

  role_policy_arns = {
    policy = module.iam_policy_ebs_csi.arn
  }

  oidc_providers = {
    one = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.12"

  depends_on        = [module.iam_role_ebs_csi]
  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  create_delay_dependencies = [for prof in module.eks.fargate_profiles : prof.fargate_profile_arn]

  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.iam_role_ebs_csi.iam_role_arn
    }
    coredns = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }

  enable_aws_load_balancer_controller = true
  #   aws_load_balancer_controller = {
  #     wait = true
  #   }
  aws_load_balancer_controller = {
    set = [
      {
        name  = "vpcId"
        value = module.vpc.vpc_id # Explicitly set VPC ID
      },
      {
        name  = "region"
        value = local.region
      },
      {
        name  = "clusterName"
        value = module.eks.cluster_name
      }
    ]
  }

  enable_secrets_store_csi_driver              = true
  enable_secrets_store_csi_driver_provider_aws = true
  enable_karpenter                             = true
  karpenter_enable_spot_termination            = true
  karpenter = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
    chart_version       = "0.37.6"
  }

  tags = local.tags
}

resource "aws_ec2_tag" "karpenter_tag_cluster_primary_security_group" {
  resource_id = module.eks.cluster_primary_security_group_id
  key         = "karpenter.sh/discovery"
  value       = local.name
}

# # This should not affect the name of the cluster primary security group
# # Ref: https://github.com/terraform-aws-modules/terraform-aws-eks/pull/2006
# # Ref: https://github.com/terraform-aws-modules/terraform-aws-eks/pull/2008
# #for_each = var.create_additional_tags_for_cluster_security_group ? : { for k, v in merge(var.tags, var.cluster_tags) : k => v if local.create && k != "Name" } : {}

# module "admin_team" {
#   source = "aws-ia/eks-blueprints-teams/aws"

#   name = "admin-team"

#   # Enables elevated, admin privileges for this team
#   enable_admin = true
#   users        = ["arn:aws:iam::999999999:role/Admin"]
#   cluster_arn  = module.eks.cluster_arn

#   tags = {
#     environment = "besu"
#   }
# }

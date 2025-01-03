module "iam_policy_quorum_node_secrets" {
  source = "terraform-aws-modules/iam/aws//modules/iam-policy"

  name        = "${module.eks.cluster_name}-iam_policy_quorum_node_secrets"
  path        = "/"
  description = "Besu Pods to Secret Manager acesses"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{  
    "Effect": "Allow",
    "Action": ["secretsmanager:CreateSecret","secretsmanager:UpdateSecret","secretsmanager:DescribeSecret","secretsmanager:GetSecretValue","secretsmanager:PutSecretValue","secretsmanager:ReplicateSecretToRegions","secretsmanager:TagResource"],
    "Resource": ["arn:aws:secretsmanager:${local.region}:${data.aws_caller_identity.current.account_id}:secret:besu-node-*"]
  }]
}
EOF
}

module "iam_role_quorum_node_secrets" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  role_name = "${module.eks.cluster_name}-quorum-node-secrets-sa"

  role_policy_arns = {
    policy = module.iam_policy_quorum_node_secrets.arn
  }

  oidc_providers = {
    one = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["besu:quorum-node-secrets-sa"]
    }
  }
}

resource "kubernetes_namespace" "k8s-besu-namespace" {
  depends_on = [module.iam_policy_quorum_node_secrets, module.iam_role_quorum_node_secrets, kubectl_manifest.karpenter_provisioner, kubernetes_storage_class.ebs_sc]
  metadata {
    name = local.besu_namespace
  }
}

resource "kubernetes_service_account" "k8s-quorum-node-secrets-sa" {
  metadata {
    name      = "quorum-node-secrets-sa"
    namespace = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
    annotations = {
      "eks.amazonaws.com/role-arn" : "${module.iam_role_quorum_node_secrets.iam_role_arn}"
    }
  }
}

resource "helm_release" "monitoring" {
  name       = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "59.1.0"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  # timeout    = 900 #15 minutes
  # # Enable CRD installation
  # set {
  #   name  = "prometheusOperator.createCustomResource"
  #   value = "true"
  # }
  # values = [
  #   # file("${path.module}/quorum-kubernetes/helm/values/monitoring.yml")
  #   file("${path.module}/kube-prometheus-values.yml")
  # ]
}

resource "kubectl_manifest" "alerting-besu-nodes" {
  depends_on = [helm_release.monitoring]
  yaml_body  = file("${path.module}/quorum-kubernetes/helm/values/monitoring/alerting-besu-nodes.yml")
}

resource "kubectl_manifest" "grafana-besu-dashboard" {
  depends_on = [helm_release.monitoring]
  yaml_body  = file("${path.module}/quorum-kubernetes/helm/values/monitoring/grafana-besu-dashboard.yml")
}

resource "helm_release" "elasticsearch" {
  depends_on = [helm_release.monitoring]
  name       = "elasticsearch"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  version    = "7.17.1"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/elasticsearch.yml")
  ]
}

resource "helm_release" "kibana" {
  depends_on = [helm_release.elasticsearch]
  name       = "kibana"
  repository = "https://helm.elastic.co"
  chart      = "kibana"
  version    = "7.17.1"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/kibana.yml")
  ]
}

resource "helm_release" "filebeat" {
  depends_on = [helm_release.elasticsearch]
  name       = "filebeat"
  repository = "https://helm.elastic.co"
  chart      = "filebeat"
  version    = "7.17.1"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/filebeat.yml")
  ]
}

resource "aws_security_group" "monitoring-ingress-nginx" {
  name        = "${module.eks.cluster_name}-monitoring-ingress-nginx"
  description = "Allow public HTTP and HTTPS traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # modify to your requirements
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # modify to your requirements
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}
module "monitoring-ingress-nginx" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.12"

  depends_on = [helm_release.monitoring]

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_ingress_nginx = true

  ingress_nginx = {
    name          = "monitoring-ingress-nginx"
    namespace     = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
    chart         = "ingress-nginx"
    chart_version = "4.7.1"
    repository    = "https://kubernetes.github.io/ingress-nginx"
    wait          = true

    values = [
      <<-EOT
          controller:
            replicaCount: 2
            image:
              registry: registry.k8s.io
              image: ingress-nginx/controller
              tag: "v1.8.1"
              digest: ""
            admissionWebhooks:
              patch:
                image:
                  registry: registry.k8s.io
                  image: ingress-nginx/kube-webhook-certgen
                  tag: "v1.3.0"
                  digest: ""
            service:
              annotations:
                service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
                service.beta.kubernetes.io/aws-load-balancer-scheme: internal
                service.beta.kubernetes.io/aws-load-balancer-security-groups: ${aws_security_group.monitoring-ingress-nginx.id}
                service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules: true
              loadBalancerClass: service.k8s.aws/nlb
            topologySpreadConstraints:
              - maxSkew: 1
                topologyKey: topology.kubernetes.io/zone
                whenUnsatisfiable: ScheduleAnyway
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/instance: monitoring-ingress-nginx
              - maxSkew: 1
                topologyKey: kubernetes.io/hostname
                whenUnsatisfiable: ScheduleAnyway
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/instance: monitoring-ingress-nginx
            minAvailable: 1
            ingressClassResource:
              name: monitoring-ingress-nginx
              enabled: true
              default: false
              controllerValue: k8s.io/monitoring-ingress-nginx
        EOT
    ]
  }
}
resource "kubectl_manifest" "ingress-rules-monitoring-ingress" {
  depends_on = [module.monitoring-ingress-nginx]
  yaml_body  = file("${path.module}/quorum-kubernetes/ingress/ingress-rules-monitoring.yml")
}

######### CREATE BESU CLUSTER ##########
resource "helm_release" "genesis" {
  depends_on = [kubectl_manifest.ingress-rules-monitoring-ingress, kubernetes_service_account.k8s-quorum-node-secrets-sa]
  # depends_on = [kubernetes_service_account.k8s-quorum-node-secrets-sa]
  name       = "genesis"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "besu-genesis"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/genesis-besu.yml")
  ]
}

resource "time_sleep" "wait_for_genesis" {
  create_duration = local.genesis_timer

  depends_on = [helm_release.genesis]
}

resource "helm_release" "bootnode-1" {
  depends_on = [time_sleep.wait_for_genesis]
  name       = "bootnode-1"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "besu-node"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/bootnode.yml")
  ]
}

resource "time_sleep" "wait_for_bootnode1" {
  create_duration = local.bootnode_timer
  depends_on      = [helm_release.bootnode-1]
}

resource "helm_release" "bootnode-2" {
  depends_on = [time_sleep.wait_for_bootnode1]
  name       = "bootnode-2"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "besu-node"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/bootnode.yml")
  ]
}

resource "time_sleep" "wait_for_bootnodes" {
  create_duration = local.bootnode_timer

  depends_on = [helm_release.bootnode-1, helm_release.bootnode-2]
}

resource "helm_release" "validator-1" {
  depends_on = [time_sleep.wait_for_bootnodes]
  name       = "validator-1"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "besu-node"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/validator-a.yml")
  ]
}

resource "time_sleep" "wait_for_validator1" {
  create_duration = local.validator_timer

  depends_on = [helm_release.validator-1]
}

resource "helm_release" "validator-2" {
  depends_on = [time_sleep.wait_for_validator1]
  name       = "validator-2"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "besu-node"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/validator-a.yml")
  ]
}

resource "time_sleep" "wait_for_validator2" {
  create_duration = local.validator_timer

  depends_on = [helm_release.validator-2]
}

resource "helm_release" "validator-3" {
  depends_on = [time_sleep.wait_for_validator2]
  name       = "validator-3"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "besu-node"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/validator-b.yml")
  ]
}

resource "time_sleep" "wait_for_validator3" {
  create_duration = local.validator_timer

  depends_on = [helm_release.validator-3]
}

resource "helm_release" "validator-4" {
  depends_on = [time_sleep.wait_for_validator3]
  name       = "validator-4"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "besu-node"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/validator-b.yml")
  ]
}

resource "time_sleep" "wait_for_validator4" {
  create_duration = local.validator_timer

  depends_on = [helm_release.validator-4]
}

resource "helm_release" "validator-5" {
  depends_on = [time_sleep.wait_for_validator4]
  name       = "validator-5"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "besu-node"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/validator-c.yml")
  ]
}

resource "time_sleep" "wait_for_validator5" {
  create_duration = local.validator_timer

  depends_on = [helm_release.validator-5]
}

resource "helm_release" "validator-6" {
  depends_on = [time_sleep.wait_for_validator5]
  name       = "validator-6"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "besu-node"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/validator-c.yml")
  ]
}

resource "time_sleep" "wait_for_validator6" {
  create_duration = local.validator_timer

  depends_on = [helm_release.validator-6]
}

resource "helm_release" "rpc-1" {
  depends_on = [time_sleep.wait_for_validator6]
  name       = "rpc-1"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "besu-node"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/reader.yml")
  ]
}

resource "time_sleep" "wait_for_rpc-1" {
  create_duration = local.other_timer

  depends_on = [helm_release.rpc-1]
}

resource "helm_release" "member-1" {
  depends_on = [time_sleep.wait_for_rpc-1]
  name       = "member-1"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "besu-node"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/txnode.yml")
  ]
}

resource "time_sleep" "wait_for_member-1" {
  create_duration = local.other_timer

  depends_on = [helm_release.member-1]
}

resource "helm_release" "member-2" {
  depends_on = [time_sleep.wait_for_member-1]
  name       = "member-2"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "besu-node"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/txnode.yml")
  ]
}

resource "time_sleep" "wait_for_member-2" {
  create_duration = local.other_timer

  depends_on = [helm_release.member-2]
}

# # resource "helm_release" "member-3" {
# #   depends_on = [helm_release.validator-4]
# #   name       = "member-3"
# #   repository = "${path.module}/quorum-kubernetes/helm/charts"
# #   chart      = "besu-node"
# #   namespace = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
# #   wait = "true"
# #   values = [
# #     file("${path.module}/quorum-kubernetes/helm/values/txnode.yml")
# #   ]
# # }

resource "aws_security_group" "besu-ingress-nginx" {
  name        = "${module.eks.cluster_name}-besu-nginx-external"
  description = "Allow public HTTP and HTTPS traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # modify to your requirements
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # modify to your requirements
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}
module "besu-ingress-nginx" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.12"

  depends_on = [helm_release.monitoring]

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_ingress_nginx = true

  ingress_nginx = {
    name          = "besu-ingress-nginx"
    namespace     = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
    chart         = "ingress-nginx"
    chart_version = "4.7.1"
    repository    = "https://kubernetes.github.io/ingress-nginx"
    wait          = true

    values = [
      <<-EOT
          controller:
            replicaCount: 2
            service:
              annotations:
                service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
                service.beta.kubernetes.io/aws-load-balancer-scheme: internal
                service.beta.kubernetes.io/aws-load-balancer-security-groups: ${aws_security_group.besu-ingress-nginx.id}
                service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules: true
              loadBalancerClass: service.k8s.aws/nlb
            topologySpreadConstraints:
              - maxSkew: 1
                topologyKey: topology.kubernetes.io/zone
                whenUnsatisfiable: ScheduleAnyway
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/instance: besu-ingress-nginx
              - maxSkew: 1
                topologyKey: kubernetes.io/hostname
                whenUnsatisfiable: ScheduleAnyway
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/instance: besu-ingress-nginx
            minAvailable: 1
            ingressClassResource:
              name: besu-ingress-nginx
              enabled: true
              default: false
              controllerValue: k8s.io/besu-ingress-nginx

        EOT
    ]
  }
}
resource "kubectl_manifest" "ingress-rules-besu" {
  depends_on = [time_sleep.wait_for_member-2, module.besu-ingress-nginx]
  yaml_body  = file("${path.module}/quorum-kubernetes/ingress/ingress-rules-besu.yml")
}

resource "helm_release" "quorum-explorer" {
  depends_on = [kubectl_manifest.ingress-rules-besu]
  name       = "quorum-explorer"
  repository = "${path.module}/quorum-kubernetes/helm/charts"
  chart      = "explorer"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/explorer-besu.yaml")
  ]
}

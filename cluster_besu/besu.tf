module "iam_policy_quorum_node_secrets" {
  source = "terraform-aws-modules/iam/aws//modules/iam-policy"

  name        = "iam_policy_quorum_node_secrets"
  path        = "/"
  description = "Besu Pods to Secret Manager acesses"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{  
    "Effect": "Allow",
    "Action": ["secretsmanager:CreateSecret","secretsmanager:UpdateSecret","secretsmanager:DescribeSecret","secretsmanager:GetSecretValue","secretsmanager:PutSecretValue","secretsmanager:ReplicateSecretToRegions","secretsmanager:TagResource"],
    "Resource": ["arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:besu-node-*"]
  }]
}
EOF
}

module "iam_role_quorum_node_secrets" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  role_name = "quorum-node-secrets-sa"

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
  depends_on = [module.iam_policy_quorum_node_secrets, module.iam_role_quorum_node_secrets, kubectl_manifest.karpenter_provisioner]
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
  version    = "34.10.0"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  values = [
    file("${path.module}/quorum-kubernetes/helm/values/monitoring.yml")
  ]
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

resource "helm_release" "ingress-nginx" {
  depends_on = [helm_release.monitoring]
  name       = "quorum-monitoring-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.7.1"
  namespace  = kubernetes_namespace.k8s-besu-namespace.metadata.0.name
  wait       = "true"
  set {
    name  = "controller.ingressClassResource.name"
    value = "monitoring-nginx"
  }
  set {
    name  = "controller.ingressClassResource.controllerValue"
    value = "k8s.io/monitoring-ingress-nginx"
  }
  set {
    name  = "controller.replicaCount"
    value = 1
  }
  set {
    name  = "controller.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }
  set {
    name  = "defaultBackend.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }
  set {
    name  = "controller.admissionWebhooks.patch.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }
  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }
}

resource "kubectl_manifest" "ingress-rules-monitoring-ingress" {
  depends_on = [helm_release.ingress-nginx]
  yaml_body  = file("${path.module}/quorum-kubernetes/ingress/ingress-rules-monitoring.yml")
}

######### CREATE BESU CLUSTER ##########
resource "helm_release" "genesis" {
  depends_on = [kubectl_manifest.ingress-rules-monitoring-ingress, kubernetes_service_account.k8s-quorum-node-secrets-sa]
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
    file("${path.module}/quorum-kubernetes/helm/values/validator.yml")
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
    file("${path.module}/quorum-kubernetes/helm/values/validator.yml")
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
    file("${path.module}/quorum-kubernetes/helm/values/validator.yml")
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
    file("${path.module}/quorum-kubernetes/helm/values/validator.yml")
  ]
}

resource "time_sleep" "wait_for_validator4" {
  create_duration = local.validator_timer

  depends_on = [helm_release.validator-4]
}

resource "helm_release" "rpc-1" {
  depends_on = [time_sleep.wait_for_validator4]
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

resource "kubectl_manifest" "ingress-rules-besu" {
  depends_on = [time_sleep.wait_for_member-2]
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

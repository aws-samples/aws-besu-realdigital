################################################################################
# Karpenter
################################################################################

resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body  = <<-YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: default
    spec:
      requirements:
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["c", "m", "r"]
        - key: "karpenter.k8s.aws/instance-cpu"
          operator: In
          values: ["2", "4", "8", "16", "32"]
        - key: "karpenter.k8s.aws/instance-hypervisor"
          operator: In
          values: ["nitro"]
        - key: "topology.kubernetes.io/zone"
          operator: In
          values: ${jsonencode(local.azs)}
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "karpenter.sh/capacity-type" # If not included, the webhook for the AWS cloud provider will default to on-demand
          operator: In
          values: ["on-demand"]
      kubeletConfiguration:
        containerRuntime: containerd
        maxPods: 110
      limits:
        resources:
          cpu: 100
      consolidation:
        enabled: false
      providerRef:
        name: default
      ttlSecondsUntilExpired: 604800 # 7 Days = 7 * 24 * 60 * 60 Seconds
      ttlSecondsAfterEmpty: 30
  YAML
  depends_on = [module.eks_blueprints_addons, aws_ec2_tag.karpenter_tag_cluster_primary_security_group, kubectl_manifest.karpenter_node_template]
}

resource "kubectl_manifest" "karpenter_node_template" {
  yaml_body  = <<-YAML
    apiVersion: karpenter.k8s.aws/v1alpha1
    kind: AWSNodeTemplate
    metadata:
      name: default
    spec:
      subnetSelector:
        karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelector:
        karpenter.sh/discovery: ${module.eks.cluster_name}
      instanceProfile: ${module.eks_blueprints_addons.karpenter.node_instance_profile_name}
      tags:
        managed-by: "karpenter"
  YAML
  depends_on = [module.eks_blueprints_addons]
}

# resource "null_resource" "sleep_before_destroy" {
#   depends_on = [module.eks_blueprints_addons]
#   triggers = {
#     # Add any relevant triggers here
#   }

#   provisioner "local-exec" {
#     command = "sleep 30" # Sleep for 5 minutes (300 seconds)
#     when    = destroy
#   }
# }

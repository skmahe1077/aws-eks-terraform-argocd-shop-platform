# Installs Argo CD into the existing EKS cluster via its official Helm
# chart. create_namespace creates the "argocd" namespace for us.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = true

  # Explicit on purpose: keep the Argo CD server internal (ClusterIP).
  # Access it with `kubectl -n argocd port-forward svc/argocd-server 8080:443`
  # - never expose it with a public load balancer in this workshop.
  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }
}

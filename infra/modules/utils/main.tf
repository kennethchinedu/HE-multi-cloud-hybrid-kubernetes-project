// To keep it simple, we will use default helm repos and configurations, in production it is 
// best to customize the helm chart and values

#Istio
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
}
    
#istiod
resource "helm_release" "istiod" {
  name             = "istiod"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "istiod"
  namespace        = "istio-system"
  create_namespace = true


}
resource "helm_release" "istiod_cni" {
  name             = "istio-cni"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "cni"
  namespace        = "istio-system"
  create_namespace = true


}

#istio gateway
resource "helm_release" "istio_gateway" {
  name       = "istio-ingressgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = "istio-system"
  create_namespace = true

}

# Kyverno policy engine
resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  namespace        = "kyverno"
  create_namespace = true
  version          = "3.3.4"

  atomic  = true
  timeout = 600
}


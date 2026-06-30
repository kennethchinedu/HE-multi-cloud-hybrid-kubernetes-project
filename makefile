.PHONY: help bootstrap-cluster install-helm install-argocd install-kyverno \
        install-chaos-mesh install-policy-reporter install-platform \
        setup-policies deploy-application deploy-gitops-platform deploy-vault deploy-all

# Default target — print usage
help:
	@echo ""
	@echo "Usage: make <target>"
	@echo ""   
	@echo "Cluster Bootstrap"
	@echo "  bootstrap-cluster          Start VMs and initialise the control plane"
	@echo ""
	@echo "Platform Installation"
	@echo "  install-helm               Install Helm (Linux/snap)"
	@echo "  install-argocd             Install ArgoCD via Helm"
	@echo "  install-argocd-rollout     Install ArgoCD Rollouts via cli"
	@echo "  install-kyverno            Install Kyverno via Helm"
	@echo "  install-chaos-mesh         Install Chaos Mesh via Helm"
	@echo "  install-policy-reporter    Install Policy Reporter via Helm"
	@echo "  install-platform           Install all platform tools in order"
	@echo ""
	@echo "Policies"
	@echo "  setup-policies             Apply all Kyverno policies to the cluster"
	@echo ""
	@echo "Application"
	@echo "  deploy-application         Apply ArgoCD project and application for boutique"
	@echo "  deploy-gitops-platform     Apply ArgoCD project and application for Kyverno"
	@echo "  deploy-vault               Apply ArgoCD project and application for Vault"
	@echo "  deploy-all                 Deploy all ArgoCD apps"
	@echo ""

# This commans bootstraps local kubernates clusters locally, using vagrants as a virtual machine

bootstrap-cluster:
	cd bootstrap && vagrant up && \
	vagrant ssh sre-control-plane -- "sudo bash /vagrant/bootstrap_control_local.sh 192.168.56.10 192.168.0.0/16"

# After bootstrap-cluster, get the join command from the control plane output,
# then run:
#   make join-worker TOKEN=<token> HASH=sha256:<hash>
join-worker:
	@if [ -z "$(TOKEN)" ] || [ -z "$(HASH)" ]; then \
		echo "ERROR: TOKEN and HASH are required."; \
		echo "Usage: make join-worker TOKEN=xmo2e8.pzq792fmgz8z09xr HASH=sha256:34039642febbab4642243585e28544fb62e32c5142ef3415ef3517b330e9fd1e"; \
		exit 1; \
	fi
	cd bootstrap && \
	vagrant ssh sre-worker-1 -- "sudo bash /vagrant/bootstrap_worker_local.sh 192.168.56.10 $(TOKEN) $(HASH)" && \
	vagrant ssh sre-worker-2 -- "sudo bash /vagrant/bootstrap_worker_local.sh 192.168.56.10 $(TOKEN) $(HASH)"




# Platform Installation ( SHOULD ONLY RUN ON YOUR ADMIN CLUSTER, basically the cluster that monitors/manages others)
# Remember switching to the right cluster context  before running the below makefile commands
install-helm:
	sudo snap install helm --classic

install-argocd:
	cd platform/argocd && \
	helm dependency update && \
	helm upgrade --install argocd . \
		--namespace argocd \
		--create-namespace \
		--values values.yaml
	#To get your initial argocd password uncomment and run the command below
	#kubectl get secret argocd-initial-admin-secret \
  		#-n argocd \
  		#-o jsonpath="{.data.password}" | base64 -d


setup-monitoring:
	cd platform/observability && \
	helm repo add grafana https://grafana.github.io/helm-charts && \
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && \
	helm repo update && \
	kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - && \
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
		--namespace monitoring \
		--create-namespace 

install-policy-reporter:
	helm repo add policy-reporter https://kyverno.github.io/policy-reporter || true && \
	helm repo update && \
	helm upgrade --install policy-reporter policy-reporter/policy-reporter \
		--namespace policy-reporter \
		--create-namespace \
		--set kyvernoPlugin.enabled=true \
		--set ui.enabled=true \
		--set service.type=NodePort \
		--set service.nodePort=32000

install-platform: install-argocd set-up-monitoring install-policy-reporter 
	@echo "All platform tools installed."

# Policies for k8s

setup-policies:
	kubectl apply -f policies/security/ -f policies/cost/ -f policies/mutations/

#  Application Deployment 
deploy-application:
	kubectl apply -f gitops/project/boutique-project.yaml && \
	kubectl apply -f gitops/apps/applications/boutique-app.yaml

# deploy-gitops-platform:
# 	kubectl apply -f gitops/project/kyverno-project.yaml && \
# 	kubectl apply -f gitops/apps/platform/kyverno-app.yaml

# deploy-vault:az 
# 	kubectl apply -f gitops/project/vault-project.yaml && \
	kubectl apply -f gitops/apps/platform/vault-app.yaml

# deploy-all: deploy-gitops-platform deploy-vault deploy-application
# 	@echo "All ArgoCD apps deployed."
 


 
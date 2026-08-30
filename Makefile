.PHONY: up infra-up kagent-up down break ui jaeger logs verify credentials

up:
	@echo "=== Provisioning infrastructure and kagent ==="
	@scripts/setup.sh

infra-up:
	@echo "=== Provisioning LKE cluster and Keycloak ==="
	@scripts/infra-up.sh

kagent-up:
	@echo "=== Configuring Keycloak and installing kagent ==="
	@scripts/kagent-up.sh

break:
	@scripts/break-app.sh

credentials:
	@if [ -f .demo-users ]; then cat .demo-users; else echo "No .demo-users yet. Run: make kagent-up"; fi

KUBECONFIG ?= $(HOME)/.kube/kagent-identity-config
export KUBECONFIG

ui:
	@echo "Open http://localhost:8080 (Keycloak login via oauth2-proxy)"
	kubectl port-forward svc/kagent-oauth2-proxy 8080:4180 -n kagent

jaeger:
	kubectl port-forward svc/jaeger-ui 16686:16686 -n monitoring

logs:
	kubectl logs -n kagent deployment/kagent-controller -f | grep -E "identity|RBAC|deny|allow|403|Forbidden"

verify:
	@echo "=== Checking endpoints ==="
	kubectl get endpoints frontend-svc -n demo
	@echo "=== Checking demo agents ==="
	kubectl get agents -n kagent observer-agent remediator-agent remediator-agent-intern
	@echo "=== Checking Service selector ==="
	kubectl get svc frontend-svc -n demo -o jsonpath='{.spec.selector}' ; echo

down:
	@echo "=== Destroying infrastructure ==="
	@scripts/cleanup.sh

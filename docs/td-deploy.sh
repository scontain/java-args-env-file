#!/usr/bin/env bash
set -Eeuo pipefail

# -------- Cleanup from previous runs --------

kubectl delete -f generated/configmap.yaml -f generated/deployment.yaml -f generated/secret.yaml >/dev/null 2>/dev/null || true
kubectl delete generated/manifest.sanitized.yaml 2>/dev/null || true

source ./docs/pe.sh

# -------- Scripted demo --------


pe '# Deploying the confidential container app using the generated manifests.'
pe '# - the manifests were generated with scripts/td-build.sh'
pe '# - and stored in generated/manifests.sanitized.yaml'
pe 'cat generated/manifest.sanitized.yaml'
sleep 10
pe '# As you can see, the do not contain any secrets nor configMaps'
pe '# We can now deploy the application using kubectl:'
pe 'kubectl apply -f generated/manifest.sanitized.yaml'
pe '# Wait for the application to be ready:'
pe 'kubectl wait pod -l app=java-cli-env-reader --for=condition=Ready --timeout=300s'
sleep 10
pe "# let's look at the output of the confidential application:"
pe "# - to show that it works as expected, the application prints the env vars "
pe "#   and the content of the injected file"
pe "# - note that a confidential application would normally not print this info!"
pe 'timeout 2m kubectl logs -l app=java-cli-env-reader --follow || true'
pe '# DONE'

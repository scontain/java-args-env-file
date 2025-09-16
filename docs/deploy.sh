#!/usr/bin/env bash
set -Eeuo pipefail

source ./docs/pe.sh

# -------- Scripted demo --------

pe '# Deploying the native container image and the manifests.'
pe '# - using scripts/deploy.sh'
pe './scripts/deploy.sh --help'
pe '# Deploying the application:'
pe './scripts/deploy.sh'
pe 'kubectl wait pod -l app=java-cli-env-reader --for=condition=Ready --timeout=300s'
pe "# let's look at the output of the application:"
pe 'kubectl logs -l app=java-cli-env-reader'
sleep 30
pe '# DONE'

#!/usr/bin/env bash
set -Eeuo pipefail

source ./docs/pe.sh

# -------- Scripted demo --------

pe '# Building the native container image and the manifests.'
pe '# - we use scripts/build.sh'
pe '# - it takes the following arguments:'
pe './scripts/build.sh --help'
sleep 5 
pe '# We use repo registry.scontain.com/workshop/java-cli-env-reader'
pe '# - you should replace it with your own registry/repo'
pe './scripts/build.sh --repo registry.scontain.com/workshop/java-cli-env-reader'
sleep 2
pe "# Let's look at the generated files:"
pe '#  - first the generated native configmap:'
pe 'cat generated/configmap.yaml'
sleep 10
pe '#  - second, the generated native deployment:' 
pe 'cat generated/deployment.yaml'
sleep 10
pe '#  - third, the generated native secrets:' 
pe 'cat generated/secret.yaml'
sleep 10
pe '# DONE'

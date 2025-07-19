# Java Tutorial

This is a simple tutorial on how to convert a very basic cloud-native application into a confidential cloud-native application.
We use a simple Java program to demonstrate the steps.

## Java Application

The Java program:

- Prints CLI arguments.
- Prints environment variables.
- Prints the content of /config/configs.yaml and /config/secrets.

## Kubernetes Manifests

- Deploy the Java application.
- Mount a ConfigMap to /config/configs.yaml.
- Mount a Secret to /config/secrets.

## Prerequisites

Make sure you have installed all necessary software on your development machine and your Kubernetes cluster by clonging repository <https://github.com/scontain/scone.git> and following the `README.md`. Basically, execute in repo `scone`

- `./scripts/prerequisite_check.sh` to install all necessary commands,
- `./scripts/reconcile_scone_operator.sh` check that your Kubernetes cluster is properly configured, and
- `./scripts/install_cas.sh` to ensure that CAS instance `cas` exists in Kubernetes namespace `default`.

## Running the tutorial

The following scrips that are found in the `scripts` directory:

- `build.sh`: build the container image and the manifests. Run `build.sh --help` to learn how to customize this build step. 
- `deploy.sh`: deploys the manifests in the default namespace.
- `show_logs.sh`: show the log of the pod
- `cleanup.sh`:  removes all resources


### Run `build.sh`

Run the following script to build the container image and generate the Kubernetes manifests:

```sh
# example: registry.scontain.com/workshop/java-cli-env-reader
./scripts/build.sh --repo your-registry-url/your-namespace/java-cli-env-reader
```

> **Note:** Tag is added using `--tag <tag>`

You can customize the build process by using command-line options. To see all available options:

```sh
./scripts/build.sh --help
```

### Run `td-build.sh`

Confidentialize previously built Docker image and generated Kubernetes manifests:

```sh
# Use --help to explore additional options and usage details
./scripts/td-build.sh --cas-addr cas.scone-system --split
```

> **Note:** Before running this script, make sure your `kubeconfig` is configured to point to the target SGX-enabled Kubernetes cluster. Also, make sure to set the `--cluster-addr` according to your environment, using the correct `name.namespace` format that matches your CAS deployment.

### Run `deploy.sh`

Apply the generated encrypted policies:

```sh
kubectl apply -f generated/manifest.sanitized.enc.yaml
```

Then deploy the workload using:

```sh
kubectl apply -f generated/manifest.sanitized.yaml 
```

> **Note:** If your container images are stored in a private registry, you must create a Kubernetes secret to allow image pulling:

```sh
# Replace <REGISTRY>, <USER> and <TOKEN> with your actual registry credentials
kubectl create secret docker-registry sconeapps \
    --docker-server=<REGISTRY> \
    --docker-username=<USER> \
    --docker-password=<TOKEN>
```

### See application logs

Streams logs from the pod created by the Kubernetes Job: java-cli-env-reader.

```sh
./scripts/show-logs.sh
```

> **Note:** If you have used the `--namespace` flag at `build.sh`, use same namespace here.

### Cleanup

Delete all Kubernetes resources created from generated manifests and the local files:

```sh
# Use --help to explore additional options and usage details
./scripts/cleanup.sh
```

## Showing the secrets

We can decode the Kubernetes secret with the help of script `decode_secret.sh`.

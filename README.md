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

## Running the tutorial

Make sure you have the following installed and accessible:

- [docker](https://docs.docker.com/engine/install/ubuntu/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [rust](https://www.rust-lang.org/tools/install)
- sed
- [yq](https://github.com/mikefarah/yq)
- Access to an SGX-enabled Kubernetes cluster with SCONE operator and CAS installed
- Access to a container registry with permissions to push generated images
- Access to Scontain container registry with permissions to pull base sconified images
- Access to the following repositories
  - [k8s-scone](https://github.com/scontain/k8s-scone)
  - [lib-sconify](https://github.com/scontain/lib-sconify)

Once access is granted, authenticate with the required registries (`docker login`) and assure you have set up GitHub SSH access or authenticated via HTTPS with a personal access token if needed.

### install `k8s-scone`

Clone the repository:

```sh
git clone https://github.com/scontain/k8s-scone.git
```

or

```sh
git clone git@github.com:scontain/k8s-scone.git
```

Then navigate into the project directory and run the installer:

```sh
cd k8s-scone
./install.sh
```

Check if the binary is successfuly installed:

```sh
k8s-scone --help
```

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

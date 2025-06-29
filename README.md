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

- `build.sh`: build the container image and the manifests. Run `build.sh --help` to learn how to customize this build step. 
- `delpoy.sh`: deploys the manifests in the default namespace.
- 

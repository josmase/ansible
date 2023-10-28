Kubernetes setup using kustomize to deploy all services following a base and environment structure. Where each environemnt will works as an overlay.
There is however a special case which is `cert-manager`, it doesn't really work if it isn't in the `cert-manager` namespace. It also requires `apiTokenSecretRef` to be in the sanme `cert-manager` namespace. Which is why the Cloudflare api token is defined in the `cert-manager` base.

## Usage

Setup cert-manager using `kubectl apply -k environments/common --server-side` after you have copied the `bases/*/secret-*.yaml` files to the `environments/common` folder. The server-side flag is required as the action-runner-controller CRDs are too big to be applied client side.

Once cert-manager is up and running the staging environemnt can be created using `kubectl apply -k environments/staging`. You can then run the following to verify that cert-manager is working and that the certificates are being generated.
1. Verify certificate challenges: `kubectl get challenges -n staging -o wide`
2. Verify certificates: `kubectl get certificates -n staging -o wide`

## Sanity check

A good sanity check to verify that the patching is working as expected is to run the below commands and then run a diff on them.

`kubectl kustomize environments/staging > output-staging.yaml`

`kubectl kustomize environments/prod > output-prod.yaml`

### Traefik

Below are some notes of how to install traefik to the cluster and some issues and solutions for them.

### Installation

Traefik has not yet been moved to a yaml defined installation. So until that is done it will be installed using helm. The install script can be found [here](../services/traefik/install.sh)

#### IngressRoutes patching

I have not found a nice way of patching ingress routes. As they seem to be matching on the `match` key, which is exactly the one that most often is changed. The solution is to simply copy the service definition of the ingress route. 




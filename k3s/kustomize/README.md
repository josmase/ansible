Kubernetes setup using kustomize to deploy all services following a base and environment structure. Where each environemnt will works as an overlay.
There is however a special case which is `cert-manager`, it doesn't really work if it isn't in the `cert-manager` namespace. It also requires `apiTokenSecretRef` to be in the sanme `cert-manager` namespace. Which is why the Cloudflare api token is defined in the `cert-manager` base.

## Usage
Setup cert-manager using `kubectl apply -k environments/common --server-side` after you have copied the `bases/*/secret-*.yaml` files to the `environments/common` folder. The server-side flag is required as the action-runner-controller CRDs are huge.

Once cert-manager is up and running the staging environemnt can be created using `kubectl apply -k environments/staging`. You can then run the following to verify that cert-manager is working and that the certificates are being generated.
1. Verify certificate challenges: `kubectl get challenges -n staging -o wide`
2. Verify certificates: `kubectl get certificates -n staging -o wide`


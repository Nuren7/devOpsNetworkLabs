# Secure Docker Microservice Lab

A small two-service demo of a private Docker network, Docker service-name DNS, and an HTTPS reverse proxy. Nginx is the only service published on the host; the FastAPI backend is reachable only from the Docker network.

## Architecture

```text
Browser
  | HTTP :80 (redirects to HTTPS) / HTTPS :443
  v
Nginx (TLS termination)
  | http://backend-api:8000 (private Docker bridge)
  v
FastAPI backend
```

Compose creates `internal_net` with the example CIDR `172.28.0.0/16`. Nginx resolves `backend-api` using Docker's embedded DNS server. The backend has no host port mapping.

## Requirements

- Docker Engine with the Compose plugin, or Docker Desktop
- OpenSSL
- Bash to run the helper scripts (Linux/macOS, WSL, or Git Bash on Windows)

Make sure ports 80 and 443 are available on the host before starting the stack.

## Run locally

From the project directory:

1. Generate a local self-signed certificate:

   ```sh
   bash scripts/generate-cert.sh
   ```

   The private key and certificate are written to `nginx/certs/` and are excluded from Git.

2. Optionally add `127.0.0.1 myapp.local` to your hosts file:
   - Linux/macOS: `/etc/hosts`
   - Windows: `C:\Windows\System32\drivers\etc\hosts` (edit as Administrator)

   Alternatively, test without changing the hosts file using curl's `--resolve` option below.

3. Build and start the services:

   ```sh
   docker compose up --build -d
   docker compose ps
   ```

4. Open `https://myapp.local/` or test from a terminal:

   ```sh
   curl -k --resolve myapp.local:443:127.0.0.1 https://myapp.local/
   curl -k --resolve myapp.local:443:127.0.0.1 https://myapp.local/health
   ```

   `-k` is needed because the development certificate is self-signed. HTTP on port 80 redirects to HTTPS. The certificate is for local testing only; use a trusted certificate for a public deployment.

To stop the services, run `docker compose down`.

> If Docker reports that `172.28.0.0/16` overlaps with another network, choose an unused private CIDR in `docker-compose.yml`.

## Kubernetes Deployment (Local Cluster)

The Kubernetes manifests provide a separate local deployment path; the existing Compose setup and SSH deployment helper remain unchanged. The backend runs with two replicas behind a private `ClusterIP` service. Nginx terminates TLS and is exposed by a `NodePort` service.

```text
Browser / curl
     | HTTPS :30443 (NodePort) or kubectl port-forward
     v
Nginx Deployment (2 replicas; TLS Secret + ConfigMap)
     | HTTP :8000 (ClusterIP DNS: backend-api)
     v
FastAPI Deployment (2 replicas)
     ^ Ingress allowed only from pods labeled app.kubernetes.io/name=nginx
     | NetworkPolicy
```

| Concept | Docker Compose | Kubernetes |
| --- | --- | --- |
| Private backend access | `internal_net`; only Nginx and the backend join it | `backend-api` is a `ClusterIP`; a `NetworkPolicy` restricts backend ingress to Nginx pods |
| Service discovery | Docker embedded DNS resolves `backend-api` | Cluster DNS resolves `backend-api` to its `ClusterIP` |
| Configuration and TLS | Read-only bind mounts from `nginx/` | Nginx `ConfigMap` and namespace-scoped TLS `Secret` (`myapp-tls`) |
| Process hardening | Non-root backend, read-only filesystems, dropped capabilities | Restricted namespace, non-root containers, read-only filesystems, dropped capabilities, and `RuntimeDefault` seccomp |
| Health and capacity | Docker health checks | Kubernetes probes, resource requests/limits, and two backend replicas |
| External access | Host ports 80/443 on Nginx | Nginx `NodePort` on 30080/30443; backend has no external port |

### Start a local cluster

Requirements: Docker, `kubectl`, Bash, and a local Kubernetes cluster. The helper script supports **kind**, **Minikube**, and **Docker Desktop Kubernetes**. Network policies are enforced by the cluster's CNI plugin; for a policy test, use a policy-capable CNI (for example, start Minikube with `minikube start --cni=calico`). The default kindnet CNI does not enforce `NetworkPolicy`.

1. Start or select a local cluster, then confirm the active context:

   ```sh
   kubectl config current-context
   ```

   Minikube example:

   ```sh
   minikube start --cni=calico
   ```

2. From the project root, run the setup script:

   ```sh
   bash scripts/k8s-setup.sh
   ```

   It generates the self-signed certificate if either certificate file is absent, creates or updates the `myapp-tls` Secret, builds `devops-lab-backend:local` and `devops-lab-nginx:local`, loads the images into kind or Minikube when selected, applies `k8s/`, and waits for both Deployments. Docker Desktop Kubernetes uses the local Docker image store. For manual image loading, use `kind load docker-image devops-lab-backend:local devops-lab-nginx:local` or run `minikube image load devops-lab-backend:local` and `minikube image load devops-lab-nginx:local` before applying the manifests.

3. Check that the pods and services are ready:

   ```sh
   kubectl get pods,services,networkpolicies -n devops-lab
   ```

4. Test HTTPS. Port-forwarding works across local cluster providers; in another terminal run:

   ```sh
   kubectl port-forward -n devops-lab service/nginx 8443:443
   ```

   Then request the backend through Nginx:

   ```sh
   curl -k --resolve myapp.local:8443:127.0.0.1 https://myapp.local:8443/
   curl -k --resolve myapp.local:8443:127.0.0.1 https://myapp.local:8443/health
   ```

   The local certificate is self-signed, so `-k` is needed. With Minikube, you can also use its node IP and the HTTPS NodePort:

   ```sh
   curl -k --resolve myapp.local:30443:"$(minikube ip)" https://myapp.local:30443/health
   ```

   HTTP on NodePort 30080 redirects to HTTPS NodePort 30443:

   ```sh
   curl -I --resolve myapp.local:30080:"$(minikube ip)" http://myapp.local:30080/
   ```

5. Verify the policy allows Nginx but blocks an unrelated pod. The first command should return the health response:

   ```sh
   kubectl exec -n devops-lab deployment/nginx -- wget -qO- http://backend-api:8000/health
   ```

   The following command is expected to **fail or time out** when the CNI enforces the policy. A successful response means the policy is not being enforced:

   ```sh
   kubectl run network-policy-test -n devops-lab --rm -i --restart=Never \
     --image=devops-lab-backend:local --image-pull-policy=IfNotPresent \
     -- python -c "import urllib.request; urllib.request.urlopen('http://backend-api:8000/health', timeout=3)"
   ```

6. Remove the Kubernetes resources when finished:

   ```sh
   kubectl delete namespace devops-lab
   ```

   This removes the Deployments, Services, NetworkPolicy, ConfigMap, and TLS Secret. It does not affect the Docker Compose stack or local images.

## What this demonstrates

- **Private IP and subnet:** Compose defines an isolated bridge network with an explicit CIDR.
- **DNS:** Nginx proxies to `backend-api` by service name, not a container IP. Docker DNS is re-resolved periodically.
- **HTTP, HTTPS, and TCP:** Nginx listens on TCP ports 80 and 443, redirects HTTP to HTTPS, and terminates TLS before proxying HTTP internally.
- **Least privilege:** Only Nginx publishes host ports. Both containers drop unnecessary Linux capabilities; the app runs as a non-root user.
- **Health checks:** Nginx waits for the API health check before starting.

## SSH deployment helper (optional)

The helper deploys an already checked-out project on a Linux host by running `docker compose up -d --build` over SSH. It does not copy files or create keys; update the remote checkout first and generate the TLS certificate on that host.

1. Create an ED25519 key if you do not already have one:

   ```sh
   ssh-keygen -t ed25519 -C "devops-network-lab"
   ```

2. Install the public key on the server (for example, with `ssh-copy-id user@your-linux-host`) and verify the host fingerprint. Keep the private key local; never commit or upload it.
3. Make sure the project and generated certificate exist in the remote project directory. Install Docker Engine and the Compose plugin on the host.
4. Run the helper from Bash:

   ```sh
   DEPLOY_HOST=user@your-linux-host \
   DEPLOY_PATH=/opt/devops-network-lab \
   SSH_KEY_PATH="$HOME/.ssh/id_ed25519" \
   bash scripts/deploy.sh
   ```

   The script uses batch mode and strict host-key checking, so the server must already be in your SSH `known_hosts` file.

For a public Linux host, configure its firewall separately to allow only the required web ports (80/443) and SSH from trusted addresses. Do not expose the backend port.

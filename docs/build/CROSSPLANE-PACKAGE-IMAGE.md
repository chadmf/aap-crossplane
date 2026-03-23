# Crossplane package image vs controller image

If Crossplane reports **"package.yaml not found in package"** for your provider image, the image you pushed is the **controller (runtime) image**, but Crossplane expects a **package image** (xpkg).

## What's the difference?

| Image | Contents | Used by |
|-------|----------|--------|
| **Controller image** | Provider binary, Terraform, provider plugins (what [build-provider-image-podman.sh](../../build/build-provider-image-podman.sh) builds) | Crossplane runs this as the provider Deployment. |
| **Package image** (xpkg) | `package.yaml` (or `crossplane.yaml`) metadata and a reference to the controller image | Crossplane pulls this first to know *what* to install and *which* controller image to run. |

`Provider.spec.package` must point at the **package image**, not the controller image. The package image tells Crossplane which controller image to deploy.

## Fix: build and push the package image

Use two tags so the controller and package images can both live in the same Quay repo (e.g. `quay.io/myorg/aap-crossplane`; replace `myorg` with your Quay org or username).

Use a specific tag (e.g. `v0.1.0`) for the controller so the package image can reference it.

### 1. Build and push the controller image (you may have done this already)

Follow **[BUILD-PROVIDER-IMAGE.md](BUILD-PROVIDER-IMAGE.md)** from the **aap-crossplane** repo root: build with Podman (use **`GOARCH=amd64`** on Apple Silicon if the cluster is amd64), then tag and push to your registry (e.g. `quay.io/myorg/aap-crossplane:v0.1.0`). That pushed URL is what you pass to **`--embed-runtime-image=`** in step 3.

### 2. Install Crossplane CLI (if needed)

Install the [Crossplane CLI](https://docs.crossplane.io/latest/cli/install/) so you can run `crossplane xpkg build` and `crossplane xpkg push`. For example:

```bash
curl -sL https://raw.githubusercontent.com/crossplane/crossplane/master/install.sh | sh
# Or on macOS: brew install crossplane
```

### 3. Build the package (xpkg) from provider-aap

From the **provider-aap** repo root (with `package/crossplane.yaml` and `package/crds/` present):

```bash
cd /path/to/provider-aap

# Build the xpkg; --embed-runtime-image is the controller image you pushed in step 1
crossplane xpkg build -f package --embed-runtime-image=quay.io/myorg/aap-crossplane:latest -o aap-crossplane.xpkg
```

This produces `aap-crossplane.xpkg`, which contains the package metadata and the controller image reference.

**Apple Silicon (M1/M2):** If you build and push the xpkg on an arm64 Mac, the **package image** you push will be **arm64**. An amd64 cluster will then fail with "Exec format error". Build the xpkg from an **amd64** environment. Example using Docker (controller image `v0.1.0` must already be pushed as amd64 from step 1):

```bash
# From host: ensure docker login quay.io so the container can push
docker run --rm --platform linux/amd64 \
  -v /path/to/provider-aap:/work -w /work \
  -v ~/.docker:/root/.docker:ro \
  crossplane/crossplane:latest \
  sh -c 'crossplane xpkg build -f package --embed-runtime-image=quay.io/myorg/aap-crossplane:v0.1.0 -o aap-crossplane.xpkg && crossplane xpkg push -f aap-crossplane.xpkg quay.io/myorg/aap-crossplane:latest'
```

Replace `/path/to/provider-aap` with the real path. Then delete the provider deployment so the new image is pulled:  
`kubectl delete deployment -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider`

### 4. Push the package image to Quay

The Crossplane CLI uses **Docker's config** (`~/.docker/config.json`) for push, not Podman's auth file. If you only use Podman, do one of the following so `crossplane xpkg push` can authenticate to Quay:

**Option A – Docker config (recommended)**  
Log in with Docker so credentials are in `~/.docker/config.json`:

```bash
docker login quay.io -u myorg
or
podman ogin quay.io -u myorg
```

Then push the xpkg:

```bash
crossplane xpkg push -f aap-crossplane.xpkg quay.io/myorg/aap-crossplane:latest
```

**Option B – Podman only**  
Create Docker-format config so the Crossplane CLI can see your Quay credentials. After `podman login quay.io`, create `~/.docker/config.json` (or merge into it) with your Quay username and token:

```bash
# One-time: create ~/.docker/config.json with Quay auth (use a robot token or password)
mkdir -p ~/.docker
echo '{"auths":{"quay.io":{"auth":"'$(echo -n 'myorg:YOUR_QUAY_TOKEN_OR_PASSWORD' | base64)'"}}}' > ~/.docker/config.json
```

Replace `YOUR_QUAY_TOKEN_OR_PASSWORD` with your Quay password or a robot account token, then run:

```bash
crossplane xpkg push -f aap-crossplane.xpkg quay.io/myorg/aap-crossplane:latest
```

### 5. Point the Provider at the package image

[deploy/provider.yaml](../../deploy/provider.yaml) should have `spec.package` set to your **package** image (e.g. `quay.io/myorg/aap-crossplane:latest`). Re-apply if you changed it:

```bash
kubectl apply -f deploy/provider.yaml
```

After a short time, the provider should report **INSTALLED=True** and **HEALTHY=True**; Crossplane will pull the controller image from the reference inside the package.

## Summary

- **Controller image** (e.g. `quay.io/myorg/aap-crossplane:v0.1.0`): build and push per [BUILD-PROVIDER-IMAGE.md](BUILD-PROVIDER-IMAGE.md) (uses [build-provider-image-podman.sh](../../build/build-provider-image-podman.sh)). Do **not** set `spec.package` to this.
- **Package image** (e.g. `quay.io/myorg/aap-crossplane:latest`): built with `crossplane xpkg build -f package --embed-runtime-image=...`, pushed with `crossplane xpkg push`. Set `spec.package` to this so Crossplane finds `package.yaml` and then deploys the controller image referenced inside it.

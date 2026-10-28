# Runbook: from zero to a running store

Everything below runs on your own PC. Total time: about 20 to 30 minutes (most of it image downloads).

## 0. Prerequisites

| Tool | Notes |
|---|---|
| Docker (Desktop or Engine) | Allocate **4 CPUs and 8 GB RAM** (Docker Desktop: Settings > Resources) |
| kind v0.33.0 | https://kind.sigs.k8s.io |
| kubectl | any recent version |
| helm 3 | only needed for monitoring |
| git, make | on Windows use WSL2 (Ubuntu) and run everything inside it |

```bash
make prereqs
```
Expected: `ok` for every tool, `ok docker daemon running`.

## 1. Create the GitHub repository and run the pipeline once

1. Create an empty public repo named `online-boutique-gitops` on GitHub.
2. Allow the pipeline to push: repo **Settings > Actions > General > Workflow permissions > Read and write permissions > Save**.
3. Set your username (this is the only placeholder in the project) and push:

```bash
make configure GH_USER=<your-github-username>
git init -b main
git add -A && git commit -m "initial commit"
git remote add origin https://github.com/<your-github-username>/online-boutique-gitops.git
git push -u origin main
```

4. Open the **Actions** tab and wait for `ci` to turn green (first run about 5 to 8 minutes).
5. Make the image public so the cluster can pull it: GitHub profile > **Packages** > `online-boutique-frontend` > **Package settings** > **Change visibility** > Public.
6. Get the bot's commit: `git pull`. Check `k8s/overlays/dev/kustomization.yaml`; `newName` and `newTag` now point at `ghcr.io/<you>/online-boutique-frontend:<12-char-sha>`.

## 2. Create the cluster

```bash
make cluster
```
Expected: `kubectl get nodes` lists 3 nodes (1 control-plane, 2 workers), all `Ready`.

## 3. Install ingress-nginx and ArgoCD

```bash
make ingress
make argocd
```
Expected: the ingress controller pod is `Running`; `argocd-server` and `argocd-repo-server` rollouts complete.

## 4. Apply the ArgoCD Application

```bash
make deploy
kubectl -n argocd get applications -w
```
Expected within a few minutes: `boutique-dev   Synced   Healthy`.

## 5. Open the store

```
http://localhost:8080
```
Try the **Dark mode** switch and the **Customize UI** button in the header. `ALIYAN MALIK` is in the bottom-right corner.

## 6. Open the ArgoCD UI

```bash
make argocd-password     # copy the password
make argocd-ui           # leave running, then open https://localhost:8081
```
Log in as `admin`, click the `boutique-dev` tile.

## 7. Install monitoring (optional, adds about 1.5 GB RAM)

```bash
make monitor
make grafana-password
make grafana-ui          # http://localhost:3000, user: admin
```
Useful built-in dashboards: *Kubernetes / Compute Resources / Namespace (Pods)* with namespace `boutique-dev`, and *Kubernetes / Compute Resources / Node (Pods)*.

---

## Verification checklist

Run these in order. Each line shows the expected result.

| # | Check | Command | Expected |
|---|---|---|---|
| 1 | Nodes ready | `kubectl get nodes` | 3 nodes, `STATUS Ready` |
| 2 | Ingress up | `kubectl -n ingress-nginx get pods` | controller `1/1 Running` |
| 3 | All pods running | `kubectl -n boutique-dev get pods` | 12 pods, all `Running` (`1/1`) |
| 4 | ArgoCD state | `kubectl -n argocd get applications` | `boutique-dev  Synced  Healthy` |
| 5 | Custom image deployed | `kubectl -n boutique-dev get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].image}'` | `ghcr.io/<you>/online-boutique-frontend:<12 chars>` |
| 6 | Store responds | `curl -s -o /dev/null -w "%{http_code}\n" localhost:8080` | `200` |
| 7 | Owner credit in page | `curl -s localhost:8080 \| grep -c "ALIYAN MALIK"` | `1` |
| 8 | Dark toggle present | `curl -s localhost:8080 \| grep -c 'id="ob-dark-toggle"'` | `1` |
| 9 | Theme assets served | `curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/static/js/theme.js` | `200` |
| 10 | Pods are healthy | `kubectl -n boutique-dev get pods \| grep -v Running` | only the header line |

Manual UI checks in the browser:

- **Dark mode:** click the switch; the whole page goes dark and the label shows `ON`. Reload: it stays dark with no white flash. Click again for `OFF`.
- **Dark mode on every page:** check home, a product page, the cart, and the order confirmation (add an item, then Place order with the sample card).
- **Customize UI:** open the panel; switch themes (header and buttons change color), density (spacing shrinks), font size, and grid columns (2/3/4 on the home page). Press **Reset to default**. Press `Esc` to close the panel.
- **Owner credit:** `ALIYAN MALIK` is visible bottom-right on all pages in both light and dark mode.
- **Mobile width:** shrink the window below 768px. The credit gets smaller and does not block buttons (clicks pass through it).

---

## Pipeline test: a change travels from commit to browser

1. Edit `src/frontend/templates/owner.html` and change the text to `ALIYAN MALIK | v2`.
2. Commit and push to `main`:
   ```bash
   git commit -am "ui: mark v2 in owner credit" && git push
   ```
3. Watch **Actions**: tests, build, Trivy scan, push, then the commit `deploy(dev): frontend <sha> [skip ci]`.
4. Watch the rollout:
   ```bash
   git pull
   kubectl -n boutique-dev rollout status deploy/frontend
   ```
   (ArgoCD polls Git about every 3 minutes. To see it immediately, press **Refresh** on the app in the ArgoCD UI.)
5. Hard-refresh `http://localhost:8080`. The bottom-right credit now says `ALIYAN MALIK | v2`.

## Roll back

```bash
git log --oneline | head              # find the bot's "deploy(dev): ..." commit for the bad release
git revert <that-commit-sha> && git push
```
ArgoCD syncs the previous image tag. (Reverting only the bot's commit leaves your source change in place, so fix the source before the next release.)

## Promote to prod (optional)

Run the **promote-to-prod** workflow from the Actions tab, then `git pull`. `make`-free next step: `kubectl apply -f argocd/application-prod.yaml` and press **Sync** in ArgoCD. This needs extra RAM; scale dev down first on a small PC.

## If the PC struggles

In order of savings:

1. Skip `make monitor` (about 1.5 GB).
2. Turn off the load generator: in `k8s/overlays/dev/kustomization.yaml` uncomment `- path: loadgenerator-off.yaml`, commit and push.
3. Give Docker more memory, and close browsers and IDEs.
4. Lower `retention` and the Prometheus limits in `monitoring/values.yaml`.

Do not use `kubectl scale` for this: ArgoCD's `selfHeal` will put the replicas back.

## Screenshots to capture for your portfolio

1. The store home page in light mode, and again in dark mode.
2. The Customize UI panel open (use the Ocean or Forest theme, so it is clearly not the default).
3. `ALIYAN MALIK` in the bottom-right corner (crop to include the page around it).
4. A green GitHub Actions run, expanded to show test, build, Trivy, push and the commit-back steps.
5. ArgoCD application page: **Synced + Healthy** with the resource tree.
6. `kubectl get pods -A` (or `-n boutique-dev`) with everything `Running`.
7. A Grafana dashboard showing pod CPU and memory for `boutique-dev`.
8. The before/after of the pipeline test (the `v2` change in the browser).

## Clean up

```bash
make destroy
```

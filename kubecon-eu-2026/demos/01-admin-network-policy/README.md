# Demo 1: Admin Network Policy (ClusterNetworkPolicy)

## Why standard NetworkPolicies aren't enough

Standard Kubernetes NetworkPolicies work well when each app team manages
their own rules, but they have key limitations:

- They only control traffic within individual namespaces, not cluster-wide
- There is no explicit "deny" rule — only implicit deny via allow rules
- They can't override another namespace's policies
- No rule hierarchy — no way to enforce org-wide security baselines

This makes them unsuitable for platform/security teams that need
centralized control across all workloads.

## What ClusterNetworkPolicy adds

EKS with the Amazon VPC CNI supports two tiers of cluster-wide policy
via a single CRD (`ClusterNetworkPolicy`):

```
┌─────────────────────────────────────────────────────┐
│  1. Admin Tier  (evaluated first, cannot be          │
│     overridden by namespace-level policies)          │
├─────────────────────────────────────────────────────┤
│  2. Standard NetworkPolicies  (namespace-scoped,     │
│     managed by app teams)                            │
├─────────────────────────────────────────────────────┤
│  3. Baseline Tier  (default connectivity rules,      │
│     CAN be overridden by namespace NetworkPolicies)  │
└─────────────────────────────────────────────────────┘
```

## Policies in this demo

Four `ClusterNetworkPolicy` resources are defined in `cluster-network-policies.yaml`:

| Priority | Name                            | Tier     | Subject                          | Effect                                              |
|----------|---------------------------------|----------|----------------------------------|-----------------------------------------------------|
| 30       | deny-internet                   | Baseline    | All namespaces                   | Deny all ingress/egress to/from 0.0.0.0/0           |
| 20       | allow-frontend-internet-egress  | Baseline | Namespaces with `role=frontend`  | Allow HTTPS (TCP 443) egress to internet            |
| 20       | allow-production-ingress        | Admin    | Namespaces with `env=production` | Allow ingress/egress between production namespaces  |
| 10       | cluster-wide-allow-kube-system  | Admin    | All namespaces                   | Allow ingress/egress to/from kube-system + DNS      |

The `deny-internet` policy (Admin tier, priority 20) acts as a hard block for
all internet traffic. The `allow-frontend-internet-egress` policy (Baseline tier,
priority 10) carves out an exception for frontend namespaces — but because it is
Baseline tier, it can be overridden by namespace-level NetworkPolicies if needed.

Because `allow-production-ingress` is Admin tier, app teams cannot write a
namespace-level policy to bypass east-west production traffic rules.

## How the subject field scales

The `subject.namespaces.matchLabels` selector means a single policy automatically
covers every namespace that matches — including ones created in the future.

- Label a namespace `role=frontend` → it immediately gets internet egress
- Label a namespace `env=production` → it immediately joins the production mesh
- No policy changes required

## Requirements

- Kubernetes 1.29 or later
- Amazon VPC CNI v1.21.1+ (standard EKS clusters)
- EKS Auto Mode supports both CNP and ANP

## Steps

```bash
kubectl apply -f ../namespaces.yaml
kubectl apply -f ../workloads.yaml
kubectl apply -f cluster-network-policies.yaml

kubectl get cnp

# Should succeed — frontend namespace (role=frontend)
kubectl exec -n app deploy/app-client -- curl -s -o /dev/null -w "%{http_code}" https://example.com

# Should be blocked — non-frontend namespace without role=frontend label
kubectl exec -n databases deploy/postgres -- curl -s --max-time 5 https://example.com
```

## Key takeaway

To onboard a new namespace under an existing policy, just apply the right label:

```bash
kubectl label namespace <new-ns> role=frontend
# or
kubectl label namespace <new-ns> env=production
```

No policy changes needed. The selector does the work.

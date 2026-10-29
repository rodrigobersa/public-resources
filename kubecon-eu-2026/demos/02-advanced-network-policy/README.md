# Demo 2: Application Network Policy — FQDN-based egress control

## What makes ApplicationNetworkPolicy different

Standard NetworkPolicies operate at OSI layers 3 & 4 — you're limited to
IP blocks and port numbers. `ApplicationNetworkPolicy` also operates at
layer 7, enabling traffic filtering by Fully Qualified Domain Names (FQDNs).

This is ideal for:

- Cloud to On-Premises: use `internal-api.company.com` instead of maintaining
  IP lists that change whenever the load balancer rotates
- SaaS access: providers regularly change IPs — an FQDN rule just works

## Why FQDN allowlisting beats IP blocklisting for crypto mining

Crypto mining pools rotate IP addresses constantly to evade detection.
Maintaining a blocklist of IPs is a losing battle.

With an FQDN allowlist you flip the model:
- Define only the domains your app legitimately needs
- Everything else — including any mining pool domain — is implicitly blocked
- No IP tracking required, ever

## Policy in this demo

One `ApplicationNetworkPolicy` is defined in `app-network-policies.yaml`:

| Name                     | Namespace | Type   | Effect                                              |
|--------------------------|-----------|--------|-----------------------------------------------------|
| allowlist-egress-domains | app       | Egress | Allow TCP 443 only to explicitly listed FQDNs       |

Allowed destinations (TCP 443 only):
- `api.example.com`
- `cdn.amazonlinux.com`
- `s3.us-west-2.amazonaws.com`
- `sts.amazonaws.com`

Blocked by omission (examples):
- `s3.us-east-1.amazonaws.com`
- `hub.miningpoolhub.com`
- `pool.minexmr.com`
- `xmr.pool.minergate.com`
- `pool.supportxmr.com`
- `*.nicehash.com`
- `*.2miners.com`
- `*.f2pool.com`

## How it works

FQDN rules in `ApplicationNetworkPolicy` are ALLOW-only. The pattern is:

```
┌─────────────────────────────────────────────────────────────┐
│  ClusterNetworkPolicy (Baseline tier)                        │
│  → Deny all egress by default                                │
│    (safety net — defined separately)                         │
├─────────────────────────────────────────────────────────────┤
│  ApplicationNetworkPolicy (namespace: app)                   │
│  → Allow egress ONLY to explicitly listed FQDNs on TCP 443  │
├─────────────────────────────────────────────────────────────┤
│  Result: any domain NOT on the list is blocked               │
│  → pool.minexmr.com        ✗                                 │
│  → *.nicehash.com          ✗                                 │
│  → xmr.pool.minergate.com  ✗                                 │
└─────────────────────────────────────────────────────────────┘
```

## Requirements

- EKS Auto Mode (v1.29+) — `ApplicationNetworkPolicy` and DNS-based filtering
  are exclusive to EKS Auto Mode
- `ClusterNetworkPolicy` is available on standard EKS clusters with
  VPC CNI v1.21.1+

## Steps

```bash
kubectl apply -f ../namespaces.yaml
kubectl apply -f ../workloads.yaml
kubectl apply -f app-network-policies.yaml

kubectl get anp -n app

# Allowed — on the FQDN allowlist
kubectl exec -n app deploy/app -- curl -sv --max-time 5 https://api.example.com

# Blocked — crypto mining pool, not on allowlist
kubectl exec -n app deploy/app -- curl -sv --max-time 5 https://pool.minexmr.com

# Blocked — any unlisted domain
kubectl exec -n app deploy/app -- curl -sv --max-time 5 https://notallowed.example.org
```

## Key takeaway

Think of `ApplicationNetworkPolicy` as a "permitted destinations" list.
You define what's allowed — everything else is denied by default, no matter
what IPs those domains resolve to.

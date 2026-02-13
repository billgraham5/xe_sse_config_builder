# IOS-XE Secure Access Config Builder (Web)

A static local web application that generates Cisco IOS-XE configuration templates to build IPsec VPN tunnels to **Cisco Secure Access (SSE)**.

This tool automates the creation of redundant, ECMP-capable IPsec + BGP configurations for Cisco 8000V routers connecting to Network Tunnel Groups (NTGs) in the SSE cloud.

---

## Overview

The Config Builder generates IOS-XE configuration that supports:

- IKEv2 + IPsec (ESP-GCM)
- Redundant primary/secondary SSE data centers
- Multiple tunnels per Cisco SSE data center
- Equal-Cost Multi-Path (ECMP) load sharing
- Optional dual-router redundancy (Active/Active)
- BGP-based dynamic routing

The tool supports deployment with:

- **1 Cisco 8000V router** or
- **2 Cisco 8000V routers** (recommended for high availability)

---

## Prerequisites

Before using this tool:

1. Log in to the **Cisco Secure Access** admin UI.
2. Create one or more **Network Tunnel Groups (NTGs)**.
3. Record the following information:
   - Primary and secondary headend IP addresses
   - Tunnel IDs (contained within the identity that is auto generated)
   - Locally assigned BGP ASN
   - Pre-shared key
   - Region and data center mappings

Note:  orgs created prior to Novemeber 2025 will use a different ASN for the Cisco SSE.

---

## Network Tunnel Group (NTG) Design

Each NTG provisioned in the SSE cloud includes:

- **Primary tunnels** → mapped to one SSE data center (or availability zone)
- **Secondary tunnels** → mapped to a different SSE data center (or availability zone)

For inter-region redundancy, deploy a second NTG in different region.

### Recommended Design for High Availability

- Two Cisco 8000V routers (Active/Active)
- Two NTGs (separate regions)
- Results in at least four tunnels per NTG
- ECMP configuration implemented on each router

This design provides:

- Cisco SSE Intra-region redundancy
- Cisco SSE Inter-region redundancy
- Router-level redundancy
- Tunnel-level failover

---

## ECMP and Throughput Scaling

The tool supports multiple tunnels per primary or secondary SSE data center to enable ECMP load sharing.

### Why ECMP?

ECMP allows:

- Per-flow traffic distribution across multiple IPsec tunnels
- Aggregate throughput scaling
- Fast failover without route reconvergence delays

### Throughput Model

- Each tunnel supports approximately **1 Gbps** of throughput
- Up to **10 tunnels** can be provisioned
- Traffic is load-shared across tunnels using ECMP

To fully leverage ECMP, BGP multipath is enabled in this IOS-XE configuration.

---

## Router Deployment Model

Each Cisco 8000V router:

- Establishes independent IPsec Security Associations (SAs) per tunnel
- Forms separate BGP sessions per tunnel
- Supports ECMP load sharing
- Provides deterministic failover

With two routers deployed:

- Active/Active edge design
- Horizontal throughput scaling
- Maintenance without service interruption
- Improved resiliency against router failure

---

## IKE Identity Requirements (`+tunnelX`)

When multiple tunnels are built to the same SSE headend IP, IOS-XE requires a unique local IKE identity per tunnel.

IOS-XE requires unique identities per tunnel and the Cisco SSE supports adding +tunnelX in the identity.  This tool will automatically implement this configuration scheme.  


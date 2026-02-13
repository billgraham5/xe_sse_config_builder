# IOS-XE Secure Access Config Builder (Web)

Static local web app that reproduces the usable parts of your workbook:
- `IPSEC_BGP_XE_CONFIG` input cells
- `_cfg_parts` generated IOS-XE CLI sections

## Run From Local Disk

1. Open `/Users/jack/Documents/New project/index.html` in Safari/Chrome.
2. Enter values and click **Generate**.
3. Use **Copy** or **Download .txt**.

No install, server, or internet access required.

## Input Mapping Used

- Router 1: `C4, C8, C9-suffix, C12, C13-suffix, C16, C17, C35`
- Router 2: `C5, C20, C21-suffix, C24, C25-suffix, C28, C29, C56`
- Shared: `Org ID (7 digits)`, `C32`, plus custom `ECMP Tunnels (1-10)`
- Additional form-only fields: Cisco DC Name dropdowns for each router primary/secondary tunnel.

Tunnel IDs are composed as:
- `<OrgID>-<9-digit suffix>`
- This preserves generated config behavior while changing form capture.

## Route-Map Behavior

- `TO_SSE_EXPORT` is generated as:
  - `route-map TO_SSE_EXPORT deny 999`
- Permit entries 5/10/15 are not generated.

## ECMP Behavior

- ECMP count is per head-end (primary and secondary).
- If ECMP = `N`, each router gets:
  - `N` primary tunnels (`Tunnel1..TunnelN`)
  - `N` secondary tunnels (`Tunnel11..Tunnel(10+N)`)
  - matching IKEv2 profiles and IPsec profiles for each tunnel
  - matching BGP neighbor/update-source lines and static routes
- Tunnel interface host IP derivation:
  - Primary offsets: base `+0..+(N-1)`
  - Secondary offsets: base `+10..+(9+N)`

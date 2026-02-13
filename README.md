This is a static local web app that generates an IOS-XE configuration to build IPsec VPN tunnels to Cisco Secure Access.

To prepare to use this web app, create one or more Network Tunnel Groups (NTGs) in the Cisco Secure Access admin UI. This tool supports one or two Cisco 8000V routers, presumably working together to achieve redundancy into the SSE cloud.

Each Network Tunnel Group defined in the SSE cloud will be provisioned with a primary and secondary set of tunnels. The primary tunnels are mapped to a specific Cisco SSE data center (or availability zone), and the secondary tunnels are mapped to a different data center. Inter-region redundancy can be achieved by provisioning a second NTG in a different region, for a total of at least four tunnels into the SSE.

This tool includes support for multiple tunnels to each primary or secondary Cisco SSE data center to achieve ECMP load sharing. Currently, each tunnel supports 1 Gbps of throughput and can be scaled up to 10 tunnels using ECMP.

BGP policy must be carefully planned and implemented to properly leverage the cloud SSE in this configuration scenario. Although not configured by this tool, static routing or outbound/NAT-only configurations are supported by the cloud SSE.

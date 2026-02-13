function value(id) {
  return document.getElementById(id).value.trim();
}

function numberValue(id) {
  return Number(document.getElementById(id).value);
}

function addToIPv4(ip, offset) {
  const parts = ip.split(".").map(Number);
  if (parts.length !== 4 || parts.some((n) => Number.isNaN(n) || n < 0 || n > 255)) {
    throw new Error(`Invalid IP address: ${ip}`);
  }
  const last = parts[3] + offset;
  if (last > 254) {
    throw new Error(`Invalid tunnel base IP ${ip}: +${offset} exceeds .254`);
  }
  parts[3] = last;
  return parts.join(".");
}

function getPrimaryTunnelNumber(index) {
  return index;
}

function getSecondaryTunnelNumber(index) {
  return 10 + index;
}

function getNeighborIP(tunnelNumber) {
  return `169.254.0.${tunnelNumber}`;
}

function ikeProfile(name, remoteIP, localEmail) {
  return [
    `crypto ikev2 profile ${name}`,
    ` match identity remote address ${remoteIP} 255.255.255.255`,
    ` identity local email ${localEmail}`,
    " authentication remote pre-share",
    " authentication local pre-share",
    " keyring local sse-kr",
    " dpd 30 3 periodic",
    "!"
  ];
}

function loopback(num, desc) {
  return [
    `interface Loopback${num}`,
    ` description ${desc}`,
    ` ip address 100.64.255.${num} 255.255.255.255`,
    " ip nat inside",
    "!"
  ];
}

function tunnel(num, address, sourceLoopback, destination, profile) {
  return [
    `interface Tunnel${num}`,
    ` ip address ${address} 255.255.255.255`,
    " ip tcp adjust-mss 1350",
    ` tunnel source Loopback${sourceLoopback}`,
    " tunnel mode ipsec ipv4",
    ` tunnel destination ${destination}`,
    ` tunnel protection ipsec profile ${profile}`,
    "!"
  ];
}

function validateEcmpCount(ecmpCount) {
  if (!Number.isInteger(ecmpCount) || ecmpCount < 1 || ecmpCount > 10) {
    throw new Error("ECMP tunnel count must be an integer between 1 and 10.");
  }
}

function buildRouter(router, psk, ecmpCount) {
  validateEcmpCount(ecmpCount);

  const lines = [
    `! Generated for ${router.name}`,
    "crypto ikev2 proposal sse-proposal",
    " encryption aes-gcm-256",
    " prf sha256",
    " group 20",
    "!",
    "crypto ikev2 policy sse-policy",
    " proposal sse-proposal",
    "!",
    "crypto ikev2 keyring sse-kr",
    " peer sse-secondary",
    `  address ${router.secondaryIP}`,
    `  pre-shared-key local ${psk}`,
    `  pre-shared-key remote ${psk}`,
    " !",
    " peer sse-primary",
    `  address ${router.primaryIP}`,
    `  pre-shared-key local ${psk}`,
    `  pre-shared-key remote ${psk}`,
    " !",
    "!",
    "!"
  ];

  for (let i = 1; i <= ecmpCount; i += 1) {
    lines.push(...ikeProfile(`sse-primary-${i}`, router.primaryIP, `${router.name}+tunnel${i}@${router.primaryId}-sse.cisco.com`));
  }
  for (let i = 1; i <= ecmpCount; i += 1) {
    lines.push(...ikeProfile(`sse-secondary-${i}`, router.secondaryIP, `${router.name}+tunnel${i}@${router.secondaryId}-sse.cisco.com`));
  }

  lines.push(
    "!",
    "crypto ipsec transform-set sse-ts esp-gcm 256",
    " mode tunnel",
    "!"
  );

  for (let i = 1; i <= ecmpCount; i += 1) {
    lines.push(
      `crypto ipsec profile sse-ipsec-primary-${i}`,
      " set transform-set sse-ts",
      ` set ikev2-profile sse-primary-${i}`,
      "!"
    );
  }
  for (let i = 1; i <= ecmpCount; i += 1) {
    lines.push(
      `crypto ipsec profile sse-ipsec-secondary-${i}`,
      " set transform-set sse-ts",
      ` set ikev2-profile sse-secondary-${i}`,
      "!"
    );
  }

  lines.push("!", "!", "!", "!");

  for (let i = 1; i <= ecmpCount; i += 1) {
    lines.push(...loopback(getPrimaryTunnelNumber(i), `source for interface tunnel ${getPrimaryTunnelNumber(i)}`));
  }
  for (let i = 1; i <= ecmpCount; i += 1) {
    lines.push(...loopback(getSecondaryTunnelNumber(i), `source for interface tunnel ${getSecondaryTunnelNumber(i)}`));
  }

  for (let i = 1; i <= ecmpCount; i += 1) {
    const tunnelNumber = getPrimaryTunnelNumber(i);
    const tunnelIP = addToIPv4(router.baseIP, i - 1);
    lines.push(...tunnel(tunnelNumber, tunnelIP, tunnelNumber, router.primaryIP, `sse-ipsec-primary-${i}`));
  }
  for (let i = 1; i <= ecmpCount; i += 1) {
    const tunnelNumber = getSecondaryTunnelNumber(i);
    const tunnelIP = addToIPv4(router.baseIP, 9 + i);
    lines.push(...tunnel(tunnelNumber, tunnelIP, tunnelNumber, router.secondaryIP, `sse-ipsec-secondary-${i}`));
  }

  lines.push(
    "interface GigabitEthernet1",
    " ip nat outside",
    "",
    `router bgp ${router.asn}`,
    ` bgp router-id ${router.rid}`,
    " maximum-paths 10",
    " bgp log-neighbor-changes",
    " neighbor CISCO_SSE peer-group",
    " neighbor CISCO_SSE remote-as 32644"
  );

  for (let i = 1; i <= ecmpCount; i += 1) {
    const tunnelNumber = getPrimaryTunnelNumber(i);
    const neighborIP = getNeighborIP(tunnelNumber);
    lines.push(
      ` neighbor ${neighborIP} peer-group CISCO_SSE`,
      ` neighbor ${neighborIP} ebgp-multihop 255`,
      ` neighbor ${neighborIP} update-source Tunnel${tunnelNumber}`
    );
  }
  for (let i = 1; i <= ecmpCount; i += 1) {
    const tunnelNumber = getSecondaryTunnelNumber(i);
    const neighborIP = getNeighborIP(tunnelNumber);
    lines.push(
      ` neighbor ${neighborIP} peer-group CISCO_SSE`,
      ` neighbor ${neighborIP} ebgp-multihop 255`,
      ` neighbor ${neighborIP} update-source Tunnel${tunnelNumber}`
    );
  }

  lines.push(
    " !",
    " address-family ipv4",
    "  neighbor CISCO_SSE send-community both",
    "  neighbor CISCO_SSE soft-reconfiguration inbound",
    "  neighbor CISCO_SSE route-map FROM_SSE_IMPORT in",
    "  neighbor CISCO_SSE route-map TO_SSE_EXPORT out",
    " exit-address-family",
    "!"
  );

  for (let i = 1; i <= ecmpCount; i += 1) {
    const tunnelNumber = getPrimaryTunnelNumber(i);
    const neighborIP = getNeighborIP(tunnelNumber);
    lines.push(`ip route ${neighborIP} 255.255.255.255 Tunnel${tunnelNumber}`);
  }
  for (let i = 1; i <= ecmpCount; i += 1) {
    const tunnelNumber = getSecondaryTunnelNumber(i);
    const neighborIP = getNeighborIP(tunnelNumber);
    lines.push(`ip route ${neighborIP} 255.255.255.255 Tunnel${tunnelNumber}`);
  }

  lines.push(
    "",
    "ip nat inside source list SSE_IKE_NAT interface GigabitEthernet1 overload",
    "",
    "ip access-list extended SSE_IKE_NAT",
    " 10 permit ip 100.64.255.0 0.0.0.255 any",
    "",
    "route-map FROM_SSE_IMPORT deny 999",
    "ip bgp-community new-format",
    "",
    "route-map TO_SSE_EXPORT deny 999",
    "!"
  );

  lines.push("!", "!", "!", "!");
  return lines.join("\n");
}

function collect() {
  const router1 = {
    name: value("r1Name"),
    primaryIP: value("r1PrimaryIP"),
    primaryId: value("r1PrimaryId"),
    secondaryIP: value("r1SecondaryIP"),
    secondaryId: value("r1SecondaryId"),
    rid: value("r1Rid"),
    asn: value("r1Asn"),
    baseIP: value("r1BaseIP")
  };
  const router2 = {
    name: value("r2Name"),
    primaryIP: value("r2PrimaryIP"),
    primaryId: value("r2PrimaryId"),
    secondaryIP: value("r2SecondaryIP"),
    secondaryId: value("r2SecondaryId"),
    rid: value("r2Rid"),
    asn: value("r2Asn"),
    baseIP: value("r2BaseIP")
  };
  return {
    router1,
    router2,
    psk: value("psk"),
    ecmpCount: numberValue("ecmpCount")
  };
}

function generate() {
  const out = document.getElementById("output");
  const err = document.getElementById("error");
  try {
    const input = collect();
    const config = [
      buildRouter(input.router1, input.psk, input.ecmpCount),
      buildRouter(input.router2, input.psk, input.ecmpCount)
    ].join("\n\n");
    out.value = config;
    err.textContent = "";
  } catch (e) {
    out.value = "";
    err.textContent = e.message || "Failed to generate config.";
  }
}

document.getElementById("generate").addEventListener("click", generate);
document.getElementById("copy").addEventListener("click", async () => {
  const text = document.getElementById("output").value;
  if (!text) return;
  try {
    await navigator.clipboard.writeText(text);
  } catch (_) {
    document.getElementById("output").select();
    document.execCommand("copy");
  }
});

document.getElementById("download").addEventListener("click", () => {
  const text = document.getElementById("output").value;
  if (!text) return;
  const blob = new Blob([text], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "ios-xe-sse-config.txt";
  a.click();
  URL.revokeObjectURL(url);
});

generate();

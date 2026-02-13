import AppKit
import SwiftUI

struct RouterInput {
    var name: String
    var primaryHeadendIP: String
    var primaryTunnelID: String
    var secondaryHeadendIP: String
    var secondaryTunnelID: String
    var bgpRouterID: String
    var localASN: String
    var tunnelBaseIP: String
}

struct ConfigInput {
    var router1: RouterInput
    var router2: RouterInput
    var preSharedKey: String
    var advertiseSDWANPrefixes: Bool
    var advertiseCloudPrefixes: Bool
}

final class BuilderViewModel: ObservableObject {
    @Published var router1Name = "CiscoIOSA-vHub-CentralUS"
    @Published var router1PrimaryHeadendIP = "3.141.141.165"
    @Published var router1PrimaryTunnelID = "8363425-667481483"
    @Published var router1SecondaryHeadendIP = "3.140.13.195"
    @Published var router1SecondaryTunnelID = "8363425-667481484"
    @Published var router1BGPRouterID = "10.255.0.5"
    @Published var router1LocalASN = "65461"
    @Published var router1TunnelBaseIP = "10.7.15.64"

    @Published var router2Name = "CiscoIOSB-EastUS-Region"
    @Published var router2PrimaryHeadendIP = "3.141.141.165"
    @Published var router2PrimaryTunnelID = "8363425-667398686"
    @Published var router2SecondaryHeadendIP = "3.140.13.195"
    @Published var router2SecondaryTunnelID = "8363425-667398687"
    @Published var router2BGPRouterID = "10.53.0.198"
    @Published var router2LocalASN = "64517"
    @Published var router2TunnelBaseIP = "10.7.15.32"

    @Published var preSharedKey = "ll0wN3t3ng123456"
    @Published var advertiseSDWANPrefixes = true
    @Published var advertiseCloudPrefixes = true

    @Published var outputText = ""
    @Published var errorText = ""

    func generate() {
        let input = ConfigInput(
            router1: RouterInput(
                name: router1Name,
                primaryHeadendIP: router1PrimaryHeadendIP,
                primaryTunnelID: router1PrimaryTunnelID,
                secondaryHeadendIP: router1SecondaryHeadendIP,
                secondaryTunnelID: router1SecondaryTunnelID,
                bgpRouterID: router1BGPRouterID,
                localASN: router1LocalASN,
                tunnelBaseIP: router1TunnelBaseIP
            ),
            router2: RouterInput(
                name: router2Name,
                primaryHeadendIP: router2PrimaryHeadendIP,
                primaryTunnelID: router2PrimaryTunnelID,
                secondaryHeadendIP: router2SecondaryHeadendIP,
                secondaryTunnelID: router2SecondaryTunnelID,
                bgpRouterID: router2BGPRouterID,
                localASN: router2LocalASN,
                tunnelBaseIP: router2TunnelBaseIP
            ),
            preSharedKey: preSharedKey,
            advertiseSDWANPrefixes: advertiseSDWANPrefixes,
            advertiseCloudPrefixes: advertiseCloudPrefixes
        )

        do {
            outputText = try ConfigGenerator().generateAll(input: input)
            errorText = ""
        } catch {
            outputText = ""
            errorText = error.localizedDescription
        }
    }

    func copyOutput() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(outputText, forType: .string)
    }

    func exportOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "ios-xe-sse-config.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try outputText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorText = "Failed to save file: \(error.localizedDescription)"
            }
        }
    }
}

struct ConfigGenerator {
    enum BuildError: LocalizedError {
        case invalidIP(String)

        var errorDescription: String? {
            switch self {
            case .invalidIP(let value):
                return "Invalid IP address: \(value). Use dotted decimal (for example 10.7.15.64)."
            }
        }
    }

    func generateAll(input: ConfigInput) throws -> String {
        let r1 = try generateRouterConfig(input.router1, input: input)
        let r2 = try generateRouterConfig(input.router2, input: input)
        return [r1, r2].joined(separator: "\n\n")
    }

    private func generateRouterConfig(_ router: RouterInput, input: ConfigInput) throws -> String {
        let tunnel1IP = try addToIPv4(router.tunnelBaseIP, 0)
        let tunnel2IP = try addToIPv4(router.tunnelBaseIP, 1)
        let tunnel11IP = try addToIPv4(router.tunnelBaseIP, 10)
        let tunnel12IP = try addToIPv4(router.tunnelBaseIP, 11)

        var lines: [String] = []
        func add(_ line: String) { lines.append(line.replacingOccurrences(of: "\u{00a0}", with: " ")) }

        add("! Generated for \(router.name)")
        add("crypto ikev2 proposal sse-proposal")
        add(" encryption aes-gcm-256")
        add(" prf sha256")
        add(" group 20")
        add("!")
        add("crypto ikev2 policy sse-policy")
        add(" proposal sse-proposal")
        add("!")
        add("crypto ikev2 keyring sse-kr")
        add(" peer sse-secondary")
        add("  address \(router.secondaryHeadendIP)")
        add("  pre-shared-key local \(input.preSharedKey)")
        add("  pre-shared-key remote \(input.preSharedKey)")
        add(" !")
        add(" peer sse-primary")
        add("  address \(router.primaryHeadendIP)")
        add("  pre-shared-key local \(input.preSharedKey)")
        add("  pre-shared-key remote \(input.preSharedKey)")
        add(" !")
        add("!")
        add("!")

        addIKEProfileBlock(lines: &lines, name: "sse-primary-1", remoteIP: router.primaryHeadendIP, localEmail: "\(router.name)+tunnel1@\(router.primaryTunnelID)-sse.cisco.com")
        addIKEProfileBlock(lines: &lines, name: "sse-primary-2", remoteIP: router.primaryHeadendIP, localEmail: "\(router.name)+tunnel2@\(router.primaryTunnelID)-sse.cisco.com")
        addIKEProfileBlock(lines: &lines, name: "sse-secondary-1", remoteIP: router.secondaryHeadendIP, localEmail: "\(router.name)+tunnel1@\(router.secondaryTunnelID)-sse.cisco.com")
        addIKEProfileBlock(lines: &lines, name: "sse-secondary-2", remoteIP: router.secondaryHeadendIP, localEmail: "\(router.name)+tunnel2@\(router.secondaryTunnelID)-sse.cisco.com")

        add("!")
        add("crypto ipsec transform-set sse-ts esp-gcm 256")
        add(" mode tunnel")
        add("!")
        add("crypto ipsec profile sse-ipsec-primary-1")
        add(" set transform-set sse-ts")
        add(" set ikev2-profile sse-primary-1")
        add("!")
        add("crypto ipsec profile sse-ipsec-primary-2")
        add(" set transform-set sse-ts")
        add(" set ikev2-profile sse-primary-2")
        add("!")
        add("crypto ipsec profile sse-ipsec-secondary-1")
        add(" set transform-set sse-ts")
        add(" set ikev2-profile sse-secondary-1")
        add("!")
        add("crypto ipsec profile sse-ipsec-secondary-2")
        add(" set transform-set sse-ts")
        add(" set ikev2-profile sse-secondary-2")
        add("!")
        add("!")
        add("!")
        add("!")
        add("!")

        addLoopbackInterface(lines: &lines, number: 1, desc: "source for interface tunnel 1")
        addLoopbackInterface(lines: &lines, number: 2, desc: "source for interface tunnel 2")
        addLoopbackInterface(lines: &lines, number: 11, desc: "source for interface tunnel 11")
        addLoopbackInterface(lines: &lines, number: 12, desc: "source for interface tunnel 12")

        addTunnelInterface(lines: &lines, number: 1, address: tunnel1IP, sourceLoopback: 1, destination: router.primaryHeadendIP, profile: "sse-ipsec-primary-1")
        addTunnelInterface(lines: &lines, number: 2, address: tunnel2IP, sourceLoopback: 2, destination: router.primaryHeadendIP, profile: "sse-ipsec-primary-2")
        addTunnelInterface(lines: &lines, number: 11, address: tunnel11IP, sourceLoopback: 11, destination: router.secondaryHeadendIP, profile: "sse-ipsec-secondary-1")
        addTunnelInterface(lines: &lines, number: 12, address: tunnel12IP, sourceLoopback: 12, destination: router.secondaryHeadendIP, profile: "sse-ipsec-secondary-2")

        add("interface GigabitEthernet1")
        add(" ip nat outside")
        add("")
        add("router bgp \(router.localASN)")
        add(" bgp router-id \(router.bgpRouterID)")
        add(" bgp log-neighbor-changes")
        add(" neighbor CISCO_SSE peer-group")
        add(" neighbor CISCO_SSE remote-as 32644")
        add(" neighbor 169.254.0.1 peer-group CISCO_SSE")
        add(" neighbor 169.254.0.1 ebgp-multihop 255")
        add(" neighbor 169.254.0.1 update-source Tunnel1")
        add(" neighbor 169.254.0.2 peer-group CISCO_SSE")
        add(" neighbor 169.254.0.2 ebgp-multihop 255")
        add(" neighbor 169.254.0.2 update-source Tunnel2")
        add(" neighbor 169.254.0.11 peer-group CISCO_SSE")
        add(" neighbor 169.254.0.11 ebgp-multihop 255")
        add(" neighbor 169.254.0.11 update-source Tunnel11")
        add(" neighbor 169.254.0.12 peer-group CISCO_SSE")
        add(" neighbor 169.254.0.12 ebgp-multihop 255")
        add(" neighbor 169.254.0.12 update-source Tunnel12")
        add(" !")
        add(" address-family ipv4")
        add("  neighbor CISCO_SSE send-community both")
        add("  neighbor CISCO_SSE soft-reconfiguration inbound")
        add("  neighbor CISCO_SSE route-map FROM_SSE_IMPORT in")
        add("  neighbor CISCO_SSE route-map TO_SSE_EXPORT out")
        add(" exit-address-family")
        add("!")
        add("ip route 169.254.0.1 255.255.255.255 Tunnel1")
        add("ip route 169.254.0.2 255.255.255.255 Tunnel2")
        add("ip route 169.254.0.11 255.255.255.255 Tunnel11")
        add("ip route 169.254.0.12 255.255.255.255 Tunnel12")
        add("")
        add("ip nat inside source list SSE_IKE_NAT interface GigabitEthernet1 overload")
        add("")
        add("ip access-list extended SSE_IKE_NAT")
        add(" 10 permit ip 100.64.255.0 0.0.0.255 any")
        add("")
        add("route-map FROM_SSE_IMPORT deny 999")
        add("ip bgp-community new-format")
        add("")

        if input.advertiseCloudPrefixes {
            add("route-map TO_SSE_EXPORT permit 5")
            add(" match ip address prefix-list AZURE_CENTRAL_PREFIXES")
            add(" set as-path prepend 64514 64514 64514")
            add("!")
        }

        if input.advertiseSDWANPrefixes {
            add("route-map TO_SSE_EXPORT permit 10")
            add(" match ip address prefix-list RFC1918_SUMMARIES")
            add(" set as-path prepend 64514 64514 64514")
            add("!")
            add("route-map TO_SSE_EXPORT permit 15")
            add(" match ip address prefix-list CISCO_MGMT_IOS")
            add(" set as-path prepend 64514 64514")
            add("!")
        }

        add("!")
        add("!")
        add("!")
        add("!")

        return lines.joined(separator: "\n")
    }

    private func addIKEProfileBlock(lines: inout [String], name: String, remoteIP: String, localEmail: String) {
        lines.append("crypto ikev2 profile \(name)")
        lines.append(" match identity remote address \(remoteIP) 255.255.255.255")
        lines.append(" identity local email \(localEmail)")
        lines.append(" authentication remote pre-share")
        lines.append(" authentication local pre-share")
        lines.append(" keyring local sse-kr")
        lines.append(" dpd 10 3 periodic")
        lines.append("!")
    }

    private func addLoopbackInterface(lines: inout [String], number: Int, desc: String) {
        lines.append("interface Loopback\(number)")
        lines.append(" description \(desc)")
        lines.append(" ip address 100.64.255.\(number) 255.255.255.255")
        lines.append(" ip nat inside")
        lines.append("!")
    }

    private func addTunnelInterface(lines: inout [String], number: Int, address: String, sourceLoopback: Int, destination: String, profile: String) {
        lines.append("interface Tunnel\(number)")
        lines.append(" ip address \(address) 255.255.255.255")
        lines.append(" ip tcp adjust-mss 1350")
        lines.append(" tunnel source Loopback\(sourceLoopback)")
        lines.append(" tunnel mode ipsec ipv4")
        lines.append(" tunnel destination \(destination)")
        lines.append(" tunnel protection ipsec profile \(profile)")
        lines.append("!")
    }

    private func addToIPv4(_ ip: String, _ offset: Int) throws -> String {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else {
            throw BuildError.invalidIP(ip)
        }
        var octets: [Int] = []
        for part in parts {
            guard let value = Int(part), (0...255).contains(value) else {
                throw BuildError.invalidIP(ip)
            }
            octets.append(value)
        }
        let host = octets[3] + offset
        guard host <= 254 else {
            throw BuildError.invalidIP("\(ip) (+\(offset) exceeds .254)")
        }
        octets[3] = host
        return "\(octets[0]).\(octets[1]).\(octets[2]).\(octets[3])"
    }
}

struct ContentView: View {
    @StateObject private var vm = BuilderViewModel()

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("IOS-XE Secure Access IPsec/BGP Config Builder")
                    .font(.title3)
                    .bold()
                Spacer()
            }

            HStack(spacing: 12) {
                VStack {
                    Form {
                        Section("Router 1 (IPSEC_BGP_XE_CONFIG rows 4-17, 35)") {
                            TextField("Router Name (C4)", text: $vm.router1Name)
                            TextField("Primary Head-End IP (C8)", text: $vm.router1PrimaryHeadendIP)
                            TextField("Primary Tunnel ID (C9)", text: $vm.router1PrimaryTunnelID)
                            TextField("Secondary Head-End IP (C12)", text: $vm.router1SecondaryHeadendIP)
                            TextField("Secondary Tunnel ID (C13)", text: $vm.router1SecondaryTunnelID)
                            TextField("BGP Router ID (C16)", text: $vm.router1BGPRouterID)
                            TextField("Local ASN (C17)", text: $vm.router1LocalASN)
                            TextField("Tunnel Base IP /28 start (C35)", text: $vm.router1TunnelBaseIP)
                        }

                        Section("Router 2 (IPSEC_BGP_XE_CONFIG rows 20-29, 56)") {
                            TextField("Router Name (C5)", text: $vm.router2Name)
                            TextField("Primary Head-End IP (C20)", text: $vm.router2PrimaryHeadendIP)
                            TextField("Primary Tunnel ID (C21)", text: $vm.router2PrimaryTunnelID)
                            TextField("Secondary Head-End IP (C24)", text: $vm.router2SecondaryHeadendIP)
                            TextField("Secondary Tunnel ID (C25)", text: $vm.router2SecondaryTunnelID)
                            TextField("BGP Router ID (C28)", text: $vm.router2BGPRouterID)
                            TextField("Local ASN (C29)", text: $vm.router2LocalASN)
                            TextField("Tunnel Base IP /28 start (C56)", text: $vm.router2TunnelBaseIP)
                        }

                        Section("Shared") {
                            TextField("Pre-Shared Key (C32)", text: $vm.preSharedKey)
                            Toggle("Advertise SD-WAN Prefixes (C79)", isOn: $vm.advertiseSDWANPrefixes)
                            Toggle("Advertise Cloud Prefixes (C80)", isOn: $vm.advertiseCloudPrefixes)
                        }
                    }
                }
                .frame(minWidth: 430)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Generate") { vm.generate() }
                            .keyboardShortcut(.return)
                        Button("Copy") { vm.copyOutput() }
                        Button("Export...") { vm.exportOutput() }
                        Spacer()
                    }

                    if !vm.errorText.isEmpty {
                        Text(vm.errorText)
                            .foregroundStyle(.red)
                    }

                    TextEditor(text: $vm.outputText)
                        .font(.system(.body, design: .monospaced))
                        .border(Color.gray.opacity(0.25))
                }
                .frame(minWidth: 620, minHeight: 700)
            }
        }
        .padding(12)
        .frame(minWidth: 1080, minHeight: 760)
        .onAppear { vm.generate() }
    }
}

@main
struct IOSXEConfigBuilderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

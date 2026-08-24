# Network Topology

VMware Workstation hosts two virtual networks: pfSense's WAN leg on the built-in **NAT**
network (`VMnet8`) and a **LAN Segment** named `LAN-LAB` (`10.10.0.0/24`) that carries all lab
traffic. pfSense is the only VM with a leg on both networks and is the default gateway, DHCP
relay point, and firewall for the LAN.

```mermaid
flowchart TB
    INTERNET(["Internet"])

    subgraph HOST["VMware Workstation Host (Windows 11)"]
        subgraph WAN_SEG["WAN — VMnet8 (NAT)"]
        end

        subgraph LAN_SEG["LAN — LAN Segment 'LAN-LAB', 10.10.0.0/24"]
            PFSENSE["pfSense\nWAN + LAN\n10.10.0.1/24"]
            DC["samba-dc01\nAD DC / DNS / KDC / NTP\n10.10.0.10"]
            DOCKER["docker01\nDocker Engine + Traefik\n10.10.0.20"]
            AUTHENTIK["authentik01\nIAM Platform\n10.10.0.30"]
            LINUXCLIENT["linux-client01\nUbuntu Desktop\nDHCP (10.10.0.100-199)"]
            WINCLIENT["win-client01\nWindows 11\nDHCP (10.10.0.100-199)"]
        end
    end

    INTERNET <--> WAN_SEG
    WAN_SEG <--> PFSENSE
    PFSENSE --- DC
    PFSENSE --- DOCKER
    PFSENSE --- AUTHENTIK
    PFSENSE --- LINUXCLIENT
    PFSENSE --- WINCLIENT

    DC <-. DNS/Kerberos/NTP .-> LINUXCLIENT
    DC <-. DNS/Kerberos/NTP .-> WINCLIENT
    DOCKER <-. LDAP/OIDC .-> AUTHENTIK
    AUTHENTIK <-. LDAP bind .-> DC

    classDef fw fill:#f8d7da,stroke:#c0392b,color:#000
    classDef infra fill:#d6eaf8,stroke:#2874a6,color:#000
    classDef client fill:#d5f5e3,stroke:#1e8449,color:#000
    class PFSENSE fw
    class DC,DOCKER,AUTHENTIK infra
    class LINUXCLIENT,WINCLIENT client
```

## Addressing plan

| Host           | Role                                      | Address                |
| -------------- | ----------------------------------------- | ---------------------- |
| pfSense (LAN)  | Gateway / Firewall / DHCP / DNS forwarder | `10.10.0.1/24`         |
| samba-dc01     | AD DC, LDAP, Kerberos, DNS, NTP           | `10.10.0.10`           |
| docker01       | Docker Engine, reverse proxy, apps        | `10.10.0.20`           |
| authentik01    | Authentik IAM (bare host or VM)           | `10.10.0.30`           |
| linux-client01 | Ubuntu Desktop, SSSD domain member        | DHCP `10.10.0.100-199` |
| win-client01   | Windows 11, domain member                 | DHCP `10.10.0.100-199` |

DHCP pool `10.10.0.100–10.10.0.199` is served by pfSense; DHCP option 6 (DNS) points clients
at `10.10.0.10` so domain-joined machines resolve `lab.internal` correctly. See
[dns-architecture.md](dns-architecture.md) for resolution details.

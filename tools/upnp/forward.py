#!/usr/bin/env python3
"""Open the Soulseek listener port on the router via UPnP-IGD (pure stdlib).

Runs on the HOST (so it maps to the host's LAN IP) as part of `zig build serve`. Soulseek
downloads need the uploader to connect back to your listen port; behind NAT that port must be
forwarded. This asks the router to forward it automatically. Best-effort: if the router has no
UPnP or refuses, it prints how to forward manually and exits 0 so serving still proceeds.

Usage: forward.py [port]   (default 41000)
"""
import socket
import sys
import urllib.request
import xml.etree.ElementTree as ET
from urllib.parse import urljoin, urlparse

SSDP_ADDR, SSDP_PORT = "239.255.255.250", 1900
WAN_SERVICES = (
    "urn:schemas-upnp-org:service:WANIPConnection:2",
    "urn:schemas-upnp-org:service:WANIPConnection:1",
    "urn:schemas-upnp-org:service:WANPPPConnection:1",
)


def log(msg):
    print(f"upnp: {msg}", flush=True)


def discover(timeout=3):
    """Return the IGD description-XML URL, or None."""
    req = (
        f"M-SEARCH * HTTP/1.1\r\nHOST:{SSDP_ADDR}:{SSDP_PORT}\r\n"
        'MAN:"ssdp:discover"\r\nMX:2\r\n'
        "ST:urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n"
    ).encode()
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.settimeout(timeout)
    try:
        s.sendto(req, (SSDP_ADDR, SSDP_PORT))
        while True:
            data, _ = s.recvfrom(65507)
            for line in data.decode(errors="ignore").splitlines():
                if line.lower().startswith("location:"):
                    return line.split(":", 1)[1].strip()
    except socket.timeout:
        return None
    finally:
        s.close()


def local_ip_towards(host):
    """LAN IP this host uses to reach `host` (the router)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((host, 80))
        return s.getsockname()[0]
    finally:
        s.close()


def _tag(el):
    return el.tag.split("}")[-1]


def find_control(desc_url):
    """Return (control_url, service_type) for the WAN connection service."""
    xml = urllib.request.urlopen(desc_url, timeout=5).read()
    root = ET.fromstring(xml)
    services = [el for el in root.iter() if _tag(el) == "service"]
    for want in WAN_SERVICES:
        for svc in services:
            st = ctrl = None
            for child in svc:
                if _tag(child) == "serviceType":
                    st = (child.text or "").strip()
                elif _tag(child) == "controlURL":
                    ctrl = (child.text or "").strip()
            if st == want and ctrl:
                return urljoin(desc_url, ctrl), st
    return None, None


def soap(control_url, service_type, action, body_args):
    args = "".join(f"<{k}>{v}</{k}>" for k, v in body_args)
    envelope = (
        '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        f'<s:Body><u:{action} xmlns:u="{service_type}">{args}'
        f"</u:{action}></s:Body></s:Envelope>"
    ).encode()
    req = urllib.request.Request(
        control_url,
        data=envelope,
        headers={
            "Content-Type": 'text/xml; charset="utf-8"',
            "SOAPAction": f'"{service_type}#{action}"',
        },
        method="POST",
    )
    return urllib.request.urlopen(req, timeout=5).read()


def main():
    port = 41000
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            pass

    desc = discover()
    if not desc:
        log(f"no UPnP router found; forward TCP {port} to this host on your router manually")
        return 0

    host = urlparse(desc).hostname
    control, stype = find_control(desc)
    if not control:
        log(f"router has no WAN connection service; forward TCP {port} manually")
        return 0

    lan_ip = local_ip_towards(host)
    common = [
        ("NewRemoteHost", ""),
        ("NewExternalPort", port),
        ("NewProtocol", "TCP"),
    ]
    # Add the mapping (lease 0 = until the router reboots). Retry with a finite lease if the
    # router rejects 0 (some do).
    add = common + [
        ("NewInternalPort", port),
        ("NewInternalClient", lan_ip),
        ("NewEnabled", 1),
        ("NewPortMappingDescription", "syncdash-soulseek"),
        ("NewLeaseDuration", 0),
    ]
    for lease in (0, 3600):
        add[-1] = ("NewLeaseDuration", lease)
        try:
            soap(control, stype, "AddPortMapping", add)
            break
        except Exception as e:  # noqa: BLE001
            if lease == 3600:
                log(f"AddPortMapping failed ({e}); forward TCP {port} to {lan_ip} manually")
                return 0

    # Confirm + report the external IP.
    try:
        r = soap(control, stype, "GetSpecificPortMappingEntry", common)
        internal = next(
            (_tag(x) and x.text for x in ET.fromstring(r).iter() if _tag(x) == "NewInternalClient"),
            None,
        )
    except Exception:  # noqa: BLE001
        internal = lan_ip
    ext_ip = "?"
    try:
        r = soap(control, stype, "GetExternalIPAddress", [])
        ext_ip = next(
            (x.text for x in ET.fromstring(r).iter() if _tag(x) == "NewExternalIPAddress"),
            "?",
        )
    except Exception:  # noqa: BLE001
        pass
    log(f"mapped TCP {port} -> {internal}:{port} (external IP {ext_ip}); Soulseek transfers can now connect in")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""vSAN cluster shutdown / restart through the vSAN management API.

This is what the vSphere Client's Cluster -> vSAN -> Shutdown Cluster and
Restart Cluster wizards do (VsanClusterPowerSystem, vSAN 7.0 U3 and later), so
shutdown_ntnx1_vcf.sh and startup_ntnx1_vcf.sh can run them with --vsan.
Standard library only (no pyVmomi), so it also runs inside Home Assistant.

    vsan_cluster_power.py status   CLUSTER_MOREF   print the cluster power status
    vsan_cluster_power.py shutdown CLUSTER_MOREF   Shutdown Cluster
    vsan_cluster_power.py restart  CLUSTER_MOREF   Restart Cluster, waits for it

CLUSTER_MOREF is the cluster's managed object id, e.g. domain-c9
(`govc find -i /dc/host/cluster` prints ClusterComputeResource:domain-c9).
vCenter and the login come from GOVC_URL, GOVC_USERNAME and GOVC_PASSWORD, the
same variables the shell scripts export for govc.

shutdown returns once vSAN has accepted the request and the task is running:
vSAN then powers off the VMs, vCenter itself (when it runs on the cluster) and
finally the hosts, so this script loses its connection part-way by design.
restart waits for the task to finish (up to 60 minutes) and fails if it does.
"""
import http.cookiejar
import os
import ssl
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

VIM_ACTION = "urn:vim25/8.0.0.0"
VSAN_ACTION = "urn:vsan/vSAN 7.0U3"  # VsanClusterPowerSystem's API version
RESTART_TIMEOUT = 3600


def die(msg):
    print(f"ERROR {msg}")
    sys.exit(1)


def local(tag):
    return tag.rsplit("}", 1)[-1]


def find(node, name):
    """First descendant element with this local name (namespaces ignored)."""
    for el in node.iter():
        if local(el.tag) == name:
            return el
    return None


def text(node, name, default=""):
    el = find(node, name)
    return el.text if el is not None and el.text is not None else default


class Client:
    def __init__(self, host, user, password):
        self.base = f"https://{host}"
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE  # lab vCenter, self-signed
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPSHandler(context=ctx),
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        self.user, self.password = user, password

    def call(self, path, action, body, timeout=60):
        envelope = (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"'
            ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
            ' xmlns:xsd="http://www.w3.org/2001/XMLSchema">'
            f"<soapenv:Body>{body}</soapenv:Body></soapenv:Envelope>")
        req = urllib.request.Request(
            self.base + path, data=envelope.encode(), method="POST",
            headers={"Content-Type": "text/xml; charset=utf-8", "SOAPAction": action})
        try:
            with self.opener.open(req, timeout=timeout) as resp:
                return ET.fromstring(resp.read())
        except urllib.error.HTTPError as e:  # SOAP faults come back as HTTP 500
            # A service that isn't up yet (vsan-health just after vCenter
            # boots) answers 503 with an HTML page, not a SOAP fault.
            try:
                root = ET.fromstring(e.read())
            except ET.ParseError:
                die(f"HTTP {e.code} {e.reason} from {path}")
            die(text(root, "faultstring", f"HTTP {e.code}"))
        except (urllib.error.URLError, OSError) as e:
            die(f"can't reach {self.base}{path}: {getattr(e, 'reason', e)}")

    def vim(self, body, **kw):
        return self.call("/sdk", VIM_ACTION, body, **kw)

    def vsan(self, body, **kw):
        return self.call("/vsanHealth", VSAN_ACTION, body, **kw)

    def login(self):
        # On vCenter the session manager is always "SessionManager"; the
        # session cookie it sets is accepted by /vsanHealth as well.
        self.vim(
            '<Login xmlns="urn:vim25"><_this type="SessionManager">SessionManager</_this>'
            f"<userName>{escape(self.user)}</userName>"
            f"<password>{escape(self.password)}</password></Login>")

    def logout(self):
        try:
            self.vim('<Logout xmlns="urn:vim25"><_this type="SessionManager">SessionManager</_this></Logout>',
                     timeout=10)
        except Exception:  # vCenter may already be going down
            pass

    def power_context(self, cluster):
        root = self.vsan(
            '<QueryClusterPowerContext xmlns="urn:vsan">'
            '<_this type="VsanClusterPowerSystem">vsan-cluster-power-system</_this>'
            f'<cluster type="ClusterComputeResource">{escape(cluster)}</cluster>'
            "</QueryClusterPowerContext>")
        return text(root, "currentClusterPowerStatus", "unknown")

    def power_action(self, cluster, target, reason=None):
        spec = f"<targetPowerStatus>{target}</targetPowerStatus>"
        if reason:
            spec += f"<powerOffReason>{escape(reason)}</powerOffReason>"
        root = self.vsan(
            '<PerformClusterPowerAction xmlns="urn:vsan">'
            '<_this type="VsanClusterPowerSystem">vsan-cluster-power-system</_this>'
            f'<cluster type="ClusterComputeResource">{escape(cluster)}</cluster>'
            f"<spec>{spec}</spec></PerformClusterPowerAction>")
        el = find(root, "returnval")
        if el is None or not el.text:
            die("vSAN accepted the request but returned no task")
        return el.text

    def task_info(self, task):
        root = self.vim(
            '<RetrievePropertiesEx xmlns="urn:vim25">'
            '<_this type="PropertyCollector">propertyCollector</_this>'
            "<specSet><propSet><type>Task</type><pathSet>info</pathSet></propSet>"
            f'<objectSet><obj type="Task">{escape(task)}</obj></objectSet></specSet>'
            "<options/></RetrievePropertiesEx>")
        info = find(root, "val")
        if info is None:
            return "unknown", "", ""
        error = find(info, "error")
        return (text(info, "state", "unknown"), text(info, "progress", ""),
                text(error, "localizedMessage", "") if error is not None else "")


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("status", "shutdown", "restart"):
        print(__doc__.strip().split("\n\n")[2])
        sys.exit(2)
    action, cluster = sys.argv[1], sys.argv[2].split(":")[-1]
    host = os.environ.get("GOVC_URL", "").removeprefix("https://").split("/")[0]
    user, password = os.environ.get("GOVC_USERNAME", ""), os.environ.get("GOVC_PASSWORD", "")
    if not (host and user and password):
        die("GOVC_URL, GOVC_USERNAME and GOVC_PASSWORD must be set")

    c = Client(host, user, password)
    c.login()
    status = c.power_context(cluster)

    if action == "status":
        print(status)
    elif action == "shutdown":
        task = c.power_action(cluster, "clusterPoweredOff", "Scheduled maintenance")
        print(f"OK vSAN Shutdown Cluster started ({task}), cluster was {status}")
    else:
        if status == "clusterPoweredOn":
            print("OK vSAN cluster is already powered on")
        else:
            task = c.power_action(cluster, "clusterPoweredOn")
            print(f"vSAN Restart Cluster started ({task}), cluster was {status}", flush=True)
            deadline = time.time() + RESTART_TIMEOUT
            last = None
            while True:
                state, progress, error = c.task_info(task)
                if (state, progress) != last:
                    print(f"  task {state}{' ' + progress + '%' if progress else ''}", flush=True)
                    last = (state, progress)
                if state == "success":
                    break
                if state == "error":
                    c.logout()
                    die(f"vSAN Restart Cluster failed: {error or 'no message'}")
                if time.time() > deadline:
                    c.logout()
                    die(f"vSAN Restart Cluster still {state} after {RESTART_TIMEOUT // 60} min")
                time.sleep(15)
            print(f"OK vSAN cluster restarted, now {c.power_context(cluster)}")
    c.logout()


if __name__ == "__main__":
    main()

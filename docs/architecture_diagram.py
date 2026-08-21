#!/usr/bin/env python3
"""
cloud-native-ha-platform — Architecture Diagram
================================================
Run from WSL:
    source ~/diagrams-env/bin/activate
    cd "/mnt/c/Users/OnlyM/Denis Cloud Projects/cloud-native-ha-platform/docs"
    python3 architecture_diagram.py

Output:
    architecture.png
"""

import os
from diagrams import Diagram, Cluster, Edge
from diagrams.azure.compute import VMSS
from diagrams.azure.network import LoadBalancers
from diagrams.gcp.compute import GCE
from diagrams.onprem.gitops import ArgoCD
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.vcs import Github
from diagrams.onprem.iac import Terraform, Ansible
from diagrams.onprem.network import Nginx
from diagrams.onprem.client import User
from diagrams.k8s.compute import Pod
from diagrams.k8s.network import Ingress

OUT = os.path.dirname(os.path.abspath(__file__))

NODE_ATTR = {
    "fontsize": "14",
    "fontname": "Helvetica-Bold",
    "width": "2.3",
    "height": "3.6",
    "fixedsize": "false",
    "labelloc": "b",
    "imagepos": "tc",
    "imagescale": "true",
}

GRAPH_ATTR = {
    "label": "cloud-native-ha-platform  —  Architecture",
    "labelloc": "t",
    "labeljust": "c",
    "fontsize": "36",
    "fontname": "Helvetica-Bold",
    "bgcolor": "white",
    "pad": "1.0",
    "nodesep": "1.3",
    "ranksep": "2.4",
    "splines": "spline",
    "dpi": "220",
}

C_SOURCE = {"style": "filled", "bgcolor": "#f5f5f5", "fontsize": "18",
            "fontname": "Helvetica-Bold", "fontcolor": "#212121"}
C_IAC = {"style": "filled", "bgcolor": "#fff8e1", "fontsize": "18",
         "fontname": "Helvetica-Bold", "fontcolor": "#bf360c"}
C_AZURE = {"style": "filled", "bgcolor": "#e3f2fd", "fontsize": "22",
           "fontname": "Helvetica-Bold", "fontcolor": "#0d47a1"}
C_K3S = {"style": "filled", "bgcolor": "#ede7f6", "fontsize": "17",
         "fontname": "Helvetica-Bold", "fontcolor": "#4527a0"}
C_APPS = {"style": "filled", "bgcolor": "#e8f5e9", "fontsize": "16",
          "fontname": "Helvetica-Bold", "fontcolor": "#1b5e20"}
C_GCP = {"style": "filled", "bgcolor": "#fce4ec", "fontsize": "20",
         "fontname": "Helvetica-Bold", "fontcolor": "#880e4f"}


def gitops(label=""):
    return Edge(color="#1b5e20", penwidth="3.2", label=label, fontsize="14",
                fontcolor="#1b5e20", fontname="Helvetica-Bold")


def infra(label=""):
    return Edge(color="#4e342e", penwidth="2.6", style="dashed", label=label,
                fontsize="13", fontcolor="#4e342e", fontname="Helvetica-Bold",
                constraint="false", arrowsize="1.2")


def traffic(label=""):
    return Edge(color="#0277bd", penwidth="2.8", label=label, fontsize="14",
                fontcolor="#0277bd", fontname="Helvetica-Bold")


def ci_edge(label=""):
    return Edge(color="#e65100", penwidth="2.8", label=label, fontsize="14",
                fontcolor="#e65100", fontname="Helvetica-Bold")


with Diagram(
    "",
    filename=os.path.join(OUT, "architecture"),
    show=False,
    outformat="png",
    graph_attr=GRAPH_ATTR,
    node_attr=NODE_ATTR,
    direction="TB",
):

    with Cluster("Source of truth", graph_attr=C_SOURCE):
        github = Github("GitHub")

    with Cluster("IaC — run once / on change", graph_attr=C_IAC):
        terraform = Terraform("")
        ansible = Ansible("")

    ci = GithubActions("GitHub Actions\n(planned)")

    with Cluster("GCP — us-central1  (cherry #2, isolated)", graph_attr=C_GCP):
        gcp_node = GCE("gcp-showcase")
        proxy = Nginx("NGINX proxy")

    browser = User("Browser")

    with Cluster("Azure West Europe  (primary)", graph_attr=C_AZURE):
        lb_west = LoadBalancers("Load\nBalancer")
        vmss_west = VMSS("VMSS")
        with Cluster("K3s cluster", graph_attr=C_K3S):
            argocd = ArgoCD("")
            kuma = Pod("kuma")
            with Cluster("hello-world ns — Traefik + TLS", graph_attr=C_APPS):
                ing_west = Ingress("")
                pods_west = Pod("2-6x")

    with Cluster("Azure Germany West Central  (failover)", graph_attr=C_AZURE):
        lb_de = LoadBalancers("Load\nBalancer")
        vmss_de = VMSS("VMSS")
        with Cluster("K3s cluster ", graph_attr=C_K3S):
            with Cluster("hello-world ns — Traefik + TLS", graph_attr=C_APPS):
                ing_de = Ingress("")
                pods_de = Pod("2x")

    # IaC provisions / configures everything - one representative edge each,
    # since Terraform/Ansible touch all three node groups the same way
    terraform >> infra("provisions all 3 node groups") >> vmss_west
    ansible >> infra("configures K3s + NGINX, same playbook") >> gcp_node

    # CI
    github >> ci_edge("on push") >> ci

    # GitOps — ArgoCD lives in West Europe, manages both Azure clusters
    github >> gitops("ArgoCD polls") >> argocd
    argocd >> gitops("deploys") >> ing_west
    argocd >> gitops("deploys") >> ing_de
    argocd >> gitops("deploys") >> kuma

    # Real user traffic — through the proxy, failing over on West EU's failure
    browser >> traffic("HTTPS") >> proxy
    proxy >> traffic("primary") >> lb_west
    proxy >> traffic("backup, on failure") >> lb_de
    lb_west >> traffic() >> ing_west
    lb_de >> traffic() >> ing_de
    ing_west >> traffic() >> pods_west
    ing_de >> traffic() >> pods_de

    # Uptime Kuma checks both regions and the proxy directly, independent of ArgoCD
    kuma >> traffic("health checks") >> ing_west
    kuma >> traffic() >> ing_de
    kuma >> traffic() >> proxy


print("\nDone!  ->  docs/architecture.png")

"""Render docs/architecture.png with mingrammer/diagrams.

Run from the repo root:
    python3 docs/render-architecture.py
or from this dir:
    python3 render-architecture.py

Requires: pip install diagrams ; apt install graphviz
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import ECR, Lambda
from diagrams.aws.integration import Eventbridge, SNS
from diagrams.aws.management import Cloudwatch
from diagrams.aws.security import IAMRole
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.client import User
from diagrams.onprem.vcs import Github

graph_attr = {
    "fontsize": "16",
    "labelloc": "t",
    "splines": "spline",
    "pad": "0.6",
    "nodesep": "0.65",
    "ranksep": "1.0",
    "bgcolor": "white",
}
node_attr = {"fontsize": "13"}
edge_attr = {"fontsize": "11"}

with Diagram(
    "aws-supply-chain-security",
    filename="architecture",
    show=False,
    direction="LR",
    outformat="png",
    graph_attr=graph_attr,
    node_attr=node_attr,
    edge_attr=edge_attr,
):
    src = Github("sre-reference-app\n(source code)")

    with Cluster("GitHub Actions runner"):
        gha = GithubActions("supply-chain.yml")
        oidc = IAMRole("OIDC token")

    with Cluster("Sigstore (public)"):
        fulcio = IAMRole("Fulcio\nshort-lived cert")
        rekor = Cloudwatch("Rekor\ntransparency log")

    with Cluster("AWS — workloads-dev (us-west-2)"):
        ecr = ECR("ECR repo\nsupply-chain-demo\nIMMUTABLE / scan-on-push")

        with Cluster("Alert path"):
            eb = Eventbridge("ECR Image Scan\nrule")
            fn = Lambda("scan-findings-handler\n(severity gate)")
            topic = SNS("scan-findings\n(KMS-encrypted)")

    user = User("jadenscottrazo@\ngmail.com")

    src >> Edge(label="actions/checkout") >> gha
    gha >> Edge(label="id-token") >> oidc
    oidc >> Edge(label="OIDC token") >> fulcio
    fulcio >> Edge(label="x509 cert") >> gha
    gha >> Edge(label="signature\n+ cert claims") >> rekor
    gha >> Edge(label="docker push", style="bold") >> ecr
    gha >> Edge(label="cosign sign", style="bold") >> ecr

    ecr >> Edge(label="ECR Image Scan COMPLETE") >> eb
    eb >> Edge(label="invoke") >> fn
    fn >> Edge(label="publish if HIGH+") >> topic
    topic >> Edge(label="email alert") >> user

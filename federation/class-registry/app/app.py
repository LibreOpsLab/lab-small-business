"""
Class Registry — a small web app the lecturer runs so students can self-register their
business's domain label + subnet, download the class CA root certificate, and get a
wildcard TLS cert for their edge reverse proxy signed by it. See docs/ClassRegistry.md.

Deliberately kept to stdlib + Flask: sqlite3 for storage, ipaddress for subnet-overlap
checks, subprocess for openssl/rndc. No ORM, no JS framework, no build step.
"""
import datetime
import ipaddress
import os
import re
import sqlite3
import subprocess
import tempfile

from flask import Flask, g, jsonify, render_template, request, send_file, abort

DB_PATH = os.environ.get("REGISTRY_DB", "/data/registry.db")
CLASS_ROOT_DOMAIN = os.environ.get("CLASS_ROOT_DOMAIN", "lab.internet")
CLASS_REGISTRY_TOKEN = os.environ.get("CLASS_REGISTRY_TOKEN", "")
CA_DIR = os.environ.get("CLASS_CA_DIR", "/ca")
CA_CNF = os.path.join(CA_DIR, "class-ca.cnf")
CA_CERT = os.path.join(CA_DIR, "certs", "class-ca.cert.pem")
ZONE_FILE = os.environ.get("ZONE_FILE", "/bind-zones/db.lab.internet")
RNDC_KEY = os.environ.get("RNDC_KEY_FILE", "/keys/rndc.key")
RNDC_SERVER = os.environ.get("RNDC_SERVER", "bind9")

NAME_RE = re.compile(r"^[a-z][a-z0-9-]{1,19}$")

app = Flask(__name__)


def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(_exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS businesses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            subnet TEXT UNIQUE NOT NULL,
            edge_ip TEXT NOT NULL,
            contact TEXT,
            registered_at TEXT NOT NULL,
            cert_issued INTEGER NOT NULL DEFAULT 0
        )
        """
    )
    conn.commit()
    conn.close()


def require_token():
    token = request.form.get("token") or request.headers.get("X-Class-Token", "")
    if not CLASS_REGISTRY_TOKEN:
        abort(500, "Registry misconfigured: CLASS_REGISTRY_TOKEN is not set on the server.")
    if token != CLASS_REGISTRY_TOKEN:
        abort(403, "Invalid or missing registration token.")


def subnet_overlaps_existing(new_subnet, db, exclude_id=None):
    new_net = ipaddress.ip_network(new_subnet, strict=True)
    rows = db.execute("SELECT id, name, subnet FROM businesses").fetchall()
    for row in rows:
        if exclude_id is not None and row["id"] == exclude_id:
            continue
        existing_net = ipaddress.ip_network(row["subnet"], strict=True)
        if new_net.overlaps(existing_net):
            return row["name"]
    return None


def regenerate_zone_file(db):
    """Rewrites the lab.internet zone file from the current businesses table and asks
    BIND to reload it. Each business gets an NS delegation to an in-bailiwick nameserver
    (ns.<name>.lab.internet) glued to their edge_ip - the standard real-world pattern for
    delegating a subdomain to a nameserver that itself lives inside that subdomain."""
    serial = int(datetime.datetime.utcnow().timestamp())
    zone_ns_ip = os.environ.get("ZONE_NS_IP", "127.0.0.1")
    lines = [
        "$TTL 3600",
        f"@   IN  SOA ns1.{CLASS_ROOT_DOMAIN}. hostmaster.{CLASS_ROOT_DOMAIN}. (",
        f"        {serial}   ; serial",
        "        3600        ; refresh",
        "        900         ; retry",
        "        604800      ; expire",
        "        3600 )      ; minimum",
        "",
        f"    IN  NS  ns1.{CLASS_ROOT_DOMAIN}.",
        f"ns1 IN  A   {zone_ns_ip}",
        "",
        "; --- registered businesses ---",
    ]
    for row in db.execute("SELECT name, edge_ip FROM businesses ORDER BY name"):
        lines.append(f"{row['name']}     IN  NS  ns.{row['name']}.{CLASS_ROOT_DOMAIN}.")
        lines.append(f"ns.{row['name']}  IN  A   {row['edge_ip']}")
    with open(ZONE_FILE, "w") as fh:
        fh.write("\n".join(lines) + "\n")

    result = subprocess.run(
        ["rndc", "-s", RNDC_SERVER, "-k", RNDC_KEY, "reload", CLASS_ROOT_DOMAIN],
        capture_output=True, text=True, timeout=15,
    )
    if result.returncode != 0:
        app.logger.error("rndc reload failed: %s", result.stderr.strip())
    return result.returncode == 0


@app.route("/")
def index():
    db = get_db()
    businesses = db.execute(
        "SELECT * FROM businesses ORDER BY registered_at"
    ).fetchall()
    return render_template(
        "index.html",
        businesses=businesses,
        root_domain=CLASS_ROOT_DOMAIN,
        diagram=render_diagram_svg(businesses),
    )


@app.route("/api/businesses")
def api_businesses():
    db = get_db()
    rows = db.execute("SELECT name, subnet, edge_ip, registered_at, cert_issued FROM businesses ORDER BY name").fetchall()
    return jsonify([dict(r) for r in rows])


@app.route("/api/register", methods=["POST"])
def register():
    require_token()
    name = (request.form.get("name") or "").strip().lower()
    subnet = (request.form.get("subnet") or "").strip()
    edge_ip = (request.form.get("edge_ip") or "").strip()
    contact = (request.form.get("contact") or "").strip()

    if not NAME_RE.match(name):
        abort(400, "name must be 2-20 lowercase letters/digits/hyphens, starting with a letter.")
    try:
        net = ipaddress.ip_network(subnet, strict=True)
        if net.prefixlen != 24 or not net.is_private:
            raise ValueError
    except ValueError:
        abort(400, "subnet must be a private /24 CIDR, e.g. 10.20.0.0/24.")
    try:
        ipaddress.ip_address(edge_ip)
    except ValueError:
        abort(400, "edge_ip must be a valid IP address (your edge proxy's reachable address).")

    db = get_db()
    if db.execute("SELECT 1 FROM businesses WHERE name = ?", (name,)).fetchone():
        abort(409, f"'{name}' is already registered.")
    conflict = subnet_overlaps_existing(subnet, db)
    if conflict:
        abort(409, f"subnet {subnet} overlaps already-registered business '{conflict}'.")

    db.execute(
        "INSERT INTO businesses (name, subnet, edge_ip, contact, registered_at) VALUES (?, ?, ?, ?, ?)",
        (name, subnet, edge_ip, contact, datetime.datetime.utcnow().isoformat()),
    )
    db.commit()
    reload_ok = regenerate_zone_file(db)

    return jsonify({
        "status": "registered",
        "name": name,
        "domain": f"{name}.{CLASS_ROOT_DOMAIN}",
        "ns_delegated": reload_ok,
        "next_step": f"POST /api/request-cert with name={name} and a CSR for "
                      f"{name}.{CLASS_ROOT_DOMAIN} / *.{name}.{CLASS_ROOT_DOMAIN} to get your "
                      f"edge proxy's certificate signed.",
    }), 201


@app.route("/api/request-cert", methods=["POST"])
def request_cert():
    require_token()
    name = (request.form.get("name") or "").strip().lower()
    csr_pem = request.form.get("csr") or (request.files["csr"].read().decode() if "csr" in request.files else None)

    if not NAME_RE.match(name):
        abort(400, "invalid name")
    if not csr_pem or "BEGIN CERTIFICATE REQUEST" not in csr_pem:
        abort(400, "csr must be a PEM-encoded certificate signing request.")

    db = get_db()
    row = db.execute("SELECT * FROM businesses WHERE name = ?", (name,)).fetchone()
    if not row:
        abort(404, f"'{name}' is not registered — POST /api/register first.")

    with tempfile.TemporaryDirectory() as tmp:
        csr_path = os.path.join(tmp, "request.csr")
        cert_path = os.path.join(tmp, "signed.cert.pem")
        with open(csr_path, "w") as fh:
            fh.write(csr_pem)

        san = f"DNS:{name}.{CLASS_ROOT_DOMAIN},DNS:*.{name}.{CLASS_ROOT_DOMAIN}"
        env = {**os.environ, "SAN": san}
        result = subprocess.run(
            ["openssl", "ca", "-config", CA_CNF, "-batch",
             "-extensions", "server_cert", "-days", "397", "-notext", "-md", "sha384",
             "-in", csr_path, "-out", cert_path],
            cwd=CA_DIR, env=env, capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            app.logger.error("openssl ca failed: %s", result.stderr.strip())
            abort(500, "Certificate signing failed - see registry container logs.")

        with open(cert_path) as fh:
            signed_cert = fh.read()
        with open(CA_CERT) as fh:
            ca_cert = fh.read()

    db.execute("UPDATE businesses SET cert_issued = 1 WHERE name = ?", (name,))
    db.commit()

    return jsonify({
        "status": "signed",
        "name": name,
        "cert_pem": signed_cert,
        "ca_cert_pem": ca_cert,
        "fullchain_pem": signed_cert + ca_cert,
    })


@app.route("/ca/root.crt")
def download_ca():
    if not os.path.exists(CA_CERT):
        abort(503, "Class CA not yet initialised - lecturer must run ca/init-class-ca.sh.")
    return send_file(CA_CERT, mimetype="application/x-pem-file", as_attachment=True,
                      download_name="lab-class-ca.crt")


@app.route("/health")
def health():
    return "ok"


def render_diagram_svg(businesses):
    """Small hand-rolled hub-and-spoke SVG (no JS/CDN dependency - this lab runs fully
    offline). Root in the centre, one node per registered business arranged in a circle."""
    import math

    width, height, cx, cy, radius = 640, 480, 320, 260, 170
    parts = [f'<svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg" '
              f'font-family="sans-serif" font-size="12">']
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="34" fill="#f8d7da" stroke="#c0392b" stroke-width="2"/>')
    parts.append(f'<text x="{cx}" y="{cy-4}" text-anchor="middle" font-weight="bold">Class Root</text>')
    parts.append(f'<text x="{cx}" y="{cy+12}" text-anchor="middle" font-size="10">(Lecturer)</text>')

    n = len(businesses)
    for i, biz in enumerate(businesses):
        angle = (2 * math.pi * i / n) - math.pi / 2 if n else 0
        x = cx + radius * math.cos(angle)
        y = cy + radius * math.sin(angle)
        parts.append(f'<line x1="{cx}" y1="{cy}" x2="{x:.0f}" y2="{y:.0f}" stroke="#2874a6" stroke-width="2"/>')
        colour = "#d5f5e3" if biz["cert_issued"] else "#fdebd0"
        stroke = "#1e8449" if biz["cert_issued"] else "#b9770e"
        parts.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="46" fill="{colour}" stroke="{stroke}" stroke-width="2"/>')
        parts.append(f'<text x="{x:.0f}" y="{y-6:.0f}" text-anchor="middle" font-weight="bold">{biz["name"]}</text>')
        parts.append(f'<text x="{x:.0f}" y="{y+8:.0f}" text-anchor="middle" font-size="9">{biz["subnet"]}</text>')
        label = "cert issued" if biz["cert_issued"] else "NS delegated only"
        parts.append(f'<text x="{x:.0f}" y="{y+22:.0f}" text-anchor="middle" font-size="9">{label}</text>')

    parts.append("</svg>")
    return "".join(parts)


init_db()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)

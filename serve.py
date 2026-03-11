#!/usr/bin/env python3
"""
Local web server for Godot HTML5 export testing.

Sets Cross-Origin-Opener-Policy and Cross-Origin-Embedder-Policy headers,
which are required for SharedArrayBuffer (used by Godot's threading model).

Usage:
    python serve.py                # HTTP — localhost only
    python serve.py --https        # HTTPS — reachable from phone on same WiFi
    python serve.py --https --regen-cert   # force new self-signed certificate
    python serve.py --port 9000    # custom port
"""

import argparse
import http.server
import os
import socket
import ssl
import subprocess
import sys

SERVE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "export", "web")
DEFAULT_PORT = 8060
CERT_FILE = "serve_cert.pem"
KEY_FILE = "serve_key.pem"


class GodotHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the export/web directory with COOP/COEP headers."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=SERVE_DIR, **kwargs)

    def end_headers(self):
        # Required for SharedArrayBuffer (Godot uses it for threading)
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

    def log_message(self, fmt, *args):
        # Only log errors — suppress the per-asset 200s
        if len(args) >= 2 and not str(args[1]).startswith("2"):
            print(f"  {self.address_string()} — {args[0]} → {args[1]}")


def local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def generate_cert(ip: str) -> bool:
    """Generate a self-signed TLS cert valid for the local IP using openssl."""
    san = f"subjectAltName=IP:{ip},IP:127.0.0.1"
    try:
        subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048",
                "-keyout", KEY_FILE, "-out", CERT_FILE,
                "-days", "365", "-nodes",
                "-subj", f"/CN={ip}",
                "-addext", san,
            ],
            check=True,
            capture_output=True,
        )
        return True
    except FileNotFoundError:
        print("  openssl not found in PATH.")
        return False
    except subprocess.CalledProcessError as e:
        print(f"  openssl error: {e.stderr.decode().strip()}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Serve Godot HTML5 export with correct COOP/COEP headers."
    )
    parser.add_argument(
        "--https", action="store_true",
        help="Enable HTTPS (required for SharedArrayBuffer on mobile browsers)"
    )
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument(
        "--regen-cert", action="store_true",
        help="Force regeneration of the self-signed TLS certificate"
    )
    args = parser.parse_args()

    if not os.path.isdir(SERVE_DIR):
        print(f"\n  ERROR: export directory not found: {SERVE_DIR}")
        print("  Run export_and_serve.sh to export first, or export from the Godot editor.")
        sys.exit(1)

    if not any(f.endswith(".html") for f in os.listdir(SERVE_DIR)):
        print(f"\n  WARNING: {SERVE_DIR} exists but contains no .html file.")
        print("  The export may not have completed successfully.")

    ip = local_ip()
    httpd = http.server.HTTPServer(("0.0.0.0", args.port), GodotHandler)

    if args.https:
        need_cert = args.regen_cert or not (
            os.path.exists(CERT_FILE) and os.path.exists(KEY_FILE)
        )
        if need_cert:
            print(f"\n  Generating self-signed certificate for {ip} ...")
            if not generate_cert(ip):
                print("  Install openssl and retry.")
                sys.exit(1)
            print(f"  Certificate saved to {CERT_FILE}")

        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(CERT_FILE, KEY_FILE)
        httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
        scheme = "https"
    else:
        scheme = "http"

    bar = "─" * 44
    print(f"\n  {bar}")
    print(f"  Godot HTML5 — local test server")
    print(f"  {bar}")
    print(f"  Local  →  {scheme}://localhost:{args.port}")
    print(f"  Mobile →  {scheme}://{ip}:{args.port}")
    print(f"  Serving:  {SERVE_DIR}")
    print(f"  {bar}")

    if args.https:
        print(
            f"\n  PHONE SETUP: open {scheme}://{ip}:{args.port} in your mobile"
            f"\n  browser, accept the certificate warning once, then reload."
        )
    else:
        print(
            "\n  NOTE: SharedArrayBuffer requires HTTPS on mobile browsers."
            "\n  Use --https if the game hangs or shows a black screen on your phone."
        )

    print("\n  Press Ctrl+C to stop.\n")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n  Server stopped.")


if __name__ == "__main__":
    main()

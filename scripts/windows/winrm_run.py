#!/usr/bin/env python3
import argparse
import os
import sys


def _require(value, name):
    if not value:
        print(f"Missing {name}. Set it via flag or env var.", file=sys.stderr)
        sys.exit(2)
    return value


def _decode(data):
    if not data:
        return ""
    if isinstance(data, bytes):
        return data.decode("utf-8", errors="replace")
    return str(data)


def main():
    parser = argparse.ArgumentParser(description="Run a command on Windows over WinRM.")
    parser.add_argument("--host", default=os.environ.get("WINRM_HOST"))
    parser.add_argument("--user", default=os.environ.get("WINRM_USER"))
    parser.add_argument("--password", default=os.environ.get("WINRM_PASS"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("WINRM_PORT", "5985")))
    parser.add_argument("--transport", default=os.environ.get("WINRM_TRANSPORT", "ntlm"))
    parser.add_argument("--ssl", action="store_true")
    parser.add_argument("--ps", action="store_true", help="Run PowerShell instead of cmd")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    host = _require(args.host, "WINRM_HOST/--host")
    user = _require(args.user, "WINRM_USER/--user")
    password = _require(args.password, "WINRM_PASS/--password")

    if not args.command:
        print("Missing command to run.", file=sys.stderr)
        sys.exit(2)

    try:
        import winrm
    except Exception as exc:
        print(f"pywinrm not available: {exc}", file=sys.stderr)
        sys.exit(2)

    scheme = "https" if args.ssl else "http"
    endpoint = f"{scheme}://{host}:{args.port}/wsman"
    kwargs = {}
    if args.ssl:
        kwargs["server_cert_validation"] = "ignore"

    session = winrm.Session(endpoint, auth=(user, password), transport=args.transport, **kwargs)

    cmd = " ".join(args.command).strip()
    if args.ps:
        result = session.run_ps(cmd)
    else:
        result = session.run_cmd(cmd)

    out = _decode(result.std_out)
    err = _decode(result.std_err)
    if out:
        print(out, end="")
    if err:
        print(err, end="", file=sys.stderr)

    sys.exit(result.status_code)


if __name__ == "__main__":
    main()

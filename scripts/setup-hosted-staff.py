#!/usr/bin/env python3
"""Register a dedicated staff account; prepare owner-run role provisioning SQL."""
import argparse
import getpass
import json
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from uuid import UUID


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def api_base(value):
    parts = urlsplit(value)
    if (parts.scheme != "https" or not parts.hostname or parts.username
            or parts.password or parts.query or parts.fragment
            or parts.path.rstrip("/") != "/api/v1"):
        raise ValueError("Use the HTTPS API URL ending in /api/v1, with no credentials or query string.")
    return value.rstrip("/")


def promotion_sql(user_id, role):
    account = str(UUID(user_id))
    if role not in ("admin", "trainer"):
        raise ValueError("Choose admin or trainer.")
    return f"""-- Run in this app's Supabase project SQL Editor as the database owner.
-- Changes only the dedicated account shown by the final SELECT.
BEGIN;
DO $staff_setup$
DECLARE
  target_id uuid := '{account}';
  previous_role text;
BEGIN
  SELECT role INTO previous_role FROM public.users WHERE id=target_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account missing. Check that this is the correct Supabase project.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.memberships WHERE customer_id=target_id) THEN
    RAISE EXCEPTION 'Use a dedicated staff account without customer memberships.';
  END IF;
  IF previous_role <> '{role}' THEN
    UPDATE public.users SET role='{role}' WHERE id=target_id;
    DELETE FROM public.sessions WHERE user_id=target_id;
    INSERT INTO public.staff_audit(id,actor_id,customer_id,action,metadata)
    VALUES(gen_random_uuid(),NULL,NULL,'staff_role_provisioned',
      jsonb_build_object('userId',target_id,'previousRole',previous_role,'role','{role}'));
  END IF;
END;
$staff_setup$;
COMMIT;
SELECT id,email,role FROM public.users WHERE id='{account}';
"""


def post(base, path, body, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(base + path, data=json.dumps(body).encode(), headers=headers, method="POST")
    try:
        with build_opener(NoRedirect()).open(request, timeout=60) as response:
            return json.load(response)
    except HTTPError as error:
        hints = {400: "Check the email, display name and password requirements.",
                 409: "This email already exists. Use a new dedicated staff email, or the existing staff-role CLI for that account.",
                 429: "Too many attempts. Wait before retrying."}
        raise ValueError(f"API returned HTTP {error.code}. " + hints.get(error.code, "Check the API deployment; no role change was made.")) from None
    except (URLError, TimeoutError, json.JSONDecodeError):
        raise ValueError("API request failed. Open the API health endpoint, wait for it to wake and retry. If registration succeeded before the interruption, check the account before registering again.") from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-url", default="https://jbfitness-app.onrender.com/api/v1")
    parser.add_argument("--role", choices=("admin", "trainer"), default="admin")
    args = parser.parse_args()
    base = api_base(args.api_url)
    if not sys.stdin.isatty():
        raise ValueError("Run this command in your terminal so the password can be entered privately.")
    print(f"Registering a dedicated {args.role} account using {base}.")
    email = input("Staff email: ").strip().lower()
    name = input("Display name: ").strip()
    if not email or len(email) > 254 or not name or len(name) > 80:
        raise ValueError("Enter a valid email and a display name of 1–80 characters.")
    password = getpass.getpass("New staff password (12–128 characters; hidden): ")
    if not 12 <= len(password) <= 128:
        raise ValueError("The password must contain 12–128 characters.")
    if password != getpass.getpass("Confirm password (hidden): "):
        raise ValueError("Passwords did not match. No request was sent.")
    result = post(base, "/auth/register", {"email": email, "displayName": name, "password": password})
    sql = promotion_sql(result["user"]["id"], args.role)
    folder = Path(__file__).resolve().parent.parent / "artifacts" / "staff-setup"
    folder.mkdir(parents=True, exist_ok=True)
    output = folder / f"promote-{UUID(result['user']['id'])}.sql"
    output.write_text(sql)
    print(f"Account registered. Its role is not changed yet.\nSQL file: {output}")
    try:
        post(base, "/auth/logout", {}, result["token"])
    except ValueError:
        print("Registration session could not be revoked. The SQL role change revokes existing sessions.")
    print("Open that SQL file, copy its contents into this app's Supabase SQL Editor, and click Run.")
    print(f"Confirm the result shows role={args.role}, then sign in at the dashboard with your new email/password.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError):
        error = sys.exc_info()[1]
        print(str(error) if isinstance(error, ValueError) else "Unexpected API response. Check the registered account before retrying.", file=sys.stderr)
        sys.exit(1)
    except (KeyboardInterrupt, EOFError):
        print("Setup interrupted. Check whether the account was created before retrying.", file=sys.stderr)
        sys.exit(1)

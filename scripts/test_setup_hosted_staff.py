import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

spec = importlib.util.spec_from_file_location("setup_staff", Path(__file__).with_name("setup-hosted-staff.py"))
staff = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staff)


class StaffSetupTests(unittest.TestCase):
    def test_role_sql_is_scoped_and_keeps_provisioning_controls(self):
        account = "ea64ec8d-4e12-4bd0-9a68-0459e6ec3f9f"
        for role in ("admin", "trainer"):
            sql = staff.promotion_sql(account, role)
            self.assertIn(f"target_id uuid := '{account}'", sql)
            self.assertIn("FOR UPDATE", sql)
            self.assertIn("public.memberships WHERE customer_id=target_id", sql)
            self.assertIn("DELETE FROM public.sessions WHERE user_id=target_id", sql)
            self.assertIn("staff_role_provisioned", sql)
        for account, role in (("'; DROP TABLE users;--", "admin"), (account, "admin';--")):
            with self.assertRaises(ValueError):
                staff.promotion_sql(account, role)

    def test_credentials_require_https_and_are_not_forwarded_to_redirects(self):
        for value in ("http://host/api/v1", "https://u:p@host/api/v1", "https://host/api/v1?secret=x"):
            with self.assertRaises(ValueError):
                staff.api_base(value)
        self.assertEqual(staff.api_base("https://host/api/v1/"), "https://host/api/v1")
        self.assertIsNone(staff.NoRedirect().redirect_request(None, None, 302, "", {}, "https://other/"))

    def test_failed_registration_does_not_print_upstream_secrets(self):
        error = HTTPError("https://host/private-secret", 409, "PRIVATE_PASSWORD", {}, None)
        with patch.object(staff, "build_opener") as opener:
            opener.return_value.open.side_effect = error
            with self.assertRaises(ValueError) as caught:
                staff.post("https://host/api/v1", "/auth/register", {"password": "PRIVATE_PASSWORD"})
            self.assertNotIn("PRIVATE_PASSWORD", str(caught.exception))
            self.assertNotIn("private-secret", str(caught.exception))


if __name__ == "__main__":
    unittest.main()

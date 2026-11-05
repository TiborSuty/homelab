import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "transport", Path(__file__).with_name("with-backend-secrets.py")
)
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)


class SecretTransportTests(unittest.TestCase):
    def test_missing_token_is_rejected(self):
        with self.assertRaises(ValueError):
            transport.command_script(["true"], {transport.TOKEN_NAMES[0]: "dummy"})

    def test_shell_metacharacters_are_literal(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / "projects/backend-monorepo").mkdir(parents=True)
            marker = home / "must-not-exist"
            token = "dummy' ; $(touch " + str(marker) + ")\nquoted"
            argument = "arg' $(touch " + str(marker) + ")"
            environment = dict.fromkeys(transport.TOKEN_NAMES, token)
            command = [sys.executable, "-c",
                       "import os,sys; assert os.environ[sys.argv[1]] == sys.argv[2]; "
                       "assert sys.argv[3] == sys.argv[4]",
                       transport.TOKEN_NAMES[0], token, argument, argument]
            result = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", "-s"],
                input=transport.command_script(command, environment), text=True,
                env={"HOME": directory, "PATH": "/usr/bin:/bin"}, capture_output=True,
            )
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout + result.stderr, "")
            self.assertFalse(marker.exists())

    def test_tokens_use_stdin_and_exit_status_is_preserved(self):
        environment = {name: "dummy-" + name for name in transport.TOKEN_NAMES}
        environment["BW_SESSION"] = "dummy-vault-session"
        with patch.dict(os.environ, environment, clear=True), \
                patch.object(sys, "argv", ["transport", "false"]), \
                patch.object(transport.subprocess, "run") as run:
            run.return_value.returncode = 37
            self.assertEqual(transport.main(), 37)
            args, kwargs = run.call_args
            for name in (*transport.TOKEN_NAMES, "BW_SESSION"):
                self.assertNotIn(name, kwargs["env"])
                self.assertNotIn(environment[name], str(args))
            for name in transport.TOKEN_NAMES:
                self.assertIn(environment[name].encode(), kwargs["input"])
            self.assertNotIn(environment["BW_SESSION"].encode(), kwargs["input"])


if __name__ == "__main__":
    unittest.main()

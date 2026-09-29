#!/usr/bin/env python3
"""Feed hook scripts JSON on stdin and assert the permission they return.

These tests do not run terraform, kubectl, helm, or git.
"""

import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOKS = ROOT / ".cursor" / "hooks"
HOOKS_JSON = ROOT / ".cursor" / "hooks.json"


def run_hook(script: str, payload: dict) -> tuple[int, dict]:
    completed = subprocess.run(
        ["bash", str(HOOKS / script)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=False,
    )
    stdout = completed.stdout.strip()
    if not stdout:
        raise AssertionError(
            f"{script} produced no JSON (exit {completed.returncode}): {completed.stderr}"
        )
    return completed.returncode, json.loads(stdout)


class HookWiringTest(unittest.TestCase):
    def test_hooks_json_wires_every_gate(self) -> None:
        config = json.loads(HOOKS_JSON.read_text())
        hooks = config["hooks"]

        shell = hooks["beforeShellExecution"]
        shell_commands = [entry["command"] for entry in shell]
        self.assertIn("bash .cursor/hooks/block-destroy.sh", shell_commands)
        self.assertIn("bash .cursor/hooks/block-dangerous-rm.sh", shell_commands)
        self.assertIn("bash .cursor/hooks/warn-apply-without-plan.sh", shell_commands)
        self.assertIn("bash .cursor/hooks/block-secret-commit.sh", shell_commands)
        self.assertIn("bash .cursor/hooks/block-hook-edits.sh", shell_commands)
        self.assertIn("bash .cursor/hooks/ask-cluster-mutation.sh", shell_commands)

        by_command = {entry["command"]: entry for entry in shell}
        for command in (
            "bash .cursor/hooks/block-destroy.sh",
            "bash .cursor/hooks/block-dangerous-rm.sh",
            "bash .cursor/hooks/block-secret-commit.sh",
            "bash .cursor/hooks/block-hook-edits.sh",
            "bash .cursor/hooks/ask-cluster-mutation.sh",
        ):
            self.assertTrue(by_command[command].get("failClosed"), command)

        mcp = hooks["beforeMCPExecution"]
        self.assertEqual(mcp[0]["command"], "bash .cursor/hooks/block-mcp-destroy.sh")
        self.assertTrue(mcp[0].get("failClosed"))

        pre = hooks["preToolUse"]
        self.assertEqual(pre[0]["command"], "bash .cursor/hooks/block-hook-edits.sh")
        self.assertTrue(pre[0].get("failClosed"))

        read = hooks["beforeReadFile"]
        self.assertEqual(read[0]["command"], "bash .cursor/hooks/block-secret-read.sh")
        self.assertTrue(read[0].get("failClosed"))

        after = hooks["afterFileEdit"]
        self.assertEqual(after[0]["command"], "bash .cursor/hooks/suggest-validate.sh")


class BlockDestroyTest(unittest.TestCase):
    def test_terraform_destroy_is_denied(self) -> None:
        code, body = run_hook("block-destroy.sh", {"command": "terraform destroy"})
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_apply_destroy_is_denied(self) -> None:
        code, body = run_hook(
            "block-destroy.sh", {"command": "terraform apply -destroy plan.out"}
        )
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_prod_namespace_delete_is_denied(self) -> None:
        code, body = run_hook(
            "block-destroy.sh",
            {"command": "kubectl delete namespace petclinic-prod"},
        )
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_read_only_kubectl_is_allowed(self) -> None:
        code, body = run_hook("block-destroy.sh", {"command": "kubectl get pods"})
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "allow")


class BlockSecretCommitTest(unittest.TestCase):
    def test_tfvars_add_is_denied(self) -> None:
        code, body = run_hook(
            "block-secret-commit.sh", {"command": "git add terraform.tfvars"}
        )
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_pem_add_is_denied(self) -> None:
        code, body = run_hook("block-secret-commit.sh", {"command": "git add cluster.pem"})
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_git_add_all_is_denied(self) -> None:
        code, body = run_hook("block-secret-commit.sh", {"command": "git add ."})
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_named_tf_file_is_allowed(self) -> None:
        code, body = run_hook(
            "block-secret-commit.sh",
            {"command": "git add terraform/modules/vpc/main.tf"},
        )
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "allow")

    def test_tfvars_example_is_allowed(self) -> None:
        code, body = run_hook(
            "block-secret-commit.sh",
            {"command": "git add terraform.tfvars.example"},
        )
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "allow")


class BlockDangerousRmTest(unittest.TestCase):
    def test_rm_rf_terraform_is_denied(self) -> None:
        code, body = run_hook("block-dangerous-rm.sh", {"command": "rm -rf terraform/"})
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_rm_of_one_file_is_allowed(self) -> None:
        code, body = run_hook("block-dangerous-rm.sh", {"command": "rm notes.tmp"})
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "allow")


class BlockMcpDestroyTest(unittest.TestCase):
    def test_terraform_mcp_destroy_is_denied(self) -> None:
        code, body = run_hook(
            "block-mcp-destroy.sh",
            {
                "tool_name": "apply_run",
                "mcp_server_name": "terraform",
                "tool_input": {"command": "destroy"},
            },
        )
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_terraform_mcp_plan_is_allowed(self) -> None:
        code, body = run_hook(
            "block-mcp-destroy.sh",
            {
                "tool_name": "create_run",
                "mcp_server_name": "terraform",
                "tool_input": {"command": "plan"},
            },
        )
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "allow")


class AskClusterMutationTest(unittest.TestCase):
    def test_kubectl_apply_asks(self) -> None:
        code, body = run_hook("ask-cluster-mutation.sh", {"command": "kubectl apply -f app.yaml"})
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "ask")

    def test_kubectl_delete_asks(self) -> None:
        code, body = run_hook(
            "ask-cluster-mutation.sh",
            {"command": "kubectl delete deployment api-gateway -n petclinic-dev"},
        )
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "ask")

    def test_prod_delete_stays_denied(self) -> None:
        code, body = run_hook(
            "ask-cluster-mutation.sh",
            {"command": "kubectl delete deployment api-gateway -n petclinic-prod"},
        )
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_dry_run_is_allowed(self) -> None:
        code, body = run_hook(
            "ask-cluster-mutation.sh",
            {"command": "kubectl apply --dry-run=client -f app.yaml"},
        )
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "allow")

    def test_helm_install_and_upgrade_ask(self) -> None:
        for command in (
            "helm install petclinic ./helm/petclinic-service",
            "helm upgrade petclinic ./helm/petclinic-service",
        ):
            with self.subTest(command=command):
                code, body = run_hook("ask-cluster-mutation.sh", {"command": command})
                self.assertEqual(code, 0)
                self.assertEqual(body["permission"], "ask")

    def test_helm_template_is_allowed(self) -> None:
        code, body = run_hook(
            "ask-cluster-mutation.sh",
            {"command": "helm template petclinic ./helm/petclinic-service"},
        )
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "allow")

    def test_argocd_sync_asks(self) -> None:
        code, body = run_hook(
            "ask-cluster-mutation.sh", {"command": "argocd app sync api-gateway-dev"}
        )
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "ask")

    def test_git_push_asks_and_commit_is_allowed(self) -> None:
        code, body = run_hook("ask-cluster-mutation.sh", {"command": "git push origin HEAD"})
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "ask")

        code, body = run_hook(
            "ask-cluster-mutation.sh", {"command": "git commit -m 'record the hook'"}
        )
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "allow")

    def test_terraform_destroy_stays_denied(self) -> None:
        code, body = run_hook("ask-cluster-mutation.sh", {"command": "terraform destroy"})
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_kubectl_get_is_allowed(self) -> None:
        code, body = run_hook("ask-cluster-mutation.sh", {"command": "kubectl get pods"})
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "allow")


class BlockHookEditsTest(unittest.TestCase):
    def test_write_to_hook_script_is_denied(self) -> None:
        code, body = run_hook(
            "block-hook-edits.sh",
            {
                "tool_name": "Write",
                "tool_input": {"path": "/repo/.cursor/hooks/block-destroy.sh"},
            },
        )
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_strreplace_on_hooks_json_is_denied(self) -> None:
        code, body = run_hook(
            "block-hook-edits.sh",
            {
                "tool_name": "StrReplace",
                "tool_input": {"file_path": "/repo/.cursor/hooks.json"},
            },
        )
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_write_to_terraform_is_allowed(self) -> None:
        code, body = run_hook(
            "block-hook-edits.sh",
            {
                "tool_name": "Write",
                "tool_input": {"path": "/repo/terraform/modules/eks/main.tf"},
            },
        )
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "allow")

    def test_shell_redirect_onto_hooks_json_is_denied(self) -> None:
        code, body = run_hook(
            "block-hook-edits.sh",
            {"command": "echo '{}' > .cursor/hooks.json"},
        )
        self.assertEqual(code, 2)
        self.assertEqual(body["permission"], "deny")

    def test_executing_a_hook_script_is_allowed(self) -> None:
        code, body = run_hook(
            "block-hook-edits.sh",
            {"command": "bash .cursor/hooks/block-destroy.sh"},
        )
        self.assertEqual(code, 0)
        self.assertEqual(body["permission"], "allow")


class BlockSecretReadTest(unittest.TestCase):
    def test_secret_names_are_denied(self) -> None:
        samples = (
            "/repo/.env",
            "/repo/terraform/terraform.tfvars",
            "/repo/certs/cluster.pem",
            "/repo/certs/cluster.key",
            "/repo/credentials.json",
        )
        for path in samples:
            with self.subTest(path=path):
                code, body = run_hook("block-secret-read.sh", {"file_path": path})
                self.assertEqual(code, 2)
                self.assertEqual(body["permission"], "deny")

    def test_example_and_source_are_allowed(self) -> None:
        for path in (
            "/repo/terraform/terraform.tfvars.example",
            "/repo/terraform/modules/eks/main.tf",
        ):
            with self.subTest(path=path):
                code, body = run_hook("block-secret-read.sh", {"file_path": path})
                self.assertEqual(code, 0)
                self.assertEqual(body["permission"], "allow")


if __name__ == "__main__":
    unittest.main()

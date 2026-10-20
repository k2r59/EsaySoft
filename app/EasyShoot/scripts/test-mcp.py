#!/usr/bin/env python3
"""Integration tests against the packaged stdio process; Python standard library only."""
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parent.parent
BINARY = Path(os.environ.get("EASYSHOOT_TEST_BINARY", str(PROJECT / "dist/EasyShoot.app/Contents/MacOS/EasyShoot")))

class Client:
    def __init__(self, *args):
        self.process = subprocess.Popen([str(BINARY), "--mcp", *args], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        self.counter = 0
    def raw(self, line):
        self.process.stdin.write(line + "\n")
        self.process.stdin.flush()
        if not select.select([self.process.stdout], [], [], 15)[0]:
            raise TimeoutError("EasyShoot did not answer within 15 seconds")
        answer = self.process.stdout.readline()
        if not answer:
            raise RuntimeError("MCP process closed unexpectedly")
        return json.loads(answer)
    def request(self, method, params=None):
        self.counter += 1
        return self.raw(json.dumps({"jsonrpc": "2.0", "id": self.counter, "method": method, "params": params or {}}))
    def initialize(self):
        result = self.request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "EasyShoot-integration", "version": "1"}})
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        self.process.stdin.flush()
        return result
    def tool(self, name, arguments=None):
        return self.request("tools/call", {"name": name, "arguments": arguments or {}})
    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=5)
        self.process.stdout.close()

class MCPIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run([str(BINARY), "--self-test"], check=True, stdout=subprocess.DEVNULL)
        cls.directory = tempfile.TemporaryDirectory(prefix="EasyShoot-mcp-test-")
        fixture = Path(tempfile.gettempdir()) / "EasyShoot-tests/ocr-source.png"
        cls.image = Path(cls.directory.name) / "source.png"
        shutil.copyfile(fixture, cls.image)
        (Path(cls.directory.name) / "escape").symlink_to("/etc/hosts")
    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()
    def setUp(self):
        self.client = Client("--read-root", self.directory.name)
    def tearDown(self):
        self.client.close()
    def test_handshake_and_discovery(self):
        self.assertEqual(self.client.request("tools/list")["error"]["code"], -32002)
        result = self.client.initialize()["result"]
        self.assertEqual(result["protocolVersion"], "2025-11-25")
        tools = self.client.request("tools/list")["result"]["tools"]
        self.assertEqual(len(tools), 6)
        self.assertIn("extract_text", [tool["name"] for tool in tools])
        self.assertEqual(self.client.request("ping")["result"], {})
    def test_local_ocr(self):
        self.client.initialize()
        result = self.client.tool("extract_text", {"path": str(self.image)})["result"]
        self.assertFalse(result["isError"])
        self.assertIn("easyshoot", result["structuredContent"]["text"].lower())
    def test_path_traversal_and_symlink_escape(self):
        self.client.initialize()
        for path in ["/etc/hosts", str(Path(self.directory.name)/"escape"), str(Path(self.directory.name)/"../outside.png")]:
            result = self.client.tool("extract_text", {"path": path})["result"]
            self.assertTrue(result["isError"])
            self.assertIn("outside the granted", result["content"][0]["text"])
    def test_bad_arguments_and_errors(self):
        self.assertEqual(self.client.raw("not json")["error"]["code"], -32700)
        self.client.initialize()
        self.assertEqual(self.client.tool("does_not_exist")["error"]["code"], -32602)
        self.assertEqual(self.client.request("unknown/method")["error"]["code"], -32601)
        for arguments in [{"limit": -1}, {"limit": True}, {"limit": 1.2}, {"unexpected": 1}]:
            self.assertTrue(self.client.tool("list_captures", arguments)["result"]["isError"])
    def test_status_and_history(self):
        self.client.initialize()
        status = self.client.tool("get_status")["result"]["structuredContent"]
        self.assertFalse(status["networkListener"])
        self.assertEqual(status["transport"], "stdio")
        history = self.client.tool("list_captures", {"limit": 1})["result"]["structuredContent"]
        self.assertLessEqual(len(history["captures"]), 1)
    def test_no_implicit_file_access(self):
        plain = Client()
        try:
            plain.initialize()
            self.assertTrue(plain.tool("extract_text", {"path": str(self.image)})["result"]["isError"])
        finally:
            plain.close()

if __name__ == "__main__":
    unittest.main(verbosity=2)

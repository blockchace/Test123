import contextlib
import io
import json
import os
import pathlib
import runpy
import tempfile
import unittest
from unittest.mock import Mock, patch

SCRIPT = pathlib.Path(__file__).parents[1] / "scripts/profile-memory-macos.py"


class MemoryProfileTests(unittest.TestCase):
    def testReportUsesSampledRSSAndStopsOnlyItsChild(self):
        child = Mock()
        child.pid = 12345
        child.poll.return_value = None
        initial = pathlib.Path.cwd()
        with tempfile.TemporaryDirectory() as folder:
            os.chdir(folder)
            try:
                with patch("sys.platform", "darwin"), patch("sys.argv", [str(SCRIPT), "--seconds", "3"]), patch("subprocess.Popen", return_value=child), patch("subprocess.check_output", side_effect=["65536", "98304", "131072"]) as rss, patch("time.sleep"), contextlib.redirect_stdout(io.StringIO()):
                    with self.assertRaises(SystemExit) as result:
                        runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertEqual(result.exception.code, 0)
                report = json.loads(pathlib.Path("dist/memory-report.json").read_text())
                self.assertEqual(report["median_rss_mib"], 96)
                self.assertEqual(report["peak_rss_mib"], 128)
                self.assertEqual(report["samples"], 3)
                self.assertTrue(report["passed"])
                child.terminate.assert_called_once()
                for call in rss.call_args_list:
                    self.assertEqual(call.args[0][-1], "12345")
            finally:
                os.chdir(initial)


if __name__ == "__main__":
    unittest.main()

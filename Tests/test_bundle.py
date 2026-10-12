import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("bundle", pathlib.Path(__file__).parents[1] / "scripts/bundle-ffmpeg.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BundleTests(unittest.TestCase):
    def test_loader_relative_dependency(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            self.assertEqual(module.resolve("@loader_path/lib.dylib", root / "bin/ffmpeg", root / "bin/ffmpeg"), root / "bin/lib.dylib")

    def test_rpath_missing_fails_instead_of_shipping_broken_binary(self):
        with patch.object(module, "rpaths", return_value=[]):
            with self.assertRaisesRegex(RuntimeError, "No se pudo resolver"):
                module.resolve("@rpath/missing.dylib", pathlib.Path("/tmp/ffmpeg"), pathlib.Path("/tmp/ffmpeg"))

    def test_transitive_dependencies_rewritten_and_cycle_stops(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            executable = root / "ffmpeg"
            a, b = root / "liba.dylib", root / "libb.dylib"
            for p in (executable, a, b):
                p.write_bytes(b"test-binary")
            deps = {executable: [str(a), "/usr/lib/libSystem.B.dylib"], a: [str(a), str(b)], b: [str(b), str(a)]}
            commands = []

            def fake_run(*args):
                commands.append(args)
                return "mock metadata"

            app = root / "Aire Audio.app"
            with patch.object(module, "dependencies", side_effect=lambda p: deps[p]), patch.object(module, "run", side_effect=fake_run), patch.object(module.subprocess, "run"):
                module.bundle(executable, app)
            self.assertEqual(sorted(p.name for p in (app / "Contents/Frameworks").iterdir()), ["liba.dylib", "libb.dylib"])
            self.assertTrue(any("@executable_path/../../Frameworks/liba.dylib" in command for command in commands))
            self.assertTrue(any("@loader_path/libb.dylib" in command for command in commands))


if __name__ == "__main__":
    unittest.main()

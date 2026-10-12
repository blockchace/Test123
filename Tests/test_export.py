import json
import math
import pathlib
import shutil
import struct
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "Se requieren FFmpeg y ffprobe")
class ExportTests(unittest.TestCase):
    def test_combined_export_keeps_both_sources_and_longest_duration(self):
        with tempfile.TemporaryDirectory(prefix="aire audio ") as folder:
            root = pathlib.Path(folder)
            tracks = [root / "sistema.caf", root / "microfono.caf"]
            for path, frequency, duration in zip(tracks, [440, 880], [2, 1]):
                subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", f"sine=frequency={frequency}:duration={duration}:sample_rate=48000", "-codec:a", "pcm_f32le", str(path)], check=True)
            output = root / "audio combinado.mp3"
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", str(tracks[0]), "-i", str(tracks[1]), "-filter_complex", "[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=0:normalize=1[a]", "-map", "[a]", "-vn", "-codec:a", "libmp3lame", "-b:a", "192k", str(output)], check=True)
            info = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", str(output)]))
            self.assertEqual(info["streams"][0]["codec_name"], "mp3")
            self.assertAlmostEqual(float(info["format"]["duration"]), 2, delta=0.1)
            pcm = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(output), "-t", "0.5", "-ar", "48000", "-ac", "1", "-f", "s16le", "-"])
            samples = struct.unpack("<" + "h" * (len(pcm) // 2), pcm)

            def amplitude(freq):
                real = sum(v * math.cos(2 * math.pi * freq * i / 48000) for i, v in enumerate(samples))
                imaginary = sum(v * math.sin(2 * math.pi * freq * i / 48000) for i, v in enumerate(samples))
                return math.hypot(real, imaginary) / len(samples)

            self.assertGreater(amplitude(440), 100)
            self.assertGreater(amplitude(880), 100)
            self.assertLess(amplitude(1500), amplitude(440) / 10)


if __name__ == "__main__":
    unittest.main()

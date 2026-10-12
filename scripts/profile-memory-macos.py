"""Measure idle-window RSS on a Mac; launch and stop only our own app process."""
import argparse
import json
import pathlib
import statistics
import subprocess
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument("--app", default="dist/ChaceRecordings.app")
parser.add_argument("--seconds", type=int, default=15)
parser.add_argument("--max-idle-mib", type=float, default=256)
args = parser.parse_args()
if sys.platform != "darwin":
    raise SystemExit("La medición real de la ventana requiere macOS.")
if not 3 <= args.seconds <= 60:
    raise SystemExit("Usa entre 3 y 60 segundos de muestreo.")
binary = pathlib.Path(args.app).resolve() / "Contents/MacOS/ChaceRecordings"
process = subprocess.Popen([str(binary)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
samples = []
error = None
try:
    time.sleep(2)
    for _ in range(args.seconds):
        if process.poll() is not None:
            raise RuntimeError("La app se cerró antes de completar la medición.")
        rss = subprocess.check_output(["ps", "-o", "rss=", "-p", str(process.pid)], text=True)
        samples.append(int(rss.strip()) / 1024)
        time.sleep(1)
except Exception as exception:
    error = str(exception)
finally:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
report = {
    "mode": "idle-window", "samples": len(samples),
    "median_rss_mib": round(statistics.median(samples), 1) if samples else None,
    "peak_rss_mib": round(max(samples), 1) if samples else None,
    "budget_mib": args.max_idle_mib,
    "passed": error is None and bool(samples) and max(samples) <= args.max_idle_mib,
    "error": error,
    "limitation": "RSS del proceso; no incluye toda la memoria GPU/WindowServer ni mide captura activa."
}
destination = pathlib.Path("dist/memory-report.json")
destination.parent.mkdir(exist_ok=True)
destination.write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
raise SystemExit(0 if report["passed"] else 1)

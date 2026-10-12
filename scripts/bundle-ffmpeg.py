"""Bundle the local macOS FFmpeg with its non-system dylibs; no downloads."""
import pathlib
import shutil
import subprocess
import sys


def run(*args):
    return subprocess.check_output(args, text=True)


def dependencies(binary):
    return [line.strip().split(" (", 1)[0] for line in run("otool", "-L", str(binary)).splitlines()[1:]]


def rpaths(binary):
    lines = run("otool", "-l", str(binary)).splitlines()
    result = []
    for index, line in enumerate(lines):
        if line.strip() == "cmd LC_RPATH":
            result.append(lines[index + 2].strip().split("path ", 1)[1].split(" (offset", 1)[0])
    return result


def resolve(dep, source, executable):
    if dep.startswith("@loader_path/"):
        return (source.parent / dep[len("@loader_path/"):]).resolve()
    if dep.startswith("@executable_path/"):
        return (executable.parent / dep[len("@executable_path/"):]).resolve()
    if dep.startswith("@rpath/"):
        for root in rpaths(source) + rpaths(executable):
            root = root.replace("@loader_path", str(source.parent)).replace("@executable_path", str(executable.parent))
            candidate = pathlib.Path(root) / dep[len("@rpath/"):]
            if candidate.is_file():
                return candidate.resolve()
        raise RuntimeError(f"No se pudo resolver {dep} desde {source}")
    return pathlib.Path(dep).resolve()


def bundle(executable, app):
    executable = executable.resolve()
    frameworks = app / "Contents/Frameworks"
    destination = app / "Contents/Resources/bin/ffmpeg"
    frameworks.mkdir(parents=True, exist_ok=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    copied = {}
    names = {}

    def visit(source, target, is_executable=False):
        shutil.copy2(source, target)
        target.chmod(0o755)
        # Remove the old signature before rewriting load commands.
        subprocess.run(["codesign", "--remove-signature", str(target)], check=False, capture_output=True)
        if not is_executable:
            run("install_name_tool", "-id", "@rpath/" + target.name, str(target))
        for dep in dependencies(source):
            if dep.startswith(("/System/Library/", "/usr/lib/")):
                continue
            path = resolve(dep, source, executable)
            if path == source:  # dylib's own LC_ID_DYLIB
                continue
            if not path.is_file():
                raise RuntimeError(f"Biblioteca ausente: {path}")
            if path not in copied:
                if path.name in names and names[path.name] != path:
                    raise RuntimeError(f"Dos bibliotecas distintas tienen el nombre {path.name}")
                names[path.name] = path
                copied[path] = frameworks / path.name
                visit(path, copied[path])
            prefix = "@executable_path/../../Frameworks/" if is_executable else "@loader_path/"
            run("install_name_tool", "-change", dep, prefix + copied[path].name, str(target))

    visit(executable, destination, True)
    licenses = app / "Contents/Resources/ThirdParty"
    licenses.mkdir(parents=True, exist_ok=True)
    (licenses / "FFmpeg-build.txt").write_text(run(str(executable), "-version") + "\n" + run(str(executable), "-L"))
    print(f"FFmpeg empaquetado con {len(copied)} bibliotecas. Arquitectura: {run('uname', '-m').strip()}")


if __name__ == "__main__":
    if sys.platform != "darwin":
        raise SystemExit("Este empaquetado requiere macOS.")
    bundle(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))

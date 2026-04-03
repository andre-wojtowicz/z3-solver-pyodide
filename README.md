# z3-solver-pyodide

Pre-built [Z3 Solver](https://github.com/Z3Prover/z3) Python wheel for [Pyodide](https://pyodide.org/).

## Why?

Z3's official PyPI releases don't include `pyodide_2025_0_wasm32` wheels. This repo builds them so you can use Z3 in the browser via Pyodide.

## Download

Grab the `.whl` from the [Releases](../../releases) page.

## Usage in Pyodide

```python
import micropip

# Install from URL (replace with actual release URL)
await micropip.install(
    "https://github.com/andre-wojtowicz/z3-solver-pyodide/releases/download/z3-4.13.4.0-pyodide-0.29.3/z3_solver-4.13.4.0-py3-none-pyodide_2025_0_wasm32.whl"
)

import z3
s = z3.Solver()
x = z3.Int('x')
s.add(x > 0, x < 10)
print(s.check())  # sat
print(s.model())  # [x = 1]
```

## Build locally

```bash
docker build -t z3-pyodide .
mkdir -p output
docker run --rm -v $(pwd)/output:/output z3-pyodide
ls output/*.whl
```

## Build specs

| Component   | Version         |
|-------------|-----------------|
| Z3 Solver   | 4.13.4.0        |
| Pyodide     | 0.29.3          |
| Python      | 3.13.2          |
| Emscripten  | 4.0.9           |
| ABI tag     | `pyodide_2025_0_wasm32` |

## How it works

The `Dockerfile` does the following:

1. Starts from Debian Trixie (Python 3.13)
2. Installs `pyodide-build` 0.29.x and Emscripten 4.0.9
3. Downloads the Z3 source tarball from GitHub releases
4. Patches Z3's build files to replace legacy `-fexceptions` with `-fwasm-exceptions` (required by Pyodide 0.29+ ABI)
5. Runs `pyodide build --exports whole_archive`

The GitHub Actions workflow automates this and publishes the wheel as a GitHub Release.

## Updating versions

Trigger the workflow manually via **Actions → Build z3-solver Pyodide wheel → Run workflow** and provide the desired Z3 and Pyodide versions. Note that changing the Pyodide version may require updating the Dockerfile (Python version, Emscripten flags, etc.).

## License

Z3 is licensed under the [MIT License](https://github.com/Z3Prover/z3/blob/master/LICENSE.txt). This repo only contains build tooling.

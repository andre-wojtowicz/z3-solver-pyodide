# =============================================================================
# Dockerfile: Build z3-solver 4.16.0.0 wheel for Pyodide 0.29.3
#
# Pyodide 0.29.3 specs:
#   - Python 3.13.2
#   - Emscripten 4.0.9
#   - ABI: pyodide_2025_0_wasm32
#   - Exception handling: -fwasm-exceptions (NOT -fexceptions)
#
# Usage:
#   docker build -t z3-pyodide .
#   docker run --rm -v $(pwd)/output:/output z3-pyodide
#
# Result:
#   output/z3_solver-4.16.0.0-py3-none-pyodide_2025_0_wasm32.whl
# =============================================================================

FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# ── 1. System dependencies ───────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-dev \
        python3-venv \
        python3-pip \
        build-essential \
        cmake \
        git \
        curl \
        ca-certificates \
        xz-utils \
        nodejs \
        npm \
    && rm -rf /var/lib/apt/lists/*

# ── 2. Verify host Python is 3.13 ───────────────────────────────────────────
RUN python3 --version | grep -q "3.13" || \
    (echo "ERROR: Host Python must be 3.13 for Pyodide 0.29.3" && exit 1)

# ── 3. Python venv + pyodide-build for 0.29.3 ───────────────────────────────
RUN python3 -m venv /opt/pyodide-env
ENV PATH="/opt/pyodide-env/bin:${PATH}"

# Pin wheel<0.45: in wheel 0.45+ the wheel.cli package was made private,
# but auditwheel_emscripten 0.0.16 imports wheel.cli.pack.
# Install wheel first, then pyodide-build with --no-deps for wheel to
# prevent pip from upgrading it.
RUN pip install --no-cache-dir "wheel>=0.40,<0.45" && \
    pip install --no-cache-dir "pyodide-build>=0.29.2,<0.30" pyodide-cli && \
    pip install --no-cache-dir "wheel>=0.40,<0.45" && \
    python3 -c "from wheel.cli.pack import pack as pack_wheel; print('wheel.cli OK')"

# Verify pyodide-build targets the correct Emscripten version
RUN EMVER=$(pyodide config get emscripten_version) && \
    echo "pyodide-build expects Emscripten: ${EMVER}" && \
    echo "${EMVER}" | grep -q "4.0" || \
    (echo "ERROR: Expected Emscripten 4.0.x, got ${EMVER}" && exit 1)

# ── 4. Install Emscripten SDK (version matched to pyodide-build) ────────────
RUN git clone --depth 1 https://github.com/emscripten-core/emsdk.git /opt/emsdk

RUN EMVER=$(pyodide config get emscripten_version) && \
    cd /opt/emsdk && \
    ./emsdk install "${EMVER}" && \
    ./emsdk activate "${EMVER}"

ENV EMSDK="/opt/emsdk"
ENV PATH="/opt/emsdk:/opt/emsdk/upstream/emscripten:${PATH}"

# Source emsdk_env.sh equivalents
RUN cd /opt/emsdk && . ./emsdk_env.sh && \
    echo "export EMSDK=${EMSDK}" >> /etc/profile.d/emsdk.sh && \
    echo "export EM_CONFIG=${EM_CONFIG}" >> /etc/profile.d/emsdk.sh && \
    echo "export PATH=${PATH}" >> /etc/profile.d/emsdk.sh && \
    emcc --version

# ── 5. Download z3-solver 4.16.0.0 source tarball ───────────────────────────
WORKDIR /build

RUN curl -fSL \
    "https://github.com/Z3Prover/z3/releases/download/z3-4.16.0/z3_solver-4.16.0.0.tar.gz" \
    -o z3_solver.tar.gz && \
    tar xzf z3_solver.tar.gz && \
    rm z3_solver.tar.gz

# ── 6. Build the Pyodide wheel ──────────────────────────────────────────────
#
# Pyodide 0.29+ ABI break: use -fwasm-exceptions instead of -fexceptions.
# Z3's setup.py / CMakeLists internally sets -fexceptions and
# -s DISABLE_EXCEPTION_CATCHING=0 (Emscripten legacy exception mode).
# These are incompatible with -fwasm-exceptions, so we patch them out.
#
WORKDIR /build/z3_solver-4.16.0.0

# Patch setup.py: replace legacy Emscripten exception flags with wasm EH
RUN sed -i \
    -e 's/-s DISABLE_EXCEPTION_CATCHING=0//g' \
    -e 's/-s DISABLE_EXCEPTION_CATCHING\s*=\s*0//g' \
    -e 's/-fexceptions/-fwasm-exceptions/g' \
    setup.py

# Also patch any CMakeLists.txt that may set these flags
RUN find . -name 'CMakeLists.txt' -exec sed -i \
    -e 's/-s DISABLE_EXCEPTION_CATCHING=0//g' \
    -e 's/-sDISABLE_EXCEPTION_CATCHING=0//g' \
    -e 's/DISABLE_EXCEPTION_CATCHING=0//g' \
    -e 's/-fexceptions/-fwasm-exceptions/g' \
    {} +

RUN cd /opt/emsdk && . ./emsdk_env.sh && cd /build/z3_solver-4.16.0.0 && \
    CFLAGS="-fwasm-exceptions -g2" \
    CXXFLAGS="-fwasm-exceptions" \
    LDFLAGS="-fwasm-exceptions -sSUPPORT_LONGJMP=wasm -sWASM_BIGINT" \
    pyodide build --exports whole_archive

# Verify the wheel was built with correct platform tag
RUN ls dist/*.whl && \
    ls dist/*.whl | grep -q "pyodide_2025_0_wasm32" || \
    (echo "WARNING: Wheel platform tag does not match pyodide_2025_0_wasm32" && \
     echo "Built wheel:" && ls dist/*.whl)

# ── 7. Copy wheel to /output on container run ───────────────────────────────
CMD cp /build/z3_solver-4.16.0.0/dist/*.whl /output/ && \
    echo "=== Done ===" && \
    echo "Wheel copied to /output/:" && \
    ls -lh /output/*.whl

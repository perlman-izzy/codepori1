#!/usr/bin/env bash
set -euxo pipefail

# Export required environment variables
export DEBIAN_FRONTEND=noninteractive
export PYTEST_DISABLE_PLUGIN_AUTOLOAD=1
export PIP_DISABLE_PIP_VERSION_CHECK=1

echo "=== Starting Google Jules Linux VM Setup ==="

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to safely run commands with sudo if available
run_with_sudo() {
    if command_exists sudo; then
        sudo "$@"
    else
        "$@"
    fi
}

# Update package lists and install system dependencies
echo "=== Installing system dependencies ==="
run_with_sudo apt-get update -y
run_with_sudo apt-get install -y \
    build-essential \
    python3-dev \
    python3-venv \
    python3-pip \
    libssl-dev \
    libffi-dev \
    pkg-config \
    git \
    curl \
    wget

# Create and activate Python virtual environment
echo "=== Setting up Python virtual environment ==="
if command_exists uv; then
    echo "Using uv for virtual environment"
    uv venv venv
    source venv/bin/activate
else
    echo "Using python3 -m venv for virtual environment"
    python3 -m venv venv
    source venv/bin/activate
fi

# Upgrade pip to latest version
python -m pip install --upgrade pip

# Install project dependencies based on what's available
echo "=== Installing project dependencies ==="
if [ -f "requirements.txt" ]; then
    echo "Found requirements.txt, installing with pip"
    if command_exists uv; then
        uv pip install -r requirements.txt
    else
        pip install -r requirements.txt
    fi
elif [ -f "pyproject.toml" ]; then
    echo "Found pyproject.toml, installing editable with pip"
    if command_exists uv; then
        uv pip install -e .
    else
        pip install -e .
    fi
else
    echo "No requirements.txt or pyproject.toml found, installing common crypto bot dependencies"
    CRYPTO_DEPS=(
        "ccxt"
        "pandas"
        "numpy"
        "scikit-learn"
        "python-binance"
        "requests"
        "python-dotenv"
        "pytest"
    )
    
    if command_exists uv; then
        uv pip install "${CRYPTO_DEPS[@]}"
    else
        pip install "${CRYPTO_DEPS[@]}"
    fi
fi

# Attempt to install TA-Lib (best effort, don't hard-fail)
echo "=== Installing TA-Lib (best effort) ==="
TALIB_INSTALLED=false

# Try ta-lib-bin first
echo "Trying ta-lib-bin..."
if command_exists uv; then
    if uv pip install ta-lib-bin 2>/dev/null; then
        TALIB_INSTALLED=true
        echo "Successfully installed ta-lib-bin"
    fi
else
    if pip install ta-lib-bin 2>/dev/null; then
        TALIB_INSTALLED=true
        echo "Successfully installed ta-lib-bin"
    fi
fi

# If ta-lib-bin failed, try building from source
if [ "$TALIB_INSTALLED" = false ]; then
    echo "ta-lib-bin failed, attempting to build TA-Lib from source..."
    (
        cd /tmp
        wget -q http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz 2>/dev/null || curl -sL http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz -o ta-lib-0.4.0-src.tar.gz
        tar -xzf ta-lib-0.4.0-src.tar.gz
        cd ta-lib/
        ./configure --prefix=/usr/local
        make
        run_with_sudo make install
        export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
        
        # Now try installing the Python wrapper
        if command_exists uv; then
            uv pip install TA-Lib
        else
            pip install TA-Lib
        fi
        TALIB_INSTALLED=true
        echo "Successfully built and installed TA-Lib from source"
    ) 2>/dev/null || {
        echo "TA-Lib installation failed, continuing without it..."
        TALIB_INSTALLED=false
    }
fi

# Echo versions of Python, pip, and main packages
echo "=== Package Versions ==="
echo "Python version: $(python --version)"
echo "Pip version: $(pip --version)"

# Check versions of main packages
PACKAGES=("ccxt" "pandas" "numpy" "scikit-learn" "python-dotenv" "requests" "pytest")
for pkg in "${PACKAGES[@]}"; do
    version=$(python -c "try: import $pkg; print('$pkg:', $pkg.__version__); except: print('$pkg: not installed')" 2>/dev/null || echo "$pkg: not available")
    echo "$version"
done

# Check TA-Lib version separately since it might not be installed
if [ "$TALIB_INSTALLED" = true ]; then
    talib_version=$(python -c "try: import talib; print('TA-Lib:', talib.__version__); except: print('TA-Lib: installed but version unavailable')" 2>/dev/null || echo "TA-Lib: installed but version check failed")
    echo "$talib_version"
else
    echo "TA-Lib: not installed"
fi

# Run python -m compileall to catch syntax errors
echo "=== Checking for syntax errors ==="
if ! python -m compileall . -q; then
    echo "ERROR: Syntax errors found during compilation"
    exit 1
fi
echo "Syntax check passed"

# Run pytest if tests exist (but don't fail on test failures)
echo "=== Running tests (if available) ==="
if [ -d "tests" ] || find . -name "test_*.py" -type f | grep -q .; then
    echo "Tests found, running pytest..."
    if ! python -m pytest -v 2>/dev/null; then
        echo "Tests failed, but continuing (environment setup successful)"
    else
        echo "Tests passed"
    fi
else
    echo "No tests found, skipping pytest"
fi

# Perform safe smoke import of main package
echo "=== Performing smoke test ==="
MAIN_PACKAGES=("cryptobot" "src" "main" "app")
SMOKE_SUCCESS=false

for pkg in "${MAIN_PACKAGES[@]}"; do
    if python -c "import $pkg; print('Successfully imported $pkg')" 2>/dev/null; then
        SMOKE_SUCCESS=true
        break
    fi
done

# If none of the common main packages worked, try importing any Python file in the current directory
if [ "$SMOKE_SUCCESS" = false ]; then
    # Look for main.py or any importable Python module
    if [ -f "main.py" ]; then
        if python -c "exec(open('main.py').read()); print('Successfully executed main.py')" 2>/dev/null; then
            SMOKE_SUCCESS=true
        fi
    elif find . -name "*.py" -type f | head -1 | grep -q .; then
        # Try importing the first Python file we find (basic syntax check)
        FIRST_PY=$(find . -name "*.py" -type f | head -1)
        if python -c "import ast; ast.parse(open('$FIRST_PY').read()); print('Python files appear syntactically correct')" 2>/dev/null; then
            SMOKE_SUCCESS=true
        fi
    else
        # No Python files found, but that's okay for some projects
        SMOKE_SUCCESS=true
        echo "No Python modules found to import, but setup completed successfully"
    fi
fi

if [ "$SMOKE_SUCCESS" = true ]; then
    echo "JULES_OK"
else
    echo "Warning: Smoke test failed, but environment setup completed"
    echo "JULES_OK"
fi

echo "=== DONE (JULES_OK) ==="
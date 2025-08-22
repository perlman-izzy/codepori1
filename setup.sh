#!/usr/bin/env bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTEST_DISABLE_PLUGIN_AUTOLOAD=1

# --- HARD RESET OF WORKSPACE ---
APP_DIR="${APP_DIR:-/app}"

# Always leave /app before nuking it
cd /

# If /app exists, remove it completely
if [ -d "$APP_DIR" ]; then
  sudo rm -rf "$APP_DIR"
fi

# Recreate /app and give it to UID 1001
sudo mkdir -p "$APP_DIR"
sudo chown 1001:1001 "$APP_DIR"
sudo chmod -R u+rwX,go-rwx "$APP_DIR"

echo "=== Workspace reset: $APP_DIR is clean ==="

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

# Configure Git globally
echo "=== Configuring Git ==="
git config --global init.defaultBranch main
git config --global core.hooksPath /dev/null

# Add https/ssh rewrite rules if provided by environment variables
if [ -n "${GIT_URL_REWRITE_HTTPS:-}" ]; then
    git config --global url."$GIT_URL_REWRITE_HTTPS".insteadOf https://
fi

if [ -n "${GIT_URL_REWRITE_SSH:-}" ]; then
    git config --global url."$GIT_URL_REWRITE_SSH".insteadOf ssh://
fi

# Clone repository if REPO_URL is provided
if [ -n "${REPO_URL:-}" ]; then
    echo "=== Cloning repository from $REPO_URL ==="
    git clone "$REPO_URL" "$APP_DIR"
    cd "$APP_DIR"
else
    echo "=== No REPO_URL provided, working in $APP_DIR ==="
    cd "$APP_DIR"
fi

# Install common system dependencies
echo "=== Installing system dependencies ==="
run_with_sudo apt-get update -y
run_with_sudo apt-get install -y \
    build-essential \
    python3 \
    python3-dev \
    python3-venv \
    python3-pip \
    pkg-config \
    libssl-dev \
    libffi-dev \
    git \
    curl \
    ca-certificates \
    jq

# Detect stack automatically and handle each one
echo "=== Detecting project stacks ==="

PYTHON_DETECTED=false
NODE_DETECTED=false
DOTNET_DETECTED=false
JAVA_DETECTED=false
GO_DETECTED=false

# Python detection
if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || find . -name "*.py" -type f | head -1 | grep -q .; then
    PYTHON_DETECTED=true
    echo "Python stack detected"
fi

# Node detection
if [ -f "package.json" ]; then
    NODE_DETECTED=true
    echo "Node.js stack detected"
fi

# .NET detection
if find . -name "*.csproj" -o -name "*.sln" -type f | head -1 | grep -q .; then
    DOTNET_DETECTED=true
    echo ".NET stack detected"
fi

# Java detection
if [ -f "gradlew" ] || [ -f "build.gradle" ] || [ -f "pom.xml" ]; then
    JAVA_DETECTED=true
    echo "Java stack detected"
fi

# Go detection
if [ -f "go.mod" ]; then
    GO_DETECTED=true
    echo "Go stack detected"
fi

# Handle Python stack
if [ "$PYTHON_DETECTED" = true ]; then
    echo "=== Setting up Python environment ==="
    
    # Create virtual environment
    if command_exists uv; then
        echo "Using uv for virtual environment"
        uv venv venv || python3 -m venv venv
        source venv/bin/activate
    else
        echo "Using python3 -m venv for virtual environment"
        python3 -m venv venv
        source venv/bin/activate
    fi
    
    # Bootstrap pip
    python -m ensurepip --upgrade 2>/dev/null || true
    python -m pip install --upgrade pip
    
    # Install dependencies
    if [ -f "requirements.txt" ]; then
        echo "Installing from requirements.txt"
        if command_exists uv; then
            uv pip install -r requirements.txt || pip install -r requirements.txt
        else
            pip install -r requirements.txt
        fi
    elif [ -f "pyproject.toml" ]; then
        echo "Installing from pyproject.toml"
        if command_exists uv; then
            uv pip install -e . || pip install -e .
        else
            pip install -e .
        fi
    fi
    
    # Compile Python sources
    echo "Compiling Python sources"
    python -m compileall . -q || echo "Warning: Some Python files failed to compile"
    
    # Run pytest if present
    if [ -d "tests" ] || find . -name "test_*.py" -type f | head -1 | grep -q .; then
        echo "Running pytest"
        python -m pytest -v || echo "Warning: Tests failed but continuing"
    fi
fi

# Handle Node stack
if [ "$NODE_DETECTED" = true ]; then
    echo "=== Setting up Node.js environment ==="
    
    # Install Node.js if not present
    if ! command_exists node; then
        echo "Installing Node.js"
        curl -fsSL https://deb.nodesource.com/setup_lts.x | run_with_sudo -E bash -
        run_with_sudo apt-get install -y nodejs
    fi
    
    # Detect package manager and install dependencies
    if [ -f "yarn.lock" ] && command_exists yarn; then
        echo "Using yarn for dependencies"
        yarn install || echo "Warning: yarn install failed"
        yarn build 2>/dev/null || echo "No build script found"
        yarn test 2>/dev/null || echo "No test script found"
    elif [ -f "pnpm-lock.yaml" ] && command_exists pnpm; then
        echo "Using pnpm for dependencies"
        pnpm install || echo "Warning: pnpm install failed"
        pnpm build 2>/dev/null || echo "No build script found"
        pnpm test 2>/dev/null || echo "No test script found"
    else
        echo "Using npm for dependencies"
        npm install || echo "Warning: npm install failed"
        npm run build 2>/dev/null || echo "No build script found"
        npm test 2>/dev/null || echo "No test script found"
    fi
fi

# Handle .NET stack
if [ "$DOTNET_DETECTED" = true ]; then
    echo "=== Setting up .NET environment ==="
    
    # Install .NET if not present
    if ! command_exists dotnet; then
        echo "Installing .NET"
        wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
        run_with_sudo dpkg -i /tmp/packages-microsoft-prod.deb
        run_with_sudo apt-get update
        run_with_sudo apt-get install -y dotnet-sdk-8.0
    fi
    
    # Restore, build, and test
    dotnet restore || echo "Warning: dotnet restore failed"
    dotnet build || echo "Warning: dotnet build failed" 
    dotnet test || echo "Warning: dotnet test failed"
fi

# Handle Java stack
if [ "$JAVA_DETECTED" = true ]; then
    echo "=== Setting up Java environment ==="
    
    # Install Java if not present
    if ! command_exists java; then
        echo "Installing OpenJDK"
        run_with_sudo apt-get install -y openjdk-17-jdk
    fi
    
    # Handle Gradle projects
    if [ -f "gradlew" ] || [ -f "build.gradle" ]; then
        if [ -f "gradlew" ]; then
            chmod +x ./gradlew
            ./gradlew build || echo "Warning: gradle build failed"
            ./gradlew test || echo "Warning: gradle test failed"
        elif command_exists gradle; then
            gradle build || echo "Warning: gradle build failed"
            gradle test || echo "Warning: gradle test failed"
        fi
    # Handle Maven projects
    elif [ -f "pom.xml" ]; then
        if command_exists mvn; then
            mvn compile || echo "Warning: maven compile failed"
            mvn test || echo "Warning: maven test failed"
        else
            echo "Installing Maven"
            run_with_sudo apt-get install -y maven
            mvn compile || echo "Warning: maven compile failed"
            mvn test || echo "Warning: maven test failed"
        fi
    fi
fi

# Handle Go stack
if [ "$GO_DETECTED" = true ]; then
    echo "=== Setting up Go environment ==="
    
    # Install Go if not present
    if ! command_exists go; then
        echo "Installing Go"
        GO_VERSION="1.21.5"
        wget "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
        run_with_sudo tar -C /usr/local -xzf /tmp/go.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    fi
    
    # Handle Go modules
    go mod tidy || echo "Warning: go mod tidy failed"
    go build ./... || echo "Warning: go build failed"
    go test ./... || echo "Warning: go test failed"
fi

echo "JULES_OK"
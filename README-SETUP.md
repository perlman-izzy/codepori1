# CodePori Setup Instructions

## Overview
This repository contains CodePori, a code generation pipeline that can accept any program description in natural language, build it, and test it autonomously.

## Key Components

### 1. API Key System
- **apikeys2**: Contains main API key collection in structured format
- **apikeys5**: Contains additional API keys in plain text format
- Keys are automatically extracted from these files by the proxy system

### 2. Proxy Server Options

#### Option A: Mock Proxy (Development/Testing)
Use `mock-gemini-proxy.py` for development and testing without internet access:
```bash
cd /home/runner/work/codepori1/codepori1
python3 mock-gemini-proxy.py
```

#### Option B: Real Proxy (Production)
Use `gemini-flask-57.py` for production with real API access:
```bash
cd /home/runner/work/codepori1/codepori1
SKIP_KEY_VALIDATION=1 python3 gemini-flask-57.py  # Skip validation in restricted environments
# OR
python3 gemini-flask-57.py  # Full validation (requires internet access)
```

### 3. Main Pipeline
Run the CodePori main pipeline:
```bash
cd /home/runner/work/codepori1/codepori1/CodePori
python3 main.py
```

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   apikeys2      │───▶│ Proxy Server     │───▶│ CodePori        │
│   apikeys5      │    │ (Port 8000)      │    │ main.py         │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │ Generated Code   │
                       │ ./output/code/   │
                       └──────────────────┘
```

## Successful Pipeline Flow

1. **Planning**: LLM generates JSON plan with architecture, files, and tests
2. **Generation**: Creates source files and test files based on plan
3. **Syntax Gate**: Validates all generated code for syntax errors
4. **Package Normalization**: Adds `__init__.py` files and organizes packages
5. **Adapter Creation**: Creates test-driven contract adapters for imported functions
6. **Linting**: Universal linter ensures all imports and symbols are satisfied
7. **Testing**: Runs pytest and validates all tests pass

## Features Working

✅ **API Key Integration**: Reads from apikeys2 and apikeys5  
✅ **Streaming API Support**: Accepts streaming responses from Gemini proxy  
✅ **End-to-End Pipeline**: Complete plan → generate → test → validate flow  
✅ **Test-Driven Development**: Automatically creates test adapters  
✅ **Autonomous Operation**: Runs without human intervention  
✅ **Error Recovery**: Handles and repairs import/symbol errors  

## Output

Generated projects are created in `CodePori/output/code/` with:
- Source code in `src/`
- Tests in `tests/`
- Requirements file
- README documentation
- Complete package structure

## Testing

The system has been tested and verified to:
- Successfully connect to proxy servers
- Generate valid Python code
- Create working test suites
- Pass all automated tests
- Handle edge cases and error recovery
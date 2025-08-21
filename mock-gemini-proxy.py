#!/usr/bin/env python3
"""
Mock Gemini Proxy for development/testing - simulates the gemini-flask-57.py behavior
without needing actual internet access to Google's API.
"""

import json
import time
import random
from flask import Flask, request, jsonify, Response

app = Flask(__name__)

# Mock API keys loaded from files
VALID_API_KEYS = []

def load_mock_keys():
    global VALID_API_KEYS
    from pathlib import Path
    import re
    
    key_files = [Path(__file__).parent / "apikeys2", Path(__file__).parent / "apikeys5"]
    raw_keys = set()
    
    for key_file in key_files:
        if key_file.exists():
            try:
                raw_keys.update(re.findall(r"(AIza[0-9A-Za-z_\\-]{35})", key_file.read_text()))
            except Exception as e:
                print(f"Could not read key file {key_file}: {e}")
    
    VALID_API_KEYS = list(raw_keys)
    print(f"Loaded {len(VALID_API_KEYS)} mock API keys")

def generate_mock_response(prompt_text: str) -> str:
    """Generate a mock response that looks like it came from Gemini"""
    
    # Check if this is a planning request (contains "JSON object with keys: architecture")
    if "architecture" in prompt_text and "files" in prompt_text and "tests" in prompt_text:
        return json.dumps({
            "architecture": ["Simple modular architecture", "Clear separation of concerns"],
            "files": [
                {"path": "src/main.py", "purpose": "Main entry point for the application"},
                {"path": "src/utils.py", "purpose": "Utility functions"}
            ],
            "tests": [
                {"path": "tests/test_main.py", "purpose": "Test main functionality"},
                {"path": "tests/test_utils.py", "purpose": "Test utility functions"}
            ],
            "notes": "Basic structure for a Python application with tests"
        })
    
    # Check if this is a file generation request (contains "language" and "code")
    if "language" in prompt_text and "code" in prompt_text:
        # Detect test files
        if "test_" in prompt_text or "/test" in prompt_text:
            if "test_main" in prompt_text:
                return json.dumps({
                    "language": "python",
                    "code": "import pytest\nfrom src.main import main\n\ndef test_main():\n    \"\"\"Test main function\"\"\"\n    # This should not raise any exceptions\n    main()\n    assert True\n"
                })
            elif "test_utils" in prompt_text:
                return json.dumps({
                    "language": "python", 
                    "code": "import pytest\nfrom src.utils import helper_function\n\ndef test_helper_function():\n    \"\"\"Test helper function\"\"\"\n    result = helper_function()\n    assert result is not None\n"
                })
        
        # Regular source files
        if "src/main.py" in prompt_text or "main.py" in prompt_text:
            return json.dumps({
                "language": "python",
                "code": "#!/usr/bin/env python3\n\ndef main():\n    \"\"\"Main function\"\"\"\n    print('Hello from generated main!')\n    return True\n\nif __name__ == '__main__':\n    main()\n"
            })
        elif "src/utils.py" in prompt_text or "utils.py" in prompt_text:
            return json.dumps({
                "language": "python",
                "code": "#!/usr/bin/env python3\n\ndef helper_function():\n    \"\"\"A helper function\"\"\"\n    return \"Helper function result\"\n\ndef another_helper(value):\n    \"\"\"Another helper function\"\"\"\n    return value * 2\n"
            })
        
        # Default code generation
        return json.dumps({
            "language": "python",
            "code": "# Generated code file\ndef main():\n    print('Hello, World!')\n\nif __name__ == '__main__':\n    main()\n"
        })
    
    # Default fallback for other requests
    responses = [
        "I understand you want me to help with software development. Here's a simple response to your request.",
        "Based on your prompt, I can help you create the necessary code structure.",
        "I'll help you implement the requested functionality step by step.",
        f"I received your request about: {prompt_text[:100]}... Let me provide a helpful response.",
        "Here's a mock implementation to help you test the system.",
    ]
    return random.choice(responses)

@app.route("/v1beta/models/<path:model>:generateContent", methods=["POST"])
def v1_generate(model):
    """Mock non-streaming endpoint"""
    try:
        data = request.get_json()
        if not data or 'contents' not in data:
            return jsonify({"error": "Invalid request format"}), 400
        
        # Extract prompt text
        prompt_text = ""
        if data['contents'] and len(data['contents']) > 0:
            parts = data['contents'][0].get('parts', [])
            if parts and len(parts) > 0:
                prompt_text = parts[0].get('text', '')
        
        # Generate mock response
        response_text = generate_mock_response(prompt_text)
        
        response = {
            "candidates": [
                {
                    "content": {
                        "parts": [{"text": response_text}],
                        "role": "model"
                    },
                    "finishReason": "STOP",
                    "index": 0
                }
            ],
            "usageMetadata": {
                "promptTokenCount": len(prompt_text.split()),
                "candidatesTokenCount": len(response_text.split()),
                "totalTokenCount": len(prompt_text.split()) + len(response_text.split())
            }
        }
        
        return jsonify(response)
    
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/v1beta/models/<path:model>:streamGenerateContent", methods=["POST"])
def v1_stream(model):
    """Mock streaming endpoint"""
    try:
        data = request.get_json()
        if not data or 'contents' not in data:
            return jsonify({"error": "Invalid request format"}), 400
        
        # Extract prompt text
        prompt_text = ""
        if data['contents'] and len(data['contents']) > 0:
            parts = data['contents'][0].get('parts', [])
            if parts and len(parts) > 0:
                prompt_text = parts[0].get('text', '')
        
        # Generate mock response
        response_text = generate_mock_response(prompt_text)
        
        def generate_stream():
            # Split response into chunks to simulate streaming
            words = response_text.split()
            chunk_size = max(1, len(words) // 5)  # 5 chunks
            
            for i in range(0, len(words), chunk_size):
                chunk_words = words[i:i+chunk_size]
                chunk_text = " ".join(chunk_words)
                
                chunk_response = {
                    "candidates": [
                        {
                            "content": {
                                "parts": [{"text": chunk_text}],
                                "role": "model"
                            },
                            "index": 0
                        }
                    ]
                }
                
                yield f"data: {json.dumps(chunk_response)}\n\n"
                time.sleep(0.1)  # Small delay to simulate streaming
            
            # Final message
            yield f"data: {json.dumps({'done': True})}\n\n"
        
        return Response(generate_stream(), content_type='text/plain')
    
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "valid_keys": len(VALID_API_KEYS),
        "cooldown_keys": 0,
        "exhausted_keys_per_model": {}
    })

if __name__ == "__main__":
    load_mock_keys()
    print(f"Starting mock Gemini proxy on http://0.0.0.0:8000")
    app.run(host="0.0.0.0", port=8000, debug=False, threaded=True)
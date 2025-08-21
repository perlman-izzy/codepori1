import pytest
from src.main import main

def test_main():
    """Test main function"""
    # This should not raise any exceptions
    main()
    assert True

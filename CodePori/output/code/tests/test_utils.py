import pytest
from src.utils import helper_function

def test_helper_function():
    """Test helper function"""
    result = helper_function()
    assert result is not None

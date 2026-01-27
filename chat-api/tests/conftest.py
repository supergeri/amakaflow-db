import sys
from pathlib import Path
from typing import Generator

import pytest
from fastapi.testclient import TestClient

# Ensure chat-api root is on sys.path so `import backend` and `import api` work
ROOT = Path(__file__).resolve().parents[1]
root_str = str(ROOT)
if root_str not in sys.path:
    sys.path.insert(0, root_str)

from backend.main import create_app
from backend.settings import Settings
from backend.auth import get_current_user as backend_get_current_user
from api.deps import get_current_user as deps_get_current_user


# ---------------------------------------------------------------------------
# Auth Mock
# ---------------------------------------------------------------------------

TEST_USER_ID = "test-user-123"


async def mock_get_current_user() -> str:
    """Mock auth dependency that returns a test user."""
    return TEST_USER_ID


# ---------------------------------------------------------------------------
# Mock Environment Variables
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def mock_env_vars(monkeypatch):
    """Set mock environment variables for tests."""
    monkeypatch.setenv("ENVIRONMENT", "test")
    monkeypatch.setenv("SUPABASE_URL", "https://test.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "test-supabase-key")


# ---------------------------------------------------------------------------
# App & Client Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="session")
def test_settings() -> Settings:
    """Test settings with minimal configuration."""
    return Settings(
        environment="test",
        supabase_url="https://test.supabase.co",
        supabase_service_role_key="test-key",
        _env_file=None,
    )


@pytest.fixture(scope="session")
def app(test_settings):
    """Create test application instance."""
    return create_app(settings=test_settings)


@pytest.fixture(scope="session")
def api_client(app) -> Generator[TestClient, None, None]:
    """
    Shared FastAPI TestClient for chat-api endpoints.
    Properly cleans up dependency overrides.
    """
    app.dependency_overrides[backend_get_current_user] = mock_get_current_user
    app.dependency_overrides[deps_get_current_user] = mock_get_current_user
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture
def client(app) -> Generator[TestClient, None, None]:
    """
    Per-test FastAPI TestClient (for tests needing fresh state).
    """
    app.dependency_overrides[backend_get_current_user] = mock_get_current_user
    app.dependency_overrides[deps_get_current_user] = mock_get_current_user
    yield TestClient(app)
    app.dependency_overrides.clear()

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

PROJECT_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_SQLITE_PATH = PROJECT_ROOT / "backend" / "dev.db"
DEFAULT_SQLITE_URL = f"sqlite:///{DEFAULT_SQLITE_PATH.as_posix()}"


class Settings(BaseSettings):
    app_name: str = "패러글라이딩 브리핑 API"
    api_v1_prefix: str = "/api/v1"
    database_url: str = DEFAULT_SQLITE_URL
    sql_echo: bool = False
    auto_create_tables: bool = True
    allowed_origins: str = (
        "http://localhost:3000,http://localhost:8080,http://localhost:5173,http://localhost:8000"
    )

    # TODO: Keep the SQLite fallback for zero-setup demos, but use PostgreSQL for team environments.
    model_config = SettingsConfigDict(
        env_file=PROJECT_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.allowed_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

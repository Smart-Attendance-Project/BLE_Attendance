from pathlib import Path
from urllib.parse import urlsplit

from pydantic import model_validator

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "BLE Attendance Prototype"
    app_env: str = "dev"
    debug: bool = True

    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "ble_attendance"
    db_user: str = "postgres"
    db_password: str = "postgres"
    database_url_override: str | None = None

    jwt_secret: str = "change-this-in-production"
    jwt_algorithm: str = "HS256"
    jwt_exp_minutes: int = 60 * 8
    web_origins: list[str] | None = None

    model_config = SettingsConfigDict(
        env_file=str(Path(__file__).resolve().parents[1] / ".env"),
        env_file_encoding="utf-8",
    )

    @model_validator(mode="after")
    def validate_web_origins(self) -> "Settings":
        for origin in self.allowed_web_origins:
            url = urlsplit(origin)
            local = self.app_env == "dev" and url.scheme == "http" and url.hostname in {
                "localhost", "127.0.0.1", "::1",
            }
            if (
                (url.scheme != "https" and not local)
                or not url.hostname or "*" in url.netloc or url.username is not None
                or url.path or url.query or url.fragment
            ):
                raise ValueError("WEB_ORIGINS must contain exact HTTPS origins (local HTTP is allowed in dev)")
        return self

    @property
    def allowed_web_origins(self) -> list[str]:
        if self.web_origins is not None:
            return self.web_origins
        return ["http://localhost:5173", "http://127.0.0.1:5173"] if self.app_env == "dev" else []

    @property
    def database_url(self) -> str:
        if self.database_url_override:
            return self.database_url_override
        return (
            f"postgresql+psycopg://{self.db_user}:{self.db_password}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )


settings = Settings()

"""Generate the native server's API assets from the FastAPI reference."""
import json
from pathlib import Path

from fastapi.openapi.docs import (
    get_redoc_html, get_swagger_ui_html, get_swagger_ui_oauth2_redirect_html,
)
from sqlalchemy import create_mock_engine

from app.database import Base
from app.main import app

output = Path("build/native")
output.mkdir(parents=True, exist_ok=True)
(output / "openapi.json").write_text(json.dumps(app.openapi(), separators=(",", ":")))

for filename, response in {
    "docs.html": get_swagger_ui_html(
        openapi_url="/openapi.json",
        title=f"{app.title} - Swagger UI",
        oauth2_redirect_url="/docs/oauth2-redirect",
    ),
    "redoc.html": get_redoc_html(openapi_url="/openapi.json", title=f"{app.title} - ReDoc"),
    "oauth2-redirect.html": get_swagger_ui_oauth2_redirect_html(),
}.items():
    (output / filename).write_bytes(response.body)

statements = ["SELECT pg_advisory_xact_lock(hashtext(current_schema()), hashtext('ble_attendance_schema'))"]
indexes = []


def capture(sql, *args, **kwargs):
    statement = str(sql.compile(dialect=engine.dialect)).strip()
    if statement.startswith("CREATE TYPE userrole"):
        statement = f"DO $$ BEGIN {statement}; EXCEPTION WHEN duplicate_object THEN NULL; END $$"
    elif statement.startswith("CREATE TABLE"):
        statement = statement.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS ", 1)
    elif statement.startswith("CREATE UNIQUE INDEX"):
        statement = statement.replace("CREATE UNIQUE INDEX ", "CREATE UNIQUE INDEX IF NOT EXISTS ", 1)
    elif statement.startswith("CREATE INDEX"):
        statement = statement.replace("CREATE INDEX ", "CREATE INDEX IF NOT EXISTS ", 1)
    if " INDEX IF NOT EXISTS " in statement:
        indexes.append(statement)
    else:
        statements.append(statement)


engine = create_mock_engine("postgresql+psycopg://", capture)
Base.metadata.create_all(engine, checkfirst=False)
legacy_columns = [
    "ALTER TYPE userrole ADD VALUE IF NOT EXISTS 'admin'",
    "ALTER TABLE sessions ADD COLUMN IF NOT EXISTS finalization_open BOOLEAN DEFAULT FALSE",
    "ALTER TABLE sessions ADD COLUMN IF NOT EXISTS assignment_id INTEGER REFERENCES teacher_assignments(id)",
    "ALTER TABLE sessions ADD COLUMN IF NOT EXISTS attendance_locked BOOLEAN DEFAULT FALSE",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS admin_id VARCHAR(16) UNIQUE",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS is_super_admin BOOLEAN DEFAULT FALSE",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS face_embedding JSON",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS face_reg_timestamps JSON",
    "ALTER TABLE divisions ADD COLUMN IF NOT EXISTS start_student_id VARCHAR(16)",
    "ALTER TABLE divisions ADD COLUMN IF NOT EXISTS end_student_id VARCHAR(16)",
]
(output / "schema.sql").write_text(";\n\n".join(statements + legacy_columns + indexes) + ";\n")

"""Initial schema for the paragliding MVP."""

from alembic import op
import sqlalchemy as sa


revision = "0001_initial_schema"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("full_name", sa.String(length=120), nullable=False),
        sa.Column("password", sa.String(length=255), nullable=False),
        sa.Column("pilot_level", sa.String(length=32), nullable=False),
        sa.Column("is_admin", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)

    op.create_table(
        "flying_sites",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("region", sa.String(length=120), nullable=False),
        sa.Column("difficulty", sa.String(length=32), nullable=False),
        sa.Column("short_description", sa.String(length=255), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("takeoff_altitude_m", sa.Integer(), nullable=False),
        sa.Column("landing_altitude_m", sa.Integer(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_flying_sites_name", "flying_sites", ["name"], unique=True)
    op.create_index("ix_flying_sites_region", "flying_sites", ["region"], unique=False)

    op.create_table(
        "notices",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("category", sa.String(length=64), nullable=False),
        sa.Column("is_pinned", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "site_rules",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("site_id", sa.Integer(), sa.ForeignKey("flying_sites.id"), nullable=False),
        sa.Column("allowed_direction_start", sa.Integer(), nullable=False),
        sa.Column("allowed_direction_end", sa.Integer(), nullable=False),
        sa.Column("beginner_max_average_wind", sa.Float(), nullable=False),
        sa.Column("intermediate_max_average_wind", sa.Float(), nullable=False),
        sa.Column("advanced_max_average_wind", sa.Float(), nullable=False),
        sa.Column("max_gust", sa.Float(), nullable=False),
        sa.Column("max_gust_difference", sa.Float(), nullable=False),
        sa.Column("allow_precipitation", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("beginner_allowed", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("notes", sa.String(length=255), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_site_rules_site_id", "site_rules", ["site_id"], unique=True)

    op.create_table(
        "weather_snapshots",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("site_id", sa.Integer(), sa.ForeignKey("flying_sites.id"), nullable=False),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("average_wind_speed", sa.Float(), nullable=False),
        sa.Column("wind_direction", sa.Integer(), nullable=False),
        sa.Column("gust_speed", sa.Float(), nullable=False),
        sa.Column("precipitation_mm", sa.Float(), nullable=True),
        sa.Column("summary", sa.String(length=255), nullable=False),
        sa.Column("hourly_forecast", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_weather_snapshots_site_id", "weather_snapshots", ["site_id"], unique=False)

    op.create_table(
        "flight_assessments",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("site_id", sa.Integer(), sa.ForeignKey("flying_sites.id"), nullable=False),
        sa.Column("weather_snapshot_id", sa.Integer(), sa.ForeignKey("weather_snapshots.id"), nullable=True),
        sa.Column("pilot_level", sa.String(length=32), nullable=False),
        sa.Column("score", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("reasons", sa.JSON(), nullable=False),
        sa.Column("summary_text", sa.String(length=255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_flight_assessments_site_id", "flight_assessments", ["site_id"], unique=False)
    op.create_index("ix_flight_assessments_weather_snapshot_id", "flight_assessments", ["weather_snapshot_id"], unique=False)
    op.create_index("ix_flight_assessments_pilot_level", "flight_assessments", ["pilot_level"], unique=False)

    op.create_table(
        "training_logs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("site_id", sa.Integer(), sa.ForeignKey("flying_sites.id"), nullable=False),
        sa.Column("training_date", sa.Date(), nullable=False),
        sa.Column("training_type", sa.String(length=120), nullable=False),
        sa.Column("participated", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("flight_success", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("difficulty", sa.String(length=32), nullable=False),
        sa.Column("memo", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_training_logs_user_id", "training_logs", ["user_id"], unique=False)
    op.create_index("ix_training_logs_site_id", "training_logs", ["site_id"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_training_logs_site_id", table_name="training_logs")
    op.drop_index("ix_training_logs_user_id", table_name="training_logs")
    op.drop_table("training_logs")

    op.drop_index("ix_flight_assessments_pilot_level", table_name="flight_assessments")
    op.drop_index("ix_flight_assessments_weather_snapshot_id", table_name="flight_assessments")
    op.drop_index("ix_flight_assessments_site_id", table_name="flight_assessments")
    op.drop_table("flight_assessments")

    op.drop_index("ix_weather_snapshots_site_id", table_name="weather_snapshots")
    op.drop_table("weather_snapshots")

    op.drop_index("ix_site_rules_site_id", table_name="site_rules")
    op.drop_table("site_rules")

    op.drop_table("notices")

    op.drop_index("ix_flying_sites_region", table_name="flying_sites")
    op.drop_index("ix_flying_sites_name", table_name="flying_sites")
    op.drop_table("flying_sites")

    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")

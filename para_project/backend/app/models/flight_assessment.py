from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, Integer, JSON, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class FlightAssessment(Base):
    __tablename__ = "flight_assessments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    site_id: Mapped[int] = mapped_column(ForeignKey("flying_sites.id"), index=True)
    weather_snapshot_id: Mapped[int | None] = mapped_column(
        ForeignKey("weather_snapshots.id"),
        nullable=True,
        index=True,
    )
    pilot_level: Mapped[str] = mapped_column(String(32), index=True)
    score: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(32))
    reasons: Mapped[list[str]] = mapped_column(JSON, default=list)
    summary_text: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )

    site: Mapped["FlyingSite"] = relationship(back_populates="assessments")
    weather_snapshot: Mapped["WeatherSnapshot | None"] = relationship(back_populates="assessments")

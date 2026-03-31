from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, Float, ForeignKey, Integer, JSON, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class WeatherSnapshot(Base):
    __tablename__ = "weather_snapshots"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    site_id: Mapped[int] = mapped_column(ForeignKey("flying_sites.id"), index=True)
    observed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    average_wind_speed: Mapped[float] = mapped_column(Float)
    wind_direction: Mapped[int] = mapped_column(Integer)
    gust_speed: Mapped[float] = mapped_column(Float)
    precipitation_mm: Mapped[float | None] = mapped_column(Float, nullable=True)
    summary: Mapped[str] = mapped_column(String(255))
    hourly_forecast: Mapped[list[dict]] = mapped_column(JSON, default=list)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )

    site: Mapped["FlyingSite"] = relationship(back_populates="weather_snapshots")
    assessments: Mapped[list["FlightAssessment"]] = relationship(back_populates="weather_snapshot")

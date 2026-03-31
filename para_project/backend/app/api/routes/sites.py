from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.db.session import get_db
from app.models.enums import PilotLevel
from app.models.flying_site import FlyingSite
from app.schemas.site import SiteDetailResponse, SiteSummaryResponse
from app.services.assessment import (
    assess_flight,
    build_site_detail,
    build_site_summary,
    latest_weather_for_site,
)

router = APIRouter(prefix="/sites", tags=["사이트"])


@router.get("", response_model=list[SiteSummaryResponse])
def list_sites(
    q: str | None = Query(default=None),
    pilot_level: PilotLevel = Query(default=PilotLevel.beginner),
    db: Session = Depends(get_db),
) -> list[SiteSummaryResponse]:
    sites = (
        db.execute(
            select(FlyingSite)
            .where(FlyingSite.is_active.is_(True))
            .options(
                selectinload(FlyingSite.rule),
                selectinload(FlyingSite.weather_snapshots),
            )
            .order_by(FlyingSite.region.asc(), FlyingSite.name.asc())
        )
        .scalars()
        .unique()
        .all()
    )

    filtered: list[SiteSummaryResponse] = []
    search_value = q.strip().lower() if q else None
    for site in sites:
        if search_value and search_value not in site.name.lower() and search_value not in site.region.lower():
            continue

        weather = latest_weather_for_site(site)
        if site.rule is None or weather is None:
            continue

        assessment = assess_flight(site, site.rule, weather, pilot_level)
        filtered.append(build_site_summary(site, weather, assessment))

    return filtered


@router.get("/{site_id}", response_model=SiteDetailResponse)
def read_site_detail(
    site_id: int,
    pilot_level: PilotLevel = Query(default=PilotLevel.beginner),
    db: Session = Depends(get_db),
) -> SiteDetailResponse:
    site = (
        db.execute(
            select(FlyingSite)
            .where(FlyingSite.id == site_id)
            .options(
                selectinload(FlyingSite.rule),
                selectinload(FlyingSite.weather_snapshots),
            )
        )
        .scalar_one_or_none()
    )
    if site is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사이트를 찾을 수 없습니다.")
    if site.rule is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사이트 기준 정보가 없습니다.")

    weather = latest_weather_for_site(site)
    if weather is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="기상 정보가 없습니다.")

    assessment = assess_flight(site, site.rule, weather, pilot_level)
    return build_site_detail(site, weather, assessment)

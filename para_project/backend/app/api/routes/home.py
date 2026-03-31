from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.db.session import get_db
from app.models.enums import PilotLevel
from app.models.flying_site import FlyingSite
from app.models.notice import Notice
from app.schemas.home import HomeResponse
from app.schemas.notice import NoticeListItemResponse
from app.schemas.site import SiteSummaryResponse
from app.services.assessment import assess_flight, build_site_summary, latest_weather_for_site

router = APIRouter(prefix="/home", tags=["홈"])


@router.get("", response_model=HomeResponse)
def read_home(
    pilot_level: PilotLevel = Query(default=PilotLevel.beginner),
    db: Session = Depends(get_db),
) -> HomeResponse:
    sites = (
        db.execute(
            select(FlyingSite)
            .where(FlyingSite.is_active.is_(True))
            .options(
                selectinload(FlyingSite.rule),
                selectinload(FlyingSite.weather_snapshots),
            )
        )
        .scalars()
        .unique()
        .all()
    )

    site_cards: list[SiteSummaryResponse] = []
    for site in sites:
        weather = latest_weather_for_site(site)
        if site.rule is None or weather is None:
            continue
        assessment = assess_flight(site, site.rule, weather, pilot_level)
        site_cards.append(build_site_summary(site, weather, assessment))

    recommended_site = max(site_cards, key=lambda item: item.assessment.score) if site_cards else None
    pinned_notices = (
        db.execute(
            select(Notice)
            .order_by(Notice.is_pinned.desc(), Notice.published_at.desc())
            .limit(3)
        )
        .scalars()
        .all()
    )

    return HomeResponse(
        date=date.today(),
        pilot_level=pilot_level.value,
        recommended_site=recommended_site,
        sites=site_cards,
        notices=[NoticeListItemResponse.model_validate(notice) for notice in pinned_notices],
    )

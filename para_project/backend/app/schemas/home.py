from datetime import date

from pydantic import BaseModel

from app.schemas.notice import NoticeListItemResponse
from app.schemas.site import SiteSummaryResponse


class HomeResponse(BaseModel):
    date: date
    pilot_level: str
    recommended_site: SiteSummaryResponse | None
    sites: list[SiteSummaryResponse]
    notices: list[NoticeListItemResponse]

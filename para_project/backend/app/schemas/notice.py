from datetime import datetime

from pydantic import BaseModel, ConfigDict


class NoticeCreateRequest(BaseModel):
    title: str
    body: str
    category: str
    is_pinned: bool = False
    published_at: datetime


class NoticeUpdateRequest(NoticeCreateRequest):
    pass


class NoticeListItemResponse(BaseModel):
    id: int
    title: str
    body: str
    category: str
    is_pinned: bool
    published_at: datetime

    model_config = ConfigDict(from_attributes=True)


class NoticeDetailResponse(NoticeListItemResponse):
    created_at: datetime
    updated_at: datetime

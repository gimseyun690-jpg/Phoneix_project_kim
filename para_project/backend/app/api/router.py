from fastapi import APIRouter

from app.api.routes import admin, assessments, auth, home, notices, sites, training_logs, weather

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(home.router)
api_router.include_router(sites.router)
api_router.include_router(weather.router)
api_router.include_router(assessments.router)
api_router.include_router(training_logs.router)
api_router.include_router(notices.router)
api_router.include_router(admin.router)

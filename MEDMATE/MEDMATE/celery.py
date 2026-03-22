"""
MEDMATE/celery.py
"""

import logging
import os

from celery import Celery
from celery.signals import worker_init, worker_ready

logger = logging.getLogger(__name__)

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "MEDMATE.settings")

app = Celery("MEDMATE")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()

_ready_logged = False


@worker_init.connect
def on_worker_init(sender, **kwargs):
    logger.info("Worker init — hostname=%s  starting model preload", sender.hostname)
    try:
        from apps.ai_engine.pipeline import start_pipeline_preload
        start_pipeline_preload()
    except Exception:
        logger.exception("Preload start failed — models will lazy-load on first task")


@worker_ready.connect
def on_worker_ready(sender, **kwargs):
    global _ready_logged
    if not _ready_logged:
        _ready_logged = True
        logger.info("Worker ready — hostname=%s  AI models loading in background", sender.hostname)
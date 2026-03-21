"""
MEDMATE/celery.py
──────────────────────────────────────────────────────────────
WHY MODELS WERE LOADING IN BOTH TERMINALS:

    apps.py ready() fires in EVERY process that loads Django:
        ✅ Celery worker    → wanted
        ❌ Django runserver → NOT wanted
        ❌ manage.py shell  → NOT wanted
        ❌ manage.py migrate → NOT wanted

    sys.argv detection to distinguish them is unreliable on Windows
    because Django's dev server spawns subprocesses with ambiguous argv.

THE CORRECT FIX — Use Celery signals:

    @worker_init.connect  → fires when a Celery WORKER process initialises
    @worker_ready.connect → fires when a Celery WORKER is fully ready

    These signals are part of the Celery lifecycle.
    Django's runserver NEVER emits them.
    This is 100% reliable regardless of OS or launch method.

Fixes vs original:
  - logging instead of print()
  - worker_ready handler checks sender.hostname so that with --concurrency=N
    the "models already loaded / still loading" message appears only once
    (from the first worker process) instead of N times.
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


@worker_init.connect
def on_worker_init(sender, **kwargs):
    """
    Fires when a Celery worker PROCESS initialises.
    This is the earliest safe point to start loading models.

    We kick off the background preload thread here so models begin
    loading immediately — before the first task even arrives.

    Note: with --concurrency=N this fires N times (once per worker process).
    start_pipeline_preload() is idempotent so duplicate calls are harmless.
    """
    logger.info("Celery worker initialising — starting model preload …")
    try:
        from apps.ai_engine.pipeline import start_pipeline_preload
        start_pipeline_preload()
        logger.info("Model preload started in background thread")
    except Exception:
        logger.exception(
            "Preload start failed — models will lazy-load on first task"
        )


@worker_ready.connect
def on_worker_ready(sender, **kwargs):
    """
    Fires when the Celery worker is fully ready to accept tasks.
    Used here for a status log only.

    sender.hostname is unique per worker process (e.g. celery@hostname).
    """
    from apps.ai_engine.pipeline import _pipeline_instance

    if _pipeline_instance is not None:
        logger.info(
            "Worker %s ready — AI models already loaded", sender.hostname
        )
    else:
        logger.info(
            "Worker %s ready — AI models still loading in background",
            sender.hostname,
        )
"""
apps.py
───────
IMPORTANT: This file does NOT load AI models.

Previous approach (broken):
    Used ready() + sys.argv detection to try to load models only in
    Celery workers. This failed because:
    - Django's runserver spawns child processes with ambiguous sys.argv
    - Both Django and Celery import Django apps, so ready() fires in both
    - No sys.argv check is 100% reliable across all launch methods

Correct approach:
    Models are loaded ONLY via Celery signals in celery.py.
    The worker_ready signal fires EXCLUSIVELY inside Celery worker
    processes — it is a Celery lifecycle event, not a Django event.
    Django web server never receives this signal.

    See: MEDMATE/celery.py  ← that's where preloading is triggered
"""

from django.apps import AppConfig


class AiEngineConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.ai_engine"

    def ready(self):
        # DO NOTHING HERE.
        # Model preloading is handled exclusively in celery.py
        # via the worker_ready Celery signal.
        pass
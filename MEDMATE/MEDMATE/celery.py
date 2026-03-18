"""
celery.py  →  MEDMATE/celery.py  (same folder as settings.py)
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

    @worker_ready.connect   → fires when a Celery WORKER is fully started
    @worker_init.connect    → fires when a Celery WORKER process initialises

    These signals are part of the Celery lifecycle.
    Django's runserver NEVER emits them.
    This is 100% reliable regardless of OS or launch method.

RESULT:
    Django terminal  → NO model loading (clean, fast startup)
    Celery terminal  → Models load in background thread on worker start
"""

import os
import threading
from celery import Celery
from celery.signals import worker_ready, worker_init

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "MEDMATE.settings")

app = Celery("MEDMATE")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()


@worker_init.connect
def on_worker_init(sender, **kwargs):
    """
    Fires when a Celery worker PROCESS initialises.
    This is the earliest safe point to start loading models.

    We start the background preload thread here so models begin
    loading immediately — before the first task even arrives.
    """
    print("\n🔧 Celery worker initialising — starting model preload...")
    try:
        from apps.ai_engine.pipeline import start_pipeline_preload
        start_pipeline_preload()
        print("🔄 Model preload started in background thread")
    except Exception as e:
        print(f"⚠️  Preload start failed ({e}) — will lazy-load on first task")


@worker_ready.connect
def on_worker_ready(sender, **kwargs):
    """
    Fires when the Celery worker is fully ready to accept tasks.
    Used here just for a status log — preload was already started
    in worker_init above.
    """
    from apps.ai_engine.pipeline import _pipeline_instance
    if _pipeline_instance is not None:
        print("✅ Worker ready — AI models already loaded")
    else:
        print("⏳ Worker ready — AI models still loading in background")
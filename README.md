# MedMate 💊

> **Status: Under Active Development** — Core features are functional. The system is being refined and is not yet in a release-ready state.

**MedMate** is an AI-powered medication management system that eliminates manual prescription entry. A user photographs a handwritten or printed prescription — the system extracts, structures, and schedules every medicine automatically, then fires native device alarms at the exact right time.

---

## The Problem It Solves

- Patients misread or manually mis-enter prescription data
- Reminder apps require manual setup — one medicine at a time
- Handwritten prescriptions are error-prone when transcribed
- Standard alarms fail when the app is killed by the OS

MedMate solves all four with a single photo.

---

## System Architecture

```
Flutter App  ──►  Django REST API  ──►  Celery Worker
                                              │
                                    ┌─────────▼──────────┐
                                    │   AI Pipeline       │
                                    │  PaddleOCR          │
                                    │  Qwen2-VL (Vision)  │
                                    │  Qwen-Instruct LLM  │
                                    └─────────────────────┘
                                              │
                                         PostgreSQL
```

The backend is fully asynchronous. The user receives a response immediately after upload while the AI processes the prescription in the background via a Celery + Redis worker queue.

---

## Key Features

### AI Prescription Pipeline
- **PaddleOCR** detects and extracts raw text from prescription images
- **Qwen2-VL** corrects handwriting errors and ambiguous characters
- **Qwen-Instruct LLM** acts as a pharmacist — parsing medicine names, dosages, and frequencies into structured JSON
- Full pipeline completes in under 30 seconds end-to-end
- Parallel GPU execution across independent CUDA contexts reduced AI inference time by **65%**

### Smart Scheduling Engine
- Users define personal meal/sleep anchors (breakfast, lunch, dinner times)
- `ScheduleEngine` computes exact alarm times from medication intent (e.g. "30 minutes before lunch")
- Schedules are stored locally for offline resilience

### Native Android Alarms
- Alarms are set directly via Android's `AlarmManager` through Flutter's `MethodChannel`
- Fires even when the app is completely closed or the OS attempts to kill it
- Per-medicine, per-dose alarm management

### Backend Engineering
- **JWT Authentication** with silent token rotation — expired sessions refresh automatically without user interruption
- **Pessimistic DB locking** prevents duplicate AI processing of the same prescription
- **`bulk_create` + `prefetch_related`** for optimized database queries (N+1 solved)
- **MIME validation** via `python-magic` — uploaded files are verified at the byte level, not just by extension
- `transaction.on_commit` ensures AI tasks only fire after the database write is confirmed

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter / Dart |
| Backend | Django + Django REST Framework |
| Database | PostgreSQL |
| Task Queue | Celery + Redis |
| OCR | PaddleOCR |
| Vision Model | Qwen2-VL |
| Language Model | Qwen-Instruct |
| Auth | JWT (SimpleJWT) |
| Containerization | Docker (basic) |

---

---

## Current Development State

This project is actively being built. What's working:

- [x] User registration, login, JWT auth with token refresh
- [x] Prescription image upload and validation
- [x] Full AI extraction pipeline (OCR → Vision → LLM)
- [x] Celery async processing with Redis
- [x] Medicine scheduling via anchor-based ScheduleEngine
- [x] Native Android alarms via MethodChannel
- [x] Per-user data isolation
- [x] OTP email verification

What's in progress:

- [ ] Riverpod/Bloc state management refactor
- [ ] Unit tests for ScheduleEngine
- [ ] Global network error handling in Flutter
- [ ] iOS alarm support

---

## Data Flow (Upload → Alarm)

1. User photographs prescription in the Flutter app
2. Image sent via authenticated multipart request to Django
3. Django validates MIME type, saves image, returns `201 Pending` immediately
4. Celery picks up the background task
5. AI pipeline extracts structured medicine JSON
6. Flutter polls and retrieves processed data
7. `ScheduleEngine` computes alarm times from user anchors
8. Android `AlarmManager` sets exact alarms for each dose

---

## Domain

Healthcare / medication adherence — designed for patients managing complex multi-medicine prescriptions from handwritten doctor notes.

---

> Built by [Santosh Kuruventi](https://linkedin.com/in/santosh-kuruventi) · B.Tech CSE · 2026

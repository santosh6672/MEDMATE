
# MedMate 💊

**B.Tech Final Year Group Project** — developed by a team of three as part of our  major project.

**MedMate** is an AI-powered medication management system for patients managing complex, multi-medicine prescriptions from handwritten doctor notes. A single photo of a prescription — typed or handwritten — triggers a full extraction, scheduling, and alarm pipeline. No manual entry. No missed doses.

---

## Why This Exists

Manual medication entry is the weakest link in patient adherence:

- Patients misread handwritten prescriptions and enter wrong dosages
- Reminder apps require one-by-one setup — time-consuming and error-prone
- Standard phone alarms are killed by Android's battery optimizer
- There is no app that goes from *photo* → *structured schedule* → *firing alarm*

MedMate solves all four with a single photograph.

---

## Architecture

```
Flutter App (Android)
      │
      │  Multipart image upload (JWT-authenticated)
      ▼
FastAPI on AWS Lambda  ──►  Supabase PostgreSQL
      │
      │  Background AI pipeline
      ▼
┌─────────────────────────────────────┐
│           AI Pipeline               │
│                                     │
│  Step 1 — Llama 4 Scout (Vision)    │
│           Extracts raw prescription │
│           text from image           │
│                                     │
│  Step 2 — Llama 3.3 70B (Instruct)  │
│           Acts as clinical          │
│           pharmacist: parses names, │
│           dosages, frequencies into │
│           structured JSON           │
└─────────────────────────────────────┘
      │
      │  Structured medicine data
      ▼
Flutter ScheduleEngine
      │
      │  Computes exact alarm times
      │  from user's personal meal/sleep anchors
      ▼
Android AlarmManager
      │  Fires even when app is killed by OS
      ▼
  Full-screen alarm with TTS + snooze
```

The API is fully **async** (FastAPI + async SQLAlchemy). The user receives a `202 Processing` response immediately after upload; the Flutter client polls until the AI pipeline completes.

---

## Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| Mobile | Flutter / Dart | Android (primary), iOS scaffold present |
| Backend | FastAPI (Python 3.12) | Async, deployed on AWS Lambda via Mangum |
| Database | PostgreSQL | Hosted on Supabase |
| Auth | Supabase Auth (JWT) | Silent token rotation on client |
| Vision AI | Llama 4 Scout 17B | Via Groq API |
| Language AI | Llama 3.3 70B | Via Groq API |
| Storage | AWS S3 (ap-south-2) | Prescription images |
| Android Alarms | AlarmManager + BootReceiver | Native Kotlin, fires through Doze |

---

## Project Structure

```
MEDMATE/
├── main.py                          # FastAPI app, lifespan, CORS, Lambda handler
├── apps/
│   ├── ai_engine/
│   │   ├── pipeline.py              # Orchestrates image → OCR → LLM pipeline
│   │   ├── ocr/
│   │   │   └── groq_vision.py       # Llama 4 Scout vision call (3-attempt retry)
│   │   └── reasoner/
│   │       └── groq_instruct.py     # Llama 3.3 70B extraction + sanitisation
│   ├── auth/
│   │   └── dependencies.py          # JWT validation via Supabase, persistent client
│   └── prescriptions/
│       ├── models.py                # SQLAlchemy ORM (Prescription, Medicine)
│       ├── schemas.py               # Pydantic response schemas (full + list)
│       └── router.py                # Upload, list, get, delete endpoints
└── flutter/medmate/
    ├── lib/
    │   ├── main.dart                # App entry, splash, auth routing
    │   ├── services/
    │   │   ├── api_service.dart     # HTTP layer, token rotation
    │   │   ├── alarm_service.dart   # MethodChannel bridge to Android AlarmManager
    │   │   ├── schedule_engine.dart # Anchor-based alarm time computation
    │   │   ├── anchor_storage.dart  # Persists user meal/sleep times
    │   │   └── reminder_storage.dart
    │   ├── screens/                 # 10 screens (login, dashboard, upload, etc.)
    │   ├── models/                  # Dart models (MedConfig, MedicationIntent, etc.)
    │   └── widgets/                 # Shared UI components
    └── android/
        └── app/src/main/kotlin/
            ├── MainActivity.kt      # MethodChannel handler, permission flows
            ├── AlarmActivity.kt     # Full-screen alarm UI, TTS, snooze logic
            ├── AlarmReceiver.kt     # BroadcastReceiver, fires AlarmActivity
            ├── AlarmScheduler.kt    # AlarmManager scheduling wrapper
            ├── Alarmrepository.kt   # SharedPreferences persistence for reboot recovery
            └── BootReceiver.kt      # Reschedules all alarms after device reboot
```

---

## Data Flow: Photo → Alarm

```
1.  User opens camera in UploadScreen
2.  Image compressed to 85% quality, sent as multipart/form-data
3.  FastAPI validates content-type, uploads image to S3
4.  DB record created with status = "processing", 202 returned immediately
5.  AI pipeline runs:
        a. Pillow: EXIF auto-rotate + resize to max 2000px (thread pool)
        b. Llama 4 Scout: extracts raw prescription text
        c. Llama 3.3 70B: parses text → structured JSON with dose flags
6.  DB updated to status = "processed", medicines saved
7.  Flutter polls every 20s (max 15 attempts) until status resolves
8.  ScheduleEngine maps each medicine's timing instruction to exact DateTime
9.  AlarmService calls Android via MethodChannel
10. AlarmManager.setExactAndAllowWhileIdle fires AlarmActivity at exact time
11. Full-screen alarm wakes device, plays audio, reads medicine name aloud
12. User taps "Taken" or snoozes (up to 3×, 5min each)
```

---

## API Reference

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/health` | None | Service status + dependency versions |
| `POST` | `/api/prescriptions/` | JWT | Upload prescription image |
| `GET` | `/api/prescriptions/` | JWT | List all prescriptions (paginated) |
| `GET` | `/api/prescriptions/{id}` | JWT | Get prescription with full medicine list |
| `DELETE` | `/api/prescriptions/{id}` | JWT | Delete prescription + cascade medicines |

All endpoints require `Authorization: Bearer <token>`. List endpoint supports `limit` (1–100, default 20) and `offset` query parameters.

---

## Running Locally

**Backend**

```bash
# Clone and install
git clone https://github.com/santosh-kuruventi/MEDMATE
cd MEDMATE
pip install -r requirements.txt

# Environment variables
cp .env.example .env
# Fill in: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_DB_URL,
#          GROQ_API_KEY, S3_BUCKET, AWS_REGION

# Run
uvicorn main:app --reload
# → http://localhost:8000/docs
```

**Flutter**

```bash
cd flutter/medmate
flutter pub get
flutter run
```
---

## Features

- [x] User registration, login, email OTP verification (Supabase Auth)
- [x] Silent JWT token rotation on every API call
- [x] Prescription image upload with S3 storage
- [x] Full AI extraction pipeline (Vision → LLM → structured JSON)
- [x] Dose safety flagging with per-medicine reason strings
- [x] Anchor-based scheduling engine (breakfast / lunch / dinner / bedtime offsets)
- [x] Native Android alarms via `AlarmManager` — fires through Doze, app-kill-safe
- [x] Alarm persistence across device reboots (`BootReceiver` + `SharedPreferences`)
- [x] Full-screen alarm UI with TTS medicine name readout and snooze (3× / 5 min)
- [x] Per-user data isolation enforced at every DB query
- [x] Paginated prescription history

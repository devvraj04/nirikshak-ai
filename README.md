# Nirikshak AI - Legal Metrology Compliance Scanner

Nirikshak AI is a full-stack solution designed to instantly evaluate packaged commodities for compliance against the Legal Metrology (Packaged Commodities) Rules, 2011. It extracts declarations (MRP, Expiry, Weight, etc.) using OCR & AI and verifies them against legal rules.

## 🚀 Repository Structure

This repository is a monorepo containing three main components:
1. **`backend/`**: FastAPI backend + Celery Worker for OCR (PaddleOCR) & AI Extraction (LLaMA 3).
2. **`web/`**: Next.js Admin Dashboard for officers to review violations and trust scores.
3. **`mobile/`**: Flutter mobile application for scanning products and submitting complaints.

---

## 🛠️ Prerequisites

Before you start, ensure you have the following installed:
- [Docker & Docker Compose](https://www.docker.com/) (For Backend, Redis, ChromaDB, Minio)
- [Node.js v18+](https://nodejs.org/) (For Web Dashboard)
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (For Mobile App)
- [Supabase Account](https://supabase.com/) (For remote PostgreSQL Database)

---

## ⚙️ Step 1: Backend Setup

1. **Configure Environment Variables:**
   Navigate to the root directory and copy `.env.example` to `.env`.
   ```bash
   cp .env.example .env
   ```
   Open `.env` and configure your keys:
   - Paste your **Supabase PostgreSQL Connection String** into `DATABASE_URL` (make sure it starts with `postgresql://`).
   - Paste your **Groq API Key** into `GROQ_API_KEY`.

2. **Start the Docker Containers:**
   Run the following command from the root directory to build and start the backend, worker, redis, chromadb, and minio.
   ```bash
   docker compose up -d --build
   ```
   *Note: Upon first startup, the backend will automatically connect to your Supabase instance and dynamically create all necessary tables. No manual database migrations are required!*

---

## 📱 Step 2: Mobile App Setup

Because the mobile app runs on a physical device, it needs to know how to connect to your computer's backend.

1. **Set the API address:** For a physical phone, use your computer's current local Wi-Fi IP. For the Android emulator, use `10.0.2.2` instead of the computer IP.
2. **Run the App:**
   Ensure your phone and PC are on the same Wi-Fi network, the backend is running, and your firewall allows incoming connections on port `8080`. Then navigate to the `mobile` folder and run:
   ```bash
   cd mobile
   flutter run --dart-define=API_BASE_URL=http://192.168.1.4:8080
   ```
   Replace `192.168.1.4` with the appropriate address. The current default can also be overridden with `--dart-define=API_BASE_URL=http://YOUR_LOCAL_IP:8080`; you no longer need to edit the Dart source.

   **📱 Want to run it wirelessly (Untethered)?**
   Instead of using a USB cable, you can use Android's Wireless Debugging to hot-reload directly over Wi-Fi:
   1. On your phone, go to **Developer Options** and turn on **Wireless Debugging**.
   2. Tap "Wireless Debugging" -> **Pair device with pairing code**.
   3. On your PC terminal, run: `adb pair [IP_ADDRESS:PORT_SHOWN_ON_PHONE]` and enter the 6-digit code.
   4. Once paired, run: `adb connect [IP_ADDRESS:PORT_FOR_CONNECTION]`
   5. Run `flutter run` and unplug your cable! Your phone is now debugging wirelessly.

   *(Alternatively, run `flutter build apk` to build an untethered release version that you can install permanently).*

---

## 💻 Step 3: Web Dashboard Setup

The Next.js dashboard also needs to connect to the backend API.

1. **Update the API Endpoints:**
   Search for the IP address in the following files and replace it with your PC's Local IP address (the same one used for the mobile app):
   - `web/src/lib/api.ts`
   - `web/src/app/dashboard/page.tsx`
   - `web/src/components/DetailsModal.tsx`
2. **Install Dependencies & Run:**
   Navigate to the `web` folder:
   ```bash
   cd web
   npm install
   npm run dev
   ```
3. Open your browser to `http://localhost:3000`.

---

## 🧠 Managing the Legal Rule Repository (ChromaDB)
The AI's knowledge base (RAG) is powered by local ChromaDB. It currently stores all ingested legal metrology acts and SOPs.
If you need to ingest new PDF documents:
1. Place the PDFs in `backend/rag_documents/`.
2. Run the ingestion script inside the backend container:
   ```bash
   docker exec nirikshak-backend-vit python scripts/ingest_legal_docs.py
   ```

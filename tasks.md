# NIRIKSHAK AI - Engineering Task Backlog

## Feature: Nutrition Table & Ingredients Visual Cropping Engine

This backlog outlines the step-by-step engineering tasks to isolate the **Nutrition Facts Table** and **Ingredient Declaration Section** as high-resolution cropped images using zero-cost Vision LLMs with deterministic local fallbacks.

---

### Phase 1: Environment & API Configuration
- [x] **TASK-1.1**: Add `google-generativeai>=0.8.0` to `backend/requirements.txt` (or ensure compatibility with existing `groq==0.15.0`). *(Completed)*
- [x] **TASK-1.2**: Update `backend/app/core/config.py` with `gemini_api_key` configuration setting (optional with safe fallback). *(Completed)*
- [x] **TASK-1.3**: Update `.env.example` to document `GEMINI_API_KEY` (Free Tier from Google AI Studio). *(Completed)*

---

### Phase 2: Database Schema & Entity Updates
- [x] **TASK-2.1**: Update `backend/app/models/scan.py` to add:
  - `nutrition_table_image_url: Mapped[str | None] = mapped_column(String(512), nullable=True)`
  - `ingredients_image_url: Mapped[str | None] = mapped_column(String(512), nullable=True)`
  - `crop_metadata: Mapped[dict | None] = mapped_column(JSON, nullable=True)` *(Completed)*
- [x] **TASK-2.2**: Update `backend/app/schemas/scan.py` to expose cropped image URLs in `ScanBase` and `ScanRead`. *(Completed)*
- [ ] **TASK-2.3**: Check and create Alembic migration or ensure auto-sync for existing database instances.

---

### Phase 3: Core Region Cropper Service
- [x] **TASK-3.1**: Create `backend/app/services/extraction/panel_cropper.py`. *(Completed)*
- [x] **TASK-3.2**: Implement `PackagingRegionCropper` class with:
  - Google Gemini Flash (Free Tier) support.
  - Groq Llama 3.2 11B Vision (Free Tier) support.
  - Strict JSON schema for bounding box detection (`[ymin, xmin, ymax, xmax]` normalized to `0-1000`). *(Completed)*
- [x] **TASK-3.3**: Implement coordinate scaler and smart padding:
  - Coordinate scaling from normalized `0-1000` to actual pixel bounds `(H, W)`.
  - Dynamic context padding (3.5% - 5.0%) to prevent clipping text borders.
  - Image boundary clamping (`min 0`, `max W/H`). *(Completed)*
- [x] **TASK-3.4**: Implement image post-processing & saving:
  - High-quality JPEG export (`cv2.IMWRITE_JPEG_QUALITY, 95`).
  - Directory management for `/uploads/crops/nutrition/` and `/uploads/crops/ingredients/`. *(Completed)*
- [x] **TASK-3.5**: Implement deterministic local fallback (PaddleOCR keyword clustering):
  - Fallback trigger when VLM is unconfigured, rate-limited, or returns empty detections.
  - Anchor keyword search (`"nutrition"`, `"per 100g"`, `"ingredients"`, `"contains"`).
  - Bounding rectangle computation. *(Completed)*

---

### Phase 4: Pipeline & Multi-Angle Scan Orchestration
- [x] **TASK-4.1**: Integrate `PackagingRegionCropper` into `backend/app/services/pipeline.py`:
  - Panel prioritization order (`back -> left -> right -> front -> top -> bottom`).
  - Execute region detection on relevant panels during the scan workflow.
  - Persist generated crop URLs to the `Scan` record in the database.
  - Return `nutrition_table_image`, `ingredients_image`, and `crop_metadata` in pipeline result. *(Completed)*
- [x] **TASK-4.2**: Verify MinIO/local storage upload hook for cropped images (`/uploads/crops/nutrition` and `/uploads/crops/ingredients`). *(Completed)*

---

### Phase 5: API Endpoints & On-Demand Re-crop
- [x] **TASK-5.1**: Ensure existing `GET /api/v1/scans/{scan_id}` and `POST /api/v1/scans/{scan_id}/process` return `nutrition_table_image`, `ingredients_image`, and `crop_metadata`. *(Completed)*
- [x] **TASK-5.2**: Add on-demand endpoint `POST /api/v1/scans/{scan_id}/recrop-panels` for re-triggering cropping if needed on existing scans. *(Completed)*

---

### Phase 6: Front-End UI Display
- [x] **TASK-6.1**: Update Mobile `details_screen.dart` and `compliance_result_screen.dart`:
  - Visual thumbnail cards for "Nutrition Table" and "Ingredients Section" with zoom icons and status tags.
  - Interactive tap-to-zoom / full-screen inspection viewer (`FullScreenImageViewer`).
  - Interactive "Re-crop" action connecting directly to backend `POST /scans/{id}/recrop-panels`. *(Completed - Zero compile errors)*
- [ ] **TASK-6.2**: Web App Scan Details view *(Skipped per explicit user instruction: "dont make web dashborad")*.

---

### Phase 7: Verification & Testing
- [x] **TASK-7.1**: Unit test for `panel_cropper.py` with dummy/test packaging images (`backend/app/tests/test_panel_cropper.py`). *(Completed)*
- [x] **TASK-7.2**: Real packaging image test with Tomato Ketchup pouch (`1000093647.jpg`): verified extraction and cropping of `TOMATO KETCHUP INGREDIENTS` and `NUTRITIONAL FACTS` table. *(Completed - All 6 Pytest assertions passed)*
- [x] **TASK-7.3**: Real packaging image test with Oral Rehydration Salts sachet (`1000093645.jpg`): verified extraction and cropping of `ELECTROLYTES` table and `COMPOSITION` section. *(Completed - All 6 Pytest assertions passed)*


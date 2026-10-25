FROM python:3.11-slim

WORKDIR /app

# System dependencies for PaddleOCR and PDF processing
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libgl1 \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Install CPU-only PyTorch to reduce image size significantly
RUN pip install --default-timeout=100 torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

# Install Python dependencies
COPY requirements.txt .
RUN pip install --default-timeout=100 --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

EXPOSE 8080

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]

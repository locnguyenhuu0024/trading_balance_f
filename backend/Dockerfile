FROM python:3.12-slim
WORKDIR /app
RUN python -m pip install --no-cache-dir gunicorn
RUN python -m pip install --no-cache-dir typesafe-sdk==0.7.2

COPY backend /app/backend
USER 10001:10001
CMD ["gunicorn", "--workers", "1", "--bind", "0.0.0.0:8000", "backend.app:application"]

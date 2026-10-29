FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir fastapi uvicorn psycopg[binary]==3.2.9
COPY app.py /app/app.py
CMD ["uvicorn","app:api","--host","0.0.0.0","--port","8080"]

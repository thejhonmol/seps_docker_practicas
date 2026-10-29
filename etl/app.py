import csv
import io
import os
import re
import unicodedata
import zipfile
from datetime import datetime
from fastapi import FastAPI, HTTPException
import psycopg

api = FastAPI(title="SEPS ETL")
SOURCE = os.getenv("SOURCE_ZIP", "/data/2026-OEPS-MEN.zip")
DB = os.environ["DATABASE_URL"]
COLUMNS = ["fecha_corte", "estado_juridico", "sector", "tipo", "grupo", "clase",
           "subclase", "provincia", "canton", "parroquia", "numero_organizaciones",
           "codigo_parroquia", "razon_social", "ruc"]
INSERT = """INSERT INTO seps.organizaciones
 (fecha_corte,estado_juridico,sector,tipo,grupo,clase,subclase,provincia,canton,parroquia,
 numero_organizaciones,codigo_parroquia,razon_social,ruc)
 VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
 ON CONFLICT (fecha_corte,ruc) DO UPDATE SET
 razon_social=excluded.razon_social, estado_juridico=excluded.estado_juridico,
 sector=excluded.sector,tipo=excluded.tipo,grupo=excluded.grupo,clase=excluded.clase,
 subclase=excluded.subclase,provincia=excluded.provincia,canton=excluded.canton,
 parroquia=excluded.parroquia,numero_organizaciones=excluded.numero_organizaciones,
 codigo_parroquia=excluded.codigo_parroquia,actualizado=now()"""

def tidy(v):
    return re.sub(r"\s+", " ", (v or "").strip()).upper()

def normalized(row):
    if len(row) != len(COLUMNS):
        raise ValueError(f"columnas incorrectas: {len(row)}")
    x = dict(zip(COLUMNS, row))
    ruc = x["ruc"].strip()
    if not re.fullmatch(r"\d{13}", ruc):
        raise ValueError("RUC inválido")
    try:
        # SEPS uses dates such as 2026-1-31 (not strictly zero-padded ISO).
        fecha = datetime.strptime(x["fecha_corte"].strip(), "%Y-%m-%d").date()
    except ValueError:
        raise ValueError("fecha inválida")
    if not x["razon_social"].strip():
        raise ValueError("razón social vacía")
    return [fecha] + [tidy(x[k]) for k in COLUMNS[1:10]] + [
        int(x["numero_organizaciones"]), x["codigo_parroquia"].strip(),
        re.sub(r"\s+", " ", x["razon_social"].strip()), ruc
    ]

@api.get("/health")
def health():
    with psycopg.connect(DB) as conn:
        conn.execute("SELECT 1").fetchone()
    return {"status": "ok"}

@api.post("/run")
def run():
    if not os.path.isfile(SOURCE):
        raise HTTPException(404, f"Archivo ZIP no encontrado: {SOURCE}")
    with psycopg.connect(DB) as conn:
        run_id = conn.execute(
            "INSERT INTO seps.importaciones(origen) VALUES (%s) RETURNING id",
            ("SEPS Organizaciones 2026",)).fetchone()[0]
        counts = {"read": 0, "valid": 0, "rejected": 0}
        batch = []
        with zipfile.ZipFile(SOURCE) as z:
            with z.open("2026.txt") as source:
                reader = csv.reader(io.TextIOWrapper(source, encoding="utf-8-sig", newline=""), delimiter="\t")
                next(reader, None)
                for number, row in enumerate(reader, start=2):
                    counts["read"] += 1
                    try:
                        batch.append(normalized(row))
                        counts["valid"] += 1
                    except (ValueError, TypeError) as exc:
                        counts["rejected"] += 1
                        conn.execute("INSERT INTO seps.rechazos(importacion_id,fila,motivo,raw) VALUES(%s,%s,%s,%s)",
                                     (run_id, number, str(exc), str(row)[:3000]))
                    if len(batch) >= 1000:
                        with conn.cursor() as cursor:
                            cursor.executemany(INSERT, batch)
                        conn.commit()
                        batch.clear()
                if batch:
                    with conn.cursor() as cursor:
                        cursor.executemany(INSERT, batch)
        conn.execute("""UPDATE seps.importaciones SET finalizado=now(),registros_leidos=%s,
        registros_validos=%s,registros_rechazados=%s,estado='finalizada' WHERE id=%s""",
                     (counts["read"],counts["valid"],counts["rejected"],run_id))
        conn.commit()
    return {"importacion_id":run_id, **counts, "status":"ok"}

"""Atomic import with a durable run log and per-cell source provenance."""
import os
from pathlib import Path
from fastapi import FastAPI, HTTPException
import psycopg
from parser import FIELDS, read_zip, sha256

api = FastAPI(title='SEPS boletines financieros')
SOURCE = os.getenv('SOURCE_ZIP', '/data/2026-EEFF-MEN.zip')


def connect():
    # Separate parameters support passwords containing URL-reserved characters.
    return psycopg.connect(host=os.getenv('PGHOST', 'postgres'),
                          dbname=os.getenv('PGDATABASE', 'seps'),
                          user=os.getenv('PGUSER', 'seps'),
                          password=os.environ['PGPASSWORD'])


@api.get('/health')
def health():
    with connect() as conn:
        ready = conn.execute("SELECT to_regclass('seps_fin.valores') IS NOT NULL").fetchone()[0]
    if not ready:
        raise HTTPException(503, 'Aplicar sql/01_schema.sql antes de importar')
    return {'status': 'ok', 'source_available': Path(SOURCE).is_file()}


@api.post('/run')
def run():
    if not Path(SOURCE).is_file():
        raise HTTPException(404, 'Copiar 2026-EEFF-MEN.zip a data/; ver README')
    fingerprint = sha256(SOURCE)
    with connect() as conn:
        if not conn.execute('SELECT pg_try_advisory_lock(20260930)').fetchone()[0]:
            raise HTTPException(409, 'Ya hay una importación financiera en curso')
        run_id = conn.execute('INSERT INTO seps_fin.importaciones(origen,sha256) VALUES(%s,%s) RETURNING id',
                              (Path(SOURCE).name, fingerprint)).fetchone()[0]
        conn.commit()
        counts = dict(read=0, valid=0, observed=0)
        try:
            # Transaction rollback preserves the last good dataset on any structural failure.
            with conn.transaction():
                conn.execute('CREATE TEMP TABLE stage (LIKE seps_fin.valores INCLUDING DEFAULTS) ON COMMIT DROP')
                conn.execute('CREATE TEMP TABLE notes(archivo TEXT,hoja TEXT,celda TEXT,motivo TEXT) ON COMMIT DROP')
                notes = []
                with conn.cursor() as cur:
                    with cur.copy('COPY stage (' + ','.join(FIELDS) + ',importacion_id) FROM STDIN') as copy:
                        for r in read_zip(SOURCE):
                            counts['read'] += 1
                            counts['valid' if r['estado']=='valido' else 'observed'] += 1
                            copy.write_row(tuple(r[k] for k in FIELDS) + (run_id,))
                            if r['estado'] != 'valido':
                                notes.append((r['archivo'], r['hoja'], r['celda'], r['motivo']))
                    with cur.copy('COPY notes FROM STDIN') as copy:
                        for note in notes:
                            copy.write_row(note)
                if not counts['valid']:
                    raise ValueError('La fuente no contiene valores numéricos válidos')
                if sha256(SOURCE) != fingerprint:
                    raise ValueError('La fuente cambió durante la lectura; repetir con un ZIP estable')
                # Replace only group-period slices represented by the validated source.
                conn.execute('''DELETE FROM seps_fin.valores v USING
                  (SELECT DISTINCT fecha_corte,segmento FROM stage) s
                  WHERE v.fecha_corte=s.fecha_corte AND v.segmento=s.segmento''')
                conn.execute('INSERT INTO seps_fin.valores SELECT * FROM stage')
                conn.execute('''INSERT INTO seps_fin.observaciones(importacion_id,archivo,hoja,celda,motivo)
                                SELECT %s,archivo,hoja,celda,motivo FROM notes''', (run_id,))
                conn.execute('''UPDATE seps_fin.importaciones SET finalizado=now(),estado='finalizada',
                  registros_leidos=%s,registros_validos=%s,registros_observados=%s WHERE id=%s''',
                  (counts['read'],counts['valid'],counts['observed'],run_id))
        except Exception as exc:
            conn.rollback()
            conn.execute("UPDATE seps_fin.importaciones SET estado='fallida',finalizado=now(),error=%s WHERE id=%s",
                         (str(exc)[:2000],run_id))
            conn.commit()
            raise HTTPException(422, f'Importación {run_id} fallida; revisar seps_fin.importaciones') from exc
        finally:
            conn.execute('SELECT pg_advisory_unlock(20260930)')
            conn.commit()
    return dict(importacion_id=run_id, status='ok', sha256=fingerprint, **counts)

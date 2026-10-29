"""Offline audit: python etl/audit_source.py data/2026-EEFF-MEN.zip --output reportes/auditoria_fuente.json"""
import argparse
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
from parser import read_zip, sha256


def audit(path):
    states = Counter()
    kinds = Counter()
    periods = defaultdict(set)
    entities = defaultdict(set)
    assets = defaultdict(Decimal)
    totals = {}
    keys = set()
    examples = []
    for r in read_zip(path):
        key = tuple(r[k] for k in ('fecha_corte', 'segmento', 'entidad', 'tipo', 'codigo'))
        if key in keys:
            raise ValueError(f'Clave duplicada: {key}')
        keys.add(key)
        states[r['estado']] += 1
        kinds[r['tipo']] += 1
        periods[r['segmento']].add(r['fecha_corte'])
        if not r['es_total']:
            entities[r['segmento']].add(r['entidad'])
        if r['estado'] != 'valido' and len(examples) < 10:
            examples.append({k: str(v) for k, v in r.items()})
        if r['tipo'] == 'cuenta' and r['codigo'] == '1' and r['valor'] is not None:
            k = (r['fecha_corte'], r['segmento'])
            if r['es_total']:
                totals[k] = r['valor']
            else:
                assets[k] += r['valor']
    checks = [dict(fecha_corte=p, segmento=g, suma_entidades=str(assets[p,g]),
                   total_publicado=str(v), diferencia=str(assets[p,g]-v),
                   coincide=abs(assets[p,g]-v) < Decimal('0.01')) for (p,g),v in totals.items()]
    return dict(archivo=Path(path).name, sha256=sha256(path),
                celdas=len(keys), estados=dict(states), tipos=dict(kinds),
                entidades_por_grupo={k:len(v) for k,v in entities.items()},
                periodos_por_grupo={k:sorted(v) for k,v in periods.items()},
                conciliacion_activos=checks, ejemplos_no_validos=examples,
                alcance='Lectura de valores guardados de hojas 2 y 5; no ejecuta macros ni valida Docker, PostgreSQL, n8n o Metabase.')

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('source')
    p.add_argument('--output')
    a = p.parse_args()
    result = json.dumps(audit(a.source), ensure_ascii=False, indent=2)
    if a.output:
        Path(a.output).write_text(result + '\n', encoding='utf-8')
    print(result)

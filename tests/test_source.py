"""Optional integration with the actual attachment: SOURCE_ZIP=/path/file.zip python -m unittest discover -s tests -v"""
import os
import sys
import unittest
from collections import Counter
from decimal import Decimal
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'etl'))
from parser import read_zip, sha256

@unittest.skipUnless(os.getenv('SOURCE_ZIP'), 'Definir SOURCE_ZIP para verificar la fuente real')
class SourceTests(unittest.TestCase):
    def test_uploaded_bundle_and_known_source_cells(self):
        path=os.environ['SOURCE_ZIP']
        self.assertEqual(sha256(path),'bbf11db7bfc043ad852e770a7eba013e84e5bf210c630a24f31572651628dc0b')
        counts=Counter()
        samples={}
        keys=set()
        for r in read_zip(path):
            counts[r['estado']]+=1
            key=tuple(r[k] for k in ('fecha_corte','segmento','entidad','tipo','codigo'))
            self.assertNotIn(key,keys)
            keys.add(key)
            if r['tipo']=='cuenta' and r['codigo']=='1' and r['fecha_corte']=='2026-09-30':
                samples[(r['segmento'],r['entidad'])]=r['valor']
        self.assertEqual(counts,dict(valido=263703,sin_dato=18238,error_excel=9))
        self.assertEqual(len(keys),281950)
        self.assertEqual(samples['CONAFIPS','CORPORACION NACIONAL DE FINANZAS POPULARES Y SOLIDARIAS'],Decimal('659036431.9'))
        self.assertEqual(samples['FINANCOOP','CAJA CENTRAL FINANCOOP'],Decimal('647426702.85'))
        self.assertEqual(samples['Mutualistas','AMBATO'],Decimal('101745255.66'))
        self.assertEqual(samples['Segmento 1','15 DE ABRIL LTDA'],Decimal('138832182.3'))

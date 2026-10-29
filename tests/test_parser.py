import sys
import unittest
from datetime import datetime
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'etl'))
from parser import numeric, parse_sheet

# Lightweight in-memory input; no workbook authoring required.
class Sheet:
    title = '2. ESTADO FINANCIERO'
    def __init__(self, rows, formats=None):
        self.rows = rows
        self.formats = formats or {}
    def iter_rows(self, min_row=1, max_row=None, max_col=None):
        width = max_col or max(map(len,self.rows))
        for i in range(min_row-1,min(max_row or len(self.rows),len(self.rows))):
            result=[]
            for j in range(width):
                value = self.rows[i][j] if j<len(self.rows[i]) else None
                result.append(SimpleNamespace(value=value,row=i+1,column=j+1,
                    coordinate=f'R{i+1}C{j+1}',number_format=self.formats.get((i+1,j+1),'General'),
                    data_type='e' if isinstance(value,str) and value.startswith('#') else 'n'))
            yield result

class ParserTests(unittest.TestCase):
    def test_dates_totals_and_account_levels(self):
        sheet=Sheet([[None]*4+[datetime(2026,9,30)],
          ['COD CONTABLE','Nombre','TIPO','GRUPO','Entidad A','VT_TOTAL SEGMENTO 1'],
          [1,'ACTIVO',1,1,100,100],[11,'FONDOS',1,2,20,20]])
        rows=list(parse_sheet(sheet,'Segmento 1','test.xlsm','cuenta'))
        self.assertEqual(len(rows),4)
        self.assertEqual(rows[1]['fecha_corte'],'2026-09-30')
        self.assertTrue(rows[1]['es_total'])
        self.assertEqual(rows[2]['codigo'],'11')
        self.assertEqual(rows[0]['valor'],Decimal('100'))
    def test_months_not_forward_filled_over_explicit_dates(self):
        sheet=Sheet([[None]*4+[datetime(2026,1,31),datetime(2026,2,28)],
          [None]*4+['ENTIDAD','ENTIDAD'],[1,'ACTIVO',1,1,0,None]])
        rows=list(parse_sheet(sheet,'CONAFIPS','test.xlsm','cuenta'))
        self.assertEqual([r['fecha_corte'] for r in rows],['2026-01-31','2026-02-28'])
        self.assertEqual(rows[0]['estado'],'valido')
        self.assertEqual(rows[0]['valor'],0)
        self.assertEqual(rows[1]['estado'],'sin_dato')
        self.assertIsNone(rows[1]['valor'])
    def test_indicators_errors_and_percent_scale(self):
        sheet=Sheet([[None,datetime(2026,9,30)], [None,'A','B'],
                     ['LIQUIDEZ'],['TASA',.12,'#NULL!']], {(4,2):'0.00%',(4,3):'0.00%'})
        rows=list(parse_sheet(sheet,'Segmento 1','test.xlsm','indicador'))
        self.assertEqual(len(rows),2)
        self.assertEqual(rows[0]['valor'],Decimal('.12'))
        self.assertEqual(rows[0]['unidad'],'proporcion')
        self.assertEqual(rows[1]['estado'],'error_excel')
        self.assertIsNone(rows[1]['valor'])
    def test_duplicate_source_key_fails(self):
        sheet=Sheet([[None]*4+[datetime(2026,9,30)], [None]*4+['A'],
                     [1,'ACTIVO',1,1,10],[1,'ACTIVO',1,1,20]])
        with self.assertRaisesRegex(ValueError,'duplicada'):
            list(parse_sheet(sheet,'Segmento 1','test.xlsm','cuenta'))
    def test_unknown_layout_fails(self):
        with self.assertRaisesRegex(ValueError,'fechas'):
            list(parse_sheet(Sheet([['sin fechas']]),'Segmento 1','test.xlsm','cuenta'))
    def test_nonfinite_rejected(self):
        for val in ('NaN','Infinity',True,'texto'):
            with self.assertRaises(ValueError):numeric(val)

if __name__=='__main__':unittest.main()

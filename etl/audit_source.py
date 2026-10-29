"""Offline quality audit of the official SEPS tab-separated file."""
import csv
import re
from collections import Counter
from pathlib import Path

path = Path(__file__).resolve().parent.parent / 'data' / '2026.txt'
with path.open(encoding='utf-8-sig', newline='') as handle:
    reader = csv.reader(handle, delimiter='\t')
    headers = next(reader)
    count = invalid = duplicates = empty_name = 0
    months = Counter()
    keys = set()
    for row in reader:
        count += 1
        if len(row) != 14:
            invalid += 1
            continue
        months[row[0]] += 1
        if not re.fullmatch(r'\d{13}', row[-1].strip()):
            invalid += 1
        if not row[-2].strip():
            empty_name += 1
        key = row[0], row[-1]
        if key in keys:
            duplicates += 1
        keys.add(key)
print({'headers': len(headers), 'rows': count, 'invalid_ruc_or_length': invalid,
       'empty_name': empty_name, 'duplicates_date_ruc': duplicates,
       'months': dict(months)})

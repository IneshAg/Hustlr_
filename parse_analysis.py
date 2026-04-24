import collections

path = 'analysis_output_v3.txt'
counts = collections.Counter()
errors = []

encodings = ['utf-16', 'utf-8', 'cp1252']
lines = []

for enc in encodings:
    try:
        with open(path, 'r', encoding=enc) as f:
            lines = f.readlines()
        break
    except Exception:
        continue

for line in lines:
    if ' - ' in line:
        parts = line.strip().split(' - ')
        if len(parts) >= 2:
            type_prefix = parts[0].strip().split(' ')[0]
            counts[type_prefix] += 1
            if type_prefix == 'error':
                errors.append(line.strip())

print(f"Counts: {dict(counts)}")
print(f"Total entries parsed: {len(lines)}")
print("\nTop 20 Errors:")
for e in errors[:20]:
    print(e)

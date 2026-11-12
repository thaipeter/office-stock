import re, html, sys, json, collections, datetime
src, out = sys.argv[1], sys.argv[2]
def rows(f):
    t = open(f"{src}/{f}", encoding="utf-8").read()
    return [[html.unescape(re.sub(r'<[^>]+>', '', x)).strip()
             for x in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', r, re.S)]
            for r in re.findall(r'<tr[^>]*>(.*?)</tr>', t, re.S)]
q = lambda s: "'" + s.replace("'", "''") + "'"
num = lambda s: re.sub(r'[^0-9.\-]', '', s) or '0'
items, seen = [], set()
for r in rows('Items.html')[3:]:
    if len(r) < 7 or not r[1] or r[1] in seen: continue
    seen.add(r[1]); items.append(r)
tx = []
for r in rows('Transactions.html')[3:]:
    if len(r) < 6 or not r[1]: continue
    # columns: 0 row#, 1 time, 2 type, 3 code, 4 name, 5 qty, 6 recorder, 7 dept, 8 note
    d, t = r[1].split(', ')
    dd, mm, yy = d.split('/')
    ts = f"{yy}-{int(mm):02d}-{int(dd):02d} {t}+07"
    typ = {'เบิกออก': 'OUT', 'รับเข้า': 'IN', 'เพิ่มสินค้าใหม่': 'NEW'}.get(r[2].split(' (')[0])
    g = lambda i: r[i] if len(r) > i else ''
    tx.append((ts, typ, r[3], g(6), g(7), g(8), num(r[5]), r[5]))
bad = [t for t in tx if t[1] is None or t[2] not in seen]
print('items', len(items), 'tx', len(tx), 'bad', bad[:5], file=sys.stderr)
o = ["-- seed generated from the exported sheets; triggers disabled so stored qty is kept as exported",
     "alter table public.movements disable trigger trg_apply_movement;",
     "insert into public.items(code,name,qty,unit,min_qty,category) values"]
o.append(",\n".join(f"({q(r[1])},{q(r[2])},{num(r[3])},{q(r[4])},{num(r[5])},{q(r[6])})" for r in items) + "\non conflict (code) do nothing;")
o.append("insert into public.movements(ts,type,code,qty,actor,dept,note) values")
o.append(",\n".join(f"({q(t[0])},{q(t[1])},{q(t[2])},{t[6]},{q(t[3])},{q(t[4])},{q(t[5])})" for t in tx if t[1] and t[2] in seen) + ";")
o.append("alter table public.movements enable trigger trg_apply_movement;")
open(out, 'w', encoding='utf-8').write("\n".join(o) + "\n")

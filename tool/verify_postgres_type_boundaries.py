"""Schema-aware guard against PostgreSQL text/UUID comparison regressions."""
from __future__ import annotations
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
MIG = ROOT / 'supabase' / 'migrations'
RESERVED={'where','set','on','for','left','right','inner','outer','full','cross','join','using','order','group','limit','returning','and','or','loop','into','values'}

# Simple top-level SQL scanner skipping comments/strings/dollar bodies.
def code_matches(text, pattern):
    rx=re.compile(pattern,re.I|re.S)
    i=0;n=len(text)
    while i<n:
        if text.startswith('--',i):
            j=text.find('\n',i+2);i=n if j<0 else j+1;continue
        if text.startswith('/*',i):
            j=text.find('*/',i+2);i=n if j<0 else j+2;continue
        c=text[i]
        if c=="'":
            i+=1
            while i<n:
                if text[i]=="'":
                    if i+1<n and text[i+1]=="'":i+=2;continue
                    i+=1;break
                i+=1
            continue
        if c=='"':
            i+=1
            while i<n:
                if text[i]=='"':
                    if i+1<n and text[i+1]=='"':i+=2;continue
                    i+=1;break
                i+=1
            continue
        m=re.match(r'\$[A-Za-z0-9_]*\$',text[i:])
        if m:
            tag=m.group(0);j=text.find(tag,i+len(tag));i=n if j<0 else j+len(tag);continue
        m=rx.match(text,i)
        if m:
            yield m
            i=m.end();continue
        i+=1

def split_top(s, delim=','):
    out=[];st=0;d=0;q=None;dt=None;i=0
    while i<len(s):
        if dt:
            if s.startswith(dt,i):i+=len(dt);dt=None
            else:i+=1
            continue
        c=s[i]
        if q:
            if c==q:
                if i+1<len(s) and s[i+1]==q:i+=2;continue
                q=None
            i+=1;continue
        if c in "'\"":q=c;i+=1;continue
        m=re.match(r'\$[A-Za-z0-9_]*\$',s[i:])
        if m:dt=m.group(0);i+=len(dt);continue
        if c=='(':d+=1
        elif c==')':d=max(0,d-1)
        elif c==delim and d==0:out.append(s[st:i].strip());st=i+1
        i+=1
    if s[st:].strip():out.append(s[st:].strip())
    return out

def find_balanced(text,start,open='(',close=')'):
    d=1;q=None;dt=None;i=start
    while i<len(text) and d:
        if dt:
            if text.startswith(dt,i):i+=len(dt);dt=None
            else:i+=1
            continue
        c=text[i]
        if q:
            if c==q:
                if i+1<len(text) and text[i+1]==q:i+=2;continue
                q=None
            i+=1;continue
        if c in "'\"":q=c;i+=1;continue
        m=re.match(r'\$[A-Za-z0-9_]*\$',text[i:])
        if m:dt=m.group(0);i+=len(dt);continue
        if c==open:d+=1
        elif c==close:d-=1
        i+=1
    return i

def find_stmt_end(text,start):
    q=None;dt=None;i=start
    while i<len(text):
        if text.startswith('--',i):
            j=text.find('\n',i+2);i=len(text) if j<0 else j+1;continue
        if text.startswith('/*',i):
            j=text.find('*/',i+2);i=len(text) if j<0 else j+2;continue
        if dt:
            if text.startswith(dt,i):i+=len(dt);dt=None
            else:i+=1
            continue
        c=text[i]
        if q:
            if c==q:
                if i+1<len(text) and text[i+1]==q:i+=2;continue
                q=None
            i+=1;continue
        if c in "'\"":q=c;i+=1;continue
        m=re.match(r'\$[A-Za-z0-9_]*\$',text[i:])
        if m:dt=m.group(0);i+=len(dt);continue
        if c==';':return i+1
        i+=1
    return len(text)

def canon_type(t):
    t=re.sub(r'\s+',' ',t.strip().lower())
    if t in {'text','character varying','varchar','citext','character'} or t.startswith('varchar('):return 'text'
    if t=='uuid':return 'uuid'
    return t

schema={}
create_table_pat=r'create\s+table\s+(?:if\s+not\s+exists\s+)?((?:public\.)?[a-z_][a-z0-9_]*)\s*\('
alter_add_pat=r'alter\s+table\s+(?:if\s+exists\s+)?((?:public\.)?[a-z_][a-z0-9_]*)\s+add\s+column\s+(?:if\s+not\s+exists\s+)?([a-z_][a-z0-9_]*)\s+([a-z][a-z0-9_ ]*)'
for mf in sorted(MIG.glob('*.sql')):
    text=mf.read_text(encoding='utf-8', errors='replace')
    for m in code_matches(text,create_table_pat):
        table=m.group(1).lower();table=table if '.' in table else 'public.'+table
        end=find_balanced(text,m.end())
        cols=schema.setdefault(table,{})
        for item in split_top(text[m.end():end-1]):
            mm=re.match(r'\s*"?([a-z_][a-z0-9_]*)"?\s+([a-z][a-z0-9_]*(?:\s+varying)?(?:\s*\([^)]*\))?)',item,re.I)
            if not mm or mm.group(1).lower() in {'primary','foreign','unique','check','constraint','exclude'}:continue
            cols[mm.group(1).lower()]=canon_type(mm.group(2))
    for m in code_matches(text,alter_add_pat):
        table=m.group(1).lower();table=table if '.' in table else 'public.'+table
        schema.setdefault(table,{})[m.group(2).lower()]=canon_type(m.group(3))

# Extract active functions.
create_func_pat=r'create\s+(?:or\s+replace\s+)?function\s+((?:public\.)?[a-z_][a-z0-9_]*)\s*\('
drop_func_pat=r'drop\s+function\s+(?:if\s+exists\s+)?((?:public\.)?[a-z_][a-z0-9_]*)\s*\('
active={}
for mf in sorted(MIG.glob('*.sql')):
    text=mf.read_text(encoding='utf-8', errors='replace')
    events=[]
    for m in code_matches(text,create_func_pat):events.append((m.start(),'create',m))
    for m in code_matches(text,drop_func_pat):events.append((m.start(),'drop',m))
    for _,kind,m in sorted(events):
        name=m.group(1).lower();name=name if '.' in name else 'public.'+name
        endargs=find_balanced(text,m.end())
        argtxt=text[m.end():endargs-1]
        args=[]
        for raw in split_top(argtxt):
            raw=re.split(r'\s+default\s+|\s*=\s*',raw,flags=re.I)[0].strip()
            tok=raw.split();mode='in'
            if tok and tok[0].lower() in {'in','out','inout','variadic'}:mode=tok.pop(0).lower()
            an=''
            if len(tok)>=2 and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',tok[0]):an=tok.pop(0).lower()
            at=canon_type(' '.join(tok))
            if mode!='out':args.append((an,at))
        sig=tuple(t for _,t in args)
        if kind=='drop':active.pop((name,sig),None);continue
        end=find_stmt_end(text,endargs)
        active[(name,sig)]=(mf.name,text[m.start():end],args)

issues=[]
for (fname,sig),(file,stmt,args) in active.items():
    typed={n:t for n,t in args if n}
    # body text between first dollar tags
    dm=re.search(r'\bas\s+(\$[A-Za-z0-9_]*\$)',stmt,re.I)
    body=stmt
    if dm:
        tag=dm.group(1);st=dm.end();en=stmt.find(tag,st);body=stmt[st:en if en>=0 else None]
    decl=re.search(r'\bdeclare\b(.*?)\bbegin\b',body,re.I|re.S)
    if decl:
        for piece in decl.group(1).split(';'):
            mm=re.match(r'\s*([a-z_][a-z0-9_]*)\s+([a-z_][a-z0-9_]*(?:\s+varying)?)',piece,re.I)
            if mm:typed[mm.group(1).lower()]=canon_type(mm.group(2))
    uuid_names=[n for n,t in typed.items() if t=='uuid']
    text_names=[n for n,t in typed.items() if t=='text']
    # JSON ->> is text, cannot compare directly to uuid identifiers.
    for n in uuid_names:
        pats=[rf"(?:->>|#>>)\s*'[^']+'\s*=\s*{re.escape(n)}\b(?!\s*::\s*text)",rf"\b{re.escape(n)}\b(?!\s*::\s*text)\s*=\s*[^;\n]{{0,80}}(?:->>|#>>)\s*'[^']+'"]
        for pat in pats:
            if re.search(pat,body,re.I):issues.append((fname,file,'json-text-vs-uuid',n,re.search(pat,body,re.I).group(0)))
    # Process semicolon-ish pieces for table comparisons.
    for seg in body.split(';'):
        aliases={}
        for mm in re.finditer(r'\b(?:from|join|update|delete\s+from)\s+((?:public\.)?[a-z_][a-z0-9_]*)(?:\s+(?:as\s+)?([a-z_][a-z0-9_]*))?',seg,re.I):
            table=mm.group(1).lower();table=table if '.' in table else 'public.'+table
            alias=(mm.group(2) or table.split('.')[-1]).lower()
            if alias in RESERVED:alias=table.split('.')[-1]
            aliases[alias]=table;aliases[table.split('.')[-1]]=table
        for alias,table in list(aliases.items()):
            cols=schema.get(table,{})
            for col,ctype in cols.items():
                for n,ntype in typed.items():
                    if {ctype,ntype}!={'text','uuid'}:continue
                    # explicit alias.column
                    patterns=[rf'\b{re.escape(alias)}\s*\.\s*{re.escape(col)}\s*=\s*\b{re.escape(n)}\b(?!\s*::\s*(?:text|uuid))',rf'\b{re.escape(n)}\b(?!\s*::\s*(?:text|uuid))\s*=\s*\b{re.escape(alias)}\s*\.\s*{re.escape(col)}\b']
                    # unqualified only if one unique table in segment
                    if len(set(aliases.values()))==1:
                        patterns += [rf'(?<!\.)\b{re.escape(col)}\s*=\s*\b{re.escape(n)}\b(?!\s*::\s*(?:text|uuid))',rf'\b{re.escape(n)}\b(?!\s*::\s*(?:text|uuid))\s*=\s*(?<!\.)\b{re.escape(col)}\b']
                    for pat in patterns:
                        mm=re.search(pat,seg,re.I)
                        if mm:issues.append((fname,file,f'{table}.{col}:{ctype}-vs-{ntype}',n,mm.group(0)))

# Report unique issues and fail the default project gate.
seen: set[tuple[str, str, str, str, str]] = set()
unique_issues: list[tuple[str, str, str, str, str]] = []
for issue in issues:
    if issue in seen:
        continue
    seen.add(issue)
    unique_issues.append(issue)

required_migration = MIG / '20260803090000_postgres_type_boundary_hardening.sql'
if not required_migration.is_file():
    unique_issues.append((
        'migration-history',
        required_migration.name,
        'missing-type-boundary-hardening',
        '',
        'The forward repair migration is missing.',
    ))
else:
    hardening_sql = required_migration.read_text(encoding='utf-8', errors='replace').lower()
    for required in (
        'erp_legacy_company_keys',
        'r.company_id=any(public.erp_legacy_company_keys(p_company_id))',
        'create or replace function public.erp_delete_cloud_purchase',
    ):
        if required not in hardening_sql:
            unique_issues.append((
                'migration-history',
                required_migration.name,
                'incomplete-type-boundary-hardening',
                '',
                required,
            ))

if unique_issues:
    print('FAIL PostgreSQL text/UUID type-boundary verification')
    for function_name, migration_name, issue_type, identifier, expression in unique_issues:
        detail = f' [{identifier}]' if identifier else ''
        print(f'  - {function_name} ({migration_name}): {issue_type}{detail}: {expression}')
    raise SystemExit(1)

print('PASS PostgreSQL text/UUID type-boundary verification')
print(f'  - {len(active)} active function signatures inspected')
print(f'  - {len(schema)} table schemas inspected')
print('  - legacy text columns cannot be compared directly with UUID parameters or variables')
print('  - JSON text extraction cannot be compared directly with UUID parameters or variables')
print('  - erp_records company matching uses one explicit UUID-to-legacy-key boundary')

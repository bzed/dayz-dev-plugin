#!/usr/bin/env python3
"""Look up the vanilla DayZ script API from the bundled compressed index (api/dayz-api.txt.xz).

  dayz-api.py class NAME [--inherited]   members of a class (--inherited: also every base class)
  dayz-api.py find REGEX [-c CLASS]      member lines matching REGEX (case-insensitive), with their class
  dayz-api.py sub NAME [--all]           classes extending NAME (--all: transitively)
  dayz-api.py enum NAME                  enum values; `find` also searches enum values and top-level declarations
  dayz-api.py src NAME                   source files declaring a class/enum, with ready `armake2 cat` commands
  dayz-api.py chain NAME                 base class chain

Output is capped at --max lines (default 120). Run `dayz-api.py class X` before relying on a method.
"""
import argparse, lzma, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
INDEX = os.path.join(HERE, '..', 'api', 'dayz-api.txt.xz')


def load():
    blocks, cur = {}, None
    head = []
    with lzma.open(INDEX, 'rt', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if line.startswith('#'):
                head.append(line)
            elif line.startswith(('CLASS ', 'ENUM ')):
                kind, rest = line.split(' ', 1)
                name = re.match(r'\w+', rest).group(0)
                cur = blocks.setdefault((kind, name), {'head': line, 'lines': []})
            elif line in ('TYPEDEF', 'FN', 'VAR'):
                cur = blocks.setdefault(('TOP', line), {'head': line, 'lines': []})
            elif cur is not None and line:
                cur['lines'].append(line)
    return head, blocks


def base_of(b):
    m = re.search(r' : ([\w.]+)', b['head'])
    return m.group(1) if m else None


LAYER = {'1': '1_Core', '2': '2_GameLib', '3': '3_Game', '4': '4_World', '5': '5_Mission'}


def files_of(head):
    return re.findall(r' @(\d):(\S+)', head)


def brief(head):
    """Header without the file list, only the layers (use `src` for the files)."""
    fl = files_of(head)
    if not fl:
        return head
    return head.split(' @')[0] + ' @' + ','.join(sorted({l for l, _ in fl}))


def inner(layer, path):
    return LAYER[layer] + '\\' + path.replace('/', '\\')


def emit(lines, cap):
    for n, l in enumerate(lines):
        if n >= cap:
            print(f'... {len(lines) - cap} more lines (raise --max or narrow the query)')
            return
        print(l)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('cmd', choices=['class', 'find', 'sub', 'enum', 'chain', 'src'])
    ap.add_argument('arg')
    ap.add_argument('--inherited', action='store_true')
    ap.add_argument('--all', action='store_true')
    ap.add_argument('-c', '--cls')
    ap.add_argument('--max', type=int, default=120)
    a = ap.parse_args()
    head, blocks = load()
    out = []
    if a.cmd == 'class':
        name = a.arg
        seen = set()
        while name and name not in seen and ('CLASS', name) in blocks:
            seen.add(name)
            b = blocks[('CLASS', name)]
            out.append(brief(b['head']))
            out.extend(b['lines'])
            if not a.inherited:
                break
            name = base_of(b)
        if not out:
            sys.exit(f'no class {a.arg!r}; try: dayz-api.py find {a.arg}')
    elif a.cmd == 'src':
        b = blocks.get(('CLASS', a.arg)) or blocks.get(('ENUM', a.arg))
        if not b:
            sys.exit(f'no class or enum {a.arg!r}')
        out.append('pbo: <DayZ install>/dta/scripts.pbo  (print one file: armake2 cat <pbo> \'<path>\')')
        for l, pth in files_of(b['head']):
            out.append(inner(l, pth))
    elif a.cmd == 'chain':
        name, seen = a.arg, []
        while name and name not in seen and ('CLASS', name) in blocks:
            seen.append(name)
            name = base_of(blocks[('CLASS', name)])
        out.append(' > '.join(seen + ([name] if name and name not in seen else [])))
    elif a.cmd == 'sub':
        kids = {}
        for (k, n), b in blocks.items():
            if k == 'CLASS' and base_of(b):
                kids.setdefault(base_of(b), []).append(n)
        todo, found = [a.arg], []
        while todo:
            for k in sorted(kids.get(todo.pop(0), [])):
                found.append(k)
                if a.all:
                    todo.append(k)
        out.append(' '.join(found) or f'no subclasses of {a.arg}')
    elif a.cmd == 'enum':
        b = blocks.get(('ENUM', a.arg))
        if not b:
            sys.exit(f'no enum {a.arg!r}')
        out = [brief(b['head'])] + b['lines']
    else:
        rx = re.compile(a.arg, re.I)
        for (k, n), b in sorted(blocks.items()):
            if a.cls and n != a.cls:
                continue
            if k == 'CLASS' and rx.search(n):
                out.append(brief(b['head']))
            for l in b['lines']:
                if rx.search(l):
                    out.append(f'{n}: {l.strip()}' if k != 'TOP' else f'{n.lower()}: {l.strip()}')
    emit(out, a.max)


if __name__ == '__main__':
    main()

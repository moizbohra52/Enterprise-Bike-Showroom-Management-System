#!/usr/bin/env python3
"""Verify that `lib/` compiles — without a Dart/Flutter SDK.

`flutter analyze` is the real check and runs in CI (`.github/workflows/ci.yml`).
This script is the fallback for environments that have no toolchain at all
(the same idea as `db_verify.py` for the SQL migrations): it parses every
library in `lib/` and reports the classes of *hard* compile error that a
generated/edited code base actually produces.

Checks
  1. imports/exports      every `dart:`-free URI resolves to a file in lib/
  2. duplicate types      one top-level name must not be declared twice
                          (an ambiguous import is a compile error)
  3. missing imports      a project symbol used in a library that does not
                          (transitively) import/`export` the declaring library
  4. members              `Type.member`, `Enum.value`, `Type.named(...)`,
                          `variable.member` for explicitly typed variables
  5. call signatures      unknown named parameter, missing `required` named
                          parameter, too many / too few positional arguments
  6. declarations         `required` + default value, optional parameter of a
                          non-nullable type without a default, non-nullable
                          non-`late` field no constructor initialises
  7. const / super        `const Foo(...)` against a non-const constructor,
                          `super.x` formals the super-class ctor does not accept
  8. structure            balanced brackets, no nested type declarations

Deliberately conservative: anything that needs real type inference (type
mismatches, override compatibility, inference failures, `dynamic`) is skipped,
so a clean run is *necessary*, not sufficient. Exit code 1 when it finds
something.

Usage
    python3 scripts/dart_verify.py                 # human readable
    python3 scripts/dart_verify.py --json          # machine readable
    python3 scripts/dart_verify.py --root lib --package enterprise_bike_showroom
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict

IDENT = r'[A-Za-z_$][A-Za-z0-9_$]*'
UPPER = r'[A-Z]' + IDENT
MODIFIERS = ('static', 'const', 'final', 'factory', 'late', 'override', 'abstract',
             'external', 'covariant', 'sealed', 'base', 'interface', 'augment')
STMT_KW = ('return', 'await', 'if', 'for', 'while', 'switch', 'assert', 'throw',
           'yield', 'else', 'do', 'case', 'break', 'continue', 'print', 'super',
           'this', 'var')
UNIVERSAL = {'toString', 'hashCode', 'runtimeType', 'noSuchMethod', 'compareTo',
             'values', 'name', 'index', 'call', 'operator', 'byName'}
DART_KEYWORDS = frozenset('''
    abstract as assert async await base break case catch class const continue
    covariant default deferred do dynamic else enum export extends extension
    external factory final finally for get hide if implements import in
    interface is late library mixin new of on operator part required rethrow
    return sealed set show static super switch sync this throw try typedef var
    void while with yield int double num bool true false null
'''.split())

# Members contributed by the external base types used in this repo. Needed by
# check_scope(): inside `extension ListX<T> on List<T>` a bare `length` is in
# scope, and inside `State` a bare `context` is -- but inside `StatelessWidget`
# it is not (that is the bug this pass exists to find). A base type that is not
# listed makes its class body opaque and the pass stays silent for it.
EXTERNAL_BASE_MEMBERS = {
    'StatelessWidget': {'key', 'build', 'createElement', 'hashCode', 'runtimeType'},
    'StatefulWidget': {'key', 'createElement', 'createState', 'hashCode', 'runtimeType'},
    'State': {'context', 'widget', 'mounted', 'setState', 'initState', 'dispose',
              'didChangeDependencies', 'didUpdateWidget', 'reassemble', 'deactivate',
              'hashCode', 'runtimeType'},
    'InheritedWidget': {'key', 'widget', 'updateShouldNotify'},
    'GetView': {'controller', 'tag', 'build', 'key'},
    'GetWidget': {'controller', 'tag', 'build', 'key'},
    'GetxController': {'isClosed', 'update', 'onInit', 'onReady', 'onClose', 'onStart',
                       'onDelete', 'addListener', 'removeListener', 'addListenerId',
                       'removeListenerId', 'notifyChildrens', 'changed', 'refresh',
                       'refreshGroup', 'ever', 'once', 'debounce', 'interval',
                       'hashCode', 'runtimeType', 'toString'},
    'GetxService': {'isClosed', 'onInit', 'onReady', 'onClose', 'onStart', 'onDelete',
                    'addListener', 'removeListener', 'update', 'hashCode', 'runtimeType'},
    'Bindings': {'dependencies', 'hashCode', 'runtimeType'},
    'GetMiddleware': {'redirect', 'onPageCalled', 'bindings', 'priority', 'enabled',
                      'onInit', 'onReady', 'onClose', 'hashCode', 'runtimeType'},
    'Interceptor': {'onRequest', 'onResponse', 'onError', 'hashCode', 'runtimeType'},
    'QueuedInterceptor': {'onRequest', 'onResponse', 'onError'},
    'Exception': {'toString'},
    'Error': {'toString', 'stackTrace'},
    'List': {'length', 'isEmpty', 'isNotEmpty', 'first', 'last', 'single', 'reversed',
             'iterator', 'add', 'addAll', 'insert', 'insertAll', 'remove', 'removeAt',
             'removeLast', 'removeWhere', 'retainWhere', 'clear', 'contains', 'indexOf',
             'lastIndexOf', 'indexWhere', 'firstWhere', 'singleWhere', 'elementAt',
             'map', 'expand', 'where', 'whereType', 'toList', 'toSet', 'take', 'takeWhile',
             'skip', 'skipWhile', 'any', 'every', 'join', 'reduce', 'fold', 'sort',
             'shuffle', 'sublist', 'getRange', 'setRange', 'setAll', 'fillRange',
             'asMap', 'asReversed', 'cast', 'typed', 'toString', 'hashCode'},
    'Map': {'keys', 'values', 'length', 'isEmpty', 'isNotEmpty', 'containsKey',
            'containsValue', 'entries', 'putIfAbsent', 'remove', 'clear', 'forEach',
            'update', 'map', 'cast', 'toString', 'hashCode'},
    'Set': {'length', 'isEmpty', 'isNotEmpty', 'first', 'last', 'single', 'contains',
            'add', 'addAll', 'remove', 'removeAll', 'clear', 'union', 'intersection',
            'difference', 'map', 'where', 'toList', 'toSet', 'any', 'every', 'join',
            'iterator', 'lookup', 'toString', 'hashCode'},
    'Iterable': {'length', 'isEmpty', 'isNotEmpty', 'first', 'last', 'single', 'iterator',
                 'map', 'where', 'toList', 'toSet', 'any', 'every', 'join', 'reduce',
                 'fold', 'take', 'skip', 'contains', 'elementAt', 'firstWhere',
                 'singleWhere', 'expand', 'cast', 'toString', 'hashCode'},
    'String': {'length', 'isEmpty', 'isNotEmpty', 'codeUnits', 'runes', 'characters',
               'substring', 'split', 'splitMapJoin', 'trim', 'trimLeft', 'trimRight',
               'toLowerCase', 'toUpperCase', 'replaceAll', 'replaceAllMapped',
               'replaceFirst', 'replaceRange', 'contains', 'startsWith', 'endsWith',
               'indexOf', 'lastIndexOf', 'padLeft', 'padRight', 'compareTo', 'isValid',
               'toString', 'hashCode'},
    'num': {'toInt', 'toDouble', 'toStringAsFixed', 'toStringAsPrecision', 'toStringAsExponential',
            'abs', 'round', 'ceil', 'floor', 'truncate', 'sign', 'isNaN', 'isInfinite',
            'isFinite', 'isNegative', 'isInteger', 'clamp', 'remainder', 'compareTo',
            'toString', 'hashCode', 'runtimeType'},
    'int': {'toInt', 'toDouble', 'toStringAsFixed', 'abs', 'round', 'ceil', 'floor',
            'truncate', 'sign', 'isEven', 'isOdd', 'bitLength', 'toRadixString',
            'isNaN', 'isFinite', 'clamp', 'remainder', 'compareTo', 'toString', 'hashCode'},
    'double': {'toInt', 'toDouble', 'toStringAsFixed', 'toStringAsPrecision', 'abs',
               'round', 'ceil', 'floor', 'truncate', 'sign', 'isNaN', 'isInfinite',
               'isFinite', 'isNegative', 'clamp', 'remainder', 'compareTo', 'toString',
               'hashCode'},
    'bool': {'toString', 'hashCode'},
    'DateTime': {'year', 'month', 'day', 'hour', 'minute', 'second', 'millisecond',
                 'microsecond', 'weekday', 'millisecondsSinceEpoch', 'microsecondsSinceEpoch',
                 'timeZoneName', 'timeZoneOffset', 'isUtc', 'add', 'subtract',
                 'difference', 'isBefore', 'isAfter', 'isAtSameMomentAs', 'compareTo',
                 'toLocal', 'toUtc', 'toIso8601String', 'toString', 'hashCode'},
    'Duration': {'inDays', 'inHours', 'inMinutes', 'inSeconds', 'inMilliseconds',
                 'inMicroseconds', 'isNegative', 'abs', 'compareTo', 'toString', 'hashCode'},
    'BuildContext': {'widget', 'size', 'owner', 'mount', 'depth', 'debugDoingBuild',
                     'findRenderObject', 'findAncestorRenderObjectOfType',
                     'findAncestorStateOfType', 'findAncestorWidgetOfExactType',
                     'getElementForInheritedWidgetOfExactType',
                     'getInheritedWidgetOfExactType', 'dependOnInheritedWidgetOfExactType',
                     'dependOnInheritedElement', 'inflateWidget', 'visitAncestorElements',
                     'visitChildElements', 'canPop', 'pop', 'maybePop', 'push',
                     'dispose', 'deactivate', 'didChangeDependencies', 'toString', 'hashCode'},
    'Object': {'hashCode', 'runtimeType', 'toString', 'noSuchMethod'},
    'SupabaseQueryBuilder': {'select', 'insert', 'update', 'upsert', 'delete', 'rpc',
                             'count', 'toString', 'hashCode'},
}


IMPORT_RE = re.compile(
    r'^[ \t]*(import|export)[ \t]+[\'"]([^\'"]+)[\'"]'
    r'([ \t]*(?:as[ \t]+\w+|show[ \t]+[^;]+|hide[ \t]+[^;]+|if[ \t]*\([^)]*\))*)',
    re.M)
DECL_HEAD_RE = re.compile(
    r'^(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+|mixin\s+|augment\s+)*'
    r'(class|mixin\s+class|mixin|enum|extension\s+type|extension)\s+(' + IDENT + r')'
    r'(?:<[^<>]*(?:<[^<>]*>)?[^<>]*>)?'
    r'((?:\s+(?:extends|on|with|implements)\s+[^{]+?)*)\s*\{', re.M)
FIELD_DECL = re.compile(
    r'^[ \t]*(?:(?:final|const|late)\s+)?(' + UPPER + r')((?:<[^;=]*?>)?\??)\s+'
    r'(' + IDENT + r')\s*(=[^=]|;)',
    re.M)
VAR_DECL = re.compile(
    r'(?<![\w.$])((?:final|const|var|late)\s+)?(' + UPPER + r')\s+(' + IDENT + r')\s*(?:=[^=]|;|,|\))')
THIS_FIELD = re.compile(r'\bthis\.(' + IDENT + r')')
GETVIEW = re.compile(r'\bGet(?:View|Widget|ResponsiveView)<\s*(' + UPPER + r')\s*>')


# --------------------------------------------------------------------- lexer
def nocomments(src: str) -> str:
    """Drop `//` and `/* */` comments, keep string literals."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
            out.append('  ')
            continue
        if c in "'\"":
            if src[i:i + 3] in ("'''", '"""'):
                q = src[i:i + 3]
                j = i + 3
                while j < n:
                    if src[j] == '\\':
                        j += 2
                        continue
                    if src[j:j + 3] == q:
                        break
                    j += 1
                out.append(src[i:j + 3])
                i = j + 3
                continue
            q, j = c, i + 1
            while j < n and src[j] != q:
                if src[j] == '\\':
                    j += 2
                elif src[j] == '\n':
                    break
                else:
                    j += 1
            out.append(src[i:j + 1])
            i = j + 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def strip_src(src: str) -> str:
    """Drop comments *and* string literals (interpolation collapsed)."""
    src = nocomments(src)
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in "'\"":
            if out and out[-1] == 'r' and (
                    len(out) < 2 or not (out[-2].isalnum() or out[-2] in '_$')):
                out.pop()                     # raw-string prefix, not an identifier
            if src[i:i + 3] in ("'''", '"""'):
                q = src[i:i + 3]
                j = src.find(q, i + 3)
                i = n if j < 0 else j + 3
                out.append('""')
                continue
            q, i = c, i + 1
            while i < n and src[i] != q:
                if src[i] == '\\':
                    i += 2
                elif src[i] == '\n':
                    break
                elif src[i] == '$' and i + 1 < n and src[i + 1] == '{':
                    depth, i = 1, i + 2       # skip the whole ${...} block
                    while i < n and depth > 0:
                        if src[i] == '{':
                            depth += 1
                        elif src[i] == '}':
                            depth -= 1
                        elif src[i] in "'\"":
                            q2, i = src[i], i + 1
                            while i < n and src[i] != q2:
                                i += 2 if src[i] == '\\' else 1
                        i += 1
                elif src[i] == '$':
                    i += 1
                    while i < n and (src[i].isalnum() or src[i] in '_$'):
                        i += 1
                else:
                    i += 1
            i += 1
            out.append('""')
            continue
        if c == '$' and i + 1 < n and src[i + 1] == '{':
            depth, i = 1, i + 2
            while i < n and depth > 0:
                if src[i] == '{':
                    depth += 1
                elif src[i] == '}':
                    depth -= 1
                elif src[i] in "'\"":
                    q, i = src[i], i + 1
                    while i < n and src[i] != q:
                        i += 2 if src[i] == '\\' else 1
                i += 1
            out.append('""')
            continue
        out.append(c)
        i += 1
    return ''.join(out)


# --------------------------------------------------------------- small utils
def balanced(src: str, open_idx: int) -> int:
    """Index just after the bracket matching `src[open_idx]`."""
    depth, i, n = 0, open_idx, len(src)
    while i < n:
        c = src[i]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def split_top(s: str, sep: str = ',') -> list[str]:
    """Split on `sep` at nesting depth 0 (counts ()[]{} and <>)."""
    out, depth, angle, cur, i, n = [], 0, 0, [], 0, len(s)
    while i < n:
        c = s[i]
        if c == '<':
            angle += 1
        elif c == '>':
            angle = max(0, angle - 1)
        elif angle == 0:
            if c in '([{':
                depth += 1
            elif c in ')]}':
                depth -= 1
            elif c == sep and depth == 0:
                out.append(''.join(cur))
                cur = []
                i += 1
                continue
        cur.append(c)
        i += 1
    out.append(''.join(cur))
    return [p for p in out if p.strip()]


def strip_generics(s: str) -> str:
    out, depth = [], 0
    for c in s or '':
        if c == '<':
            depth += 1
        elif c == '>':
            depth -= 1
        elif depth == 0:
            out.append(c)
    return ''.join(out).strip()


def split_default(p: str):
    """`head = default` at a top-level `=` (never `==`, `=>`, `<=`, `>=`)."""
    depth = angle = 0
    for i, c in enumerate(p):
        if c == '<':
            angle += 1
        elif c == '>':
            angle = max(0, angle - 1)
        elif angle == 0:
            if c in '([{':
                depth += 1
            elif c in ')]}':
                depth -= 1
            elif c == '=' and depth == 0:
                prev = p[i - 1] if i else ''
                nxt = p[i + 1] if i + 1 < len(p) else ''
                if prev in '=!<>+' or nxt in '=>':
                    continue
                return p[:i], p[i + 1:], True
    return p, '', False


# ------------------------------------------------------------------- project
class Project:
    def __init__(self, root: str, package: str):
        self.root = root.rstrip('/')
        self.package = package
        self.files: list[str] = []
        for dp, _, fn in os.walk(self.root):
            for f in fn:
                if f.endswith('.dart'):
                    self.files.append(os.path.join(dp, f).replace('\\', '/'))
        self.files.sort()
        self.info: dict[str, dict] = {}
        self.types: dict[str, dict] = {}
        self.issues: list[dict] = []
        self._closure: dict[str, set] = {}
        self.ext_members: dict[str, set] = defaultdict(set)
        self.sig_of: dict[tuple, dict] = {}
        self.decl_spans: dict[str, list] = defaultdict(list)

    # -- helpers ----------------------------------------------------------
    def add(self, file, line, ref, why, owner=''):
        self.issues.append(dict(file=file, line=line, ref=ref, why=why, owner=owner))

    @staticmethod
    def line_of(src: str, idx: int) -> int:
        return src.count('\n', 0, idx) + 1

    def resolve(self, f: str, uri: str):
        if uri.startswith('dart:'):
            return None
        if uri.startswith('package:'):
            parts = uri.split('/')
            if parts[0].split(':', 1)[1] != self.package:
                return ('ext', parts[0].split(':', 1)[1])
            return os.path.normpath(os.path.join(self.root, *parts[1:])).replace('\\', '/')
        return os.path.normpath(os.path.join(os.path.dirname(f), uri)).replace('\\', '/')

    def closure(self, f: str, seen=None) -> set:
        """Libraries whose declarations are visible in `f` (imports + re-exports)."""
        if f in self._closure:
            return self._closure[f]
        if seen is None:
            seen = set()
        if f in seen:
            return set()
        seen.add(f)
        out = set()
        for kind, uri, opts in self.info.get(f, {}).get('imports', []):
            if re.search(r'\bas\s+\w+', opts):
                continue                      # prefixed: not directly visible
            r = self.resolve(f, uri)
            if isinstance(r, tuple) or r not in self.info:
                continue
            out.add(r)
            out |= self.closure(r, seen)
        self._closure[f] = out
        return out

    # -- pass 1: parse every library --------------------------------------
    def parse(self):
        for f in self.files:
            raw = open(f, encoding='utf-8').read()
            nc = nocomments(raw)
            src = strip_src(raw)
            imps = [(m.group(1), m.group(2), m.group(3) or '') for m in IMPORT_RE.finditer(nc)]
            self.info[f] = dict(src=src, raw=raw, imports=imps, decls=set())

        for f in self.files:
            src = self.info[f]['src']
            pos = 0
            while True:
                m = DECL_HEAD_RE.search(src, pos)
                if not m:
                    break
                brace = src.index('{', m.end() - 1)
                body, end = self.body_at(src, brace)
                name, kind = m.group(2), m.group(1).replace(' ', '_')
                supers = []
                for sm in re.finditer(r'\b(?:extends|on|with|implements)\s+([^>{]+)', m.group(3) or ''):
                    for part in split_top(sm.group(1)):
                        base = re.sub(r'<.*', '', part).strip().split('.')[-1]
                        if base:
                            supers.append(base)
                self.types[name] = dict(
                    name=name, file=f, kind=kind, body=body, start=brace, end=end,
                    supers=supers, members=set(), ctors=set(), values=set())
                # per-file record: survives name collisions between libraries
                self.info[f].setdefault('tspans', []).append(
                    dict(name=name, kind=kind, start=brace, end=end, supers=supers))
                pos = end
            # per-file top-level declarations (cheap, for the import check)
            depth, i = 0, 0
            while i < len(src):
                if depth == 0 and (src[i].isalpha() or src[i] in '_$'):
                    mm = re.match(r'(?:' + '|'.join(MODIFIERS) + r'\s+)*'
                                  r'(?:class|mixin|enum|extension|typedef)\s+(' + IDENT + r')', src[i:])
                    if mm:
                        self.info[f]['decls'].add(mm.group(1))
                        i += mm.end()
                        continue
                if src[i] == '{':
                    depth += 1
                elif src[i] == '}':
                    depth -= 1
                i += 1

        for name, t in self.types.items():
            body = t['body']
            if t['kind'] == 'enum':
                t['values'] = set(self.enum_values(body))
                semi = body.find(';')
                tail = body[semi + 1:] if semi >= 0 else ''
                t['members'] = self.scan_members(name, tail) | self.enum_ctors(name, tail)
            else:
                t['members'], t['ctors'] = self.scan_members_and_ctors(name, body)
                t['members'] |= t['ctors']
            if t['kind'].startswith('extension'):
                for base in t['supers']:
                    self.ext_members[base] |= t['members']

    @staticmethod
    def body_at(src, brace):
        depth, i, n = 0, brace, len(src)
        while i < n:
            c = src[i]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    return src[brace + 1:i], i + 1
            i += 1
        return src[brace + 1:], n

    @staticmethod
    def enum_values(body):
        head, depth = body, 0
        for idx, c in enumerate(body):
            if c in '({[<':
                depth += 1
            elif c in ')}]>':
                depth -= 1
            elif c == ';' and depth == 0:
                head = body[:idx]
                break
        vals = []
        for part in split_top(head):
            m = re.match(r'\s*(' + IDENT + r')', part)
            if m:
                vals.append(m.group(1))
        return vals

    @staticmethod
    def enum_ctors(name, body):
        out = set()
        for m in re.finditer(r'^[ \t]*(?:const\s+)?' + re.escape(name) + r'(?:\.(' + IDENT + r'))?\s*\(', body, re.M):
            out.add(m.group(1) or '')
        return out

    def scan_members_and_ctors(self, name, body):
        """Permissive depth-0 scan: identifier followed by ( = ; { is a member."""
        mems, ctors = set(), set()
        depth, i, n = 0, 0, len(body)
        tok = re.compile(IDENT)
        while i < n:
            c = body[i]
            if c in '([{':
                depth += 1
                i += 1
                continue
            if c in ')]}':
                depth -= 1
                i += 1
                continue
            if depth == 0 and (c.isalpha() or c in '_$'):
                m = tok.match(body, i)
                nm = m.group(0)
                j = m.end()
                while j < n and body[j] in ' \t\r\n':
                    j += 1
                if j < n and body[j] == '<':      # generic method
                    d2, k = 0, j
                    while k < n:
                        if body[k] == '<':
                            d2 += 1
                        elif body[k] == '>':
                            d2 -= 1
                            if d2 == 0:
                                k += 1
                                break
                        k += 1
                    while k < n and body[k] in ' \t\r\n':
                        k += 1
                    j = k
                if j < n and body[j] in '(=;{':
                    mems.add(nm)
                    if body[j] == '(' and nm == name:
                        ctors.add('')
                i = m.end()
                continue
            i += 1
        for m in re.finditer(r'^[ \t]*(?:const\s+|factory\s+)?' + re.escape(name) +
                             r'\.(' + IDENT + r')\s*\(', body, re.M):
            ctors.add(m.group(1))
            mems.add(m.group(1))
        if re.search(r'^[ \t]*(?:const\s+|factory\s+)?' + re.escape(name) + r'\s*\(', body, re.M):
            ctors.add('')
        for m in re.finditer(r'^[ \t]*(?:static\s+)?(?:get|set)\s+(' + IDENT + r')', body, re.M):
            mems.add(m.group(1))
        return mems, ctors

    def scan_members(self, name, body):
        return self.scan_members_and_ctors(name, body)[0]

    def chain(self, name, seen=None):
        if seen is None:
            seen = set()
        if name in seen or name not in self.types:
            return set(), set(), set()
        seen.add(name)
        t = self.types[name]
        mem = set(t['members']) | UNIVERSAL | self.ext_members.get(name, set())
        ctors, vals = set(t['ctors']), set(t['values'])
        for p in t['supers']:
            m2, c2, v2 = self.chain(p, seen)
            mem |= m2
            ctors |= c2
            vals |= v2
        return mem, ctors, vals

    # -- pass 2: signatures ----------------------------------------------
    def parse_signatures(self):
        for name, t in self.types.items():
            if t['kind'] == 'enum':
                continue
            body, base, fsrc = t['body'], t['start'] + 1, self.info[t['file']]['src']
            depth, line_start, i, n = 0, 0, 0, len(body)
            while i <= n:
                if i == n or body[i] == '\n':
                    line = body[line_start:i]
                    if depth == 0:
                        self._signature_line(name, t, line, line_start, base, fsrc)
                    depth += line.count('{') + line.count('(') + line.count('[')
                    depth -= line.count('}') + line.count(')') + line.count(']')
                    depth = max(depth, 0)
                    line_start = i + 1
                i += 1

    def _signature_line(self, name, t, line, line_start, base, fsrc):
        s = line.strip()
        if not s or s.startswith(('/', '*', '@', '//', '}', ')', ']', ',', ':', '.')):
            return
        m = re.match(r'^((?:(?:' + '|'.join(MODIFIERS) + r')\s+)*)([^()=;]*?)\s*\(', line)
        if not m:
            return
        mods, head = m.group(1), m.group(2).strip()
        open_idx = line_start + m.end() - 1
        close = balanced(t['body'], open_idx)
        after = t['body'][close:close + 12].lstrip()
        decl_tail = after.startswith(('{', ';', '=>', ':')) or re.match(r'(?:async|sync)\b', after)
        if not decl_tail:
            return
        raw = t['body'][open_idx + 1:close - 1]
        self.decl_spans[t['file']].append((base + open_idx, base + close))
        ctor = re.match(r'^' + re.escape(name) + r'(?:\.(' + IDENT + r'))?$', head)
        if ctor and not mods.strip():
            sig = self.parse_params(raw)
            sig.update(file=t['file'], static=False)
            self.sig_of[(name, ctor.group(1) or '')] = sig
            return
        tokens = strip_generics(head).split()
        first = tokens[0] if tokens else ''
        if len(tokens) >= 2 and '.' not in head and first not in STMT_KW:
            sig = self.parse_params(raw)
            sig.update(file=t['file'], static=bool(re.search(r'\bstatic\b', mods)))
            self.sig_of[(name, tokens[-1])] = sig

    @staticmethod
    def parse_params(s: str) -> dict:
        pos, optpos, named, required = [], [], [], []
        segments, mode, depth, buf = [], 'pos', 0, []
        angle = 0

        def flush():
            nonlocal buf
            if ''.join(buf).strip():
                segments.append((mode, ''.join(buf)))
            buf = []

        for c in s:
            if c in '{[':
                if depth == 0:
                    flush()
                    mode = 'named' if c == '{' else 'opt'
                depth += 1
                continue
            if c in '}]':
                depth -= 1
                if depth == 0:
                    flush()
                    mode = 'pos'
                continue
            if c == '(':
                depth += 1
                buf.append(c)
                continue
            if c == ')':
                depth = max(0, depth - 1)
                buf.append(c)
                continue
            if c == '<':
                angle += 1
                buf.append(c)
                continue
            if c == '>':
                angle = max(0, angle - 1)
                buf.append(c)
                continue
            if c == ',' and angle == 0 and ((mode == 'pos' and depth == 0) or (mode != 'pos' and depth == 1)):
                flush()
                continue
            buf.append(c)
        flush()

        for md, rawp in segments:
            p = rawp.strip()
            req = bool(re.match(r'^required\s+', p))
            head, _, has_default = split_default(re.sub(r'^required\s+', '', p).strip())
            head = head.strip()
            if head.startswith('this.') or head.startswith('super.'):
                mm = re.match(r'(?:this|super)\.(' + IDENT + r')', head)
                if not mm:
                    continue
                pname = mm.group(1)
                ptype = ''                # taken from the field itself
                nullable = True           # judged from the field, check 6 does it
            else:
                mm = re.search(r'(' + IDENT + r')\s*$', head)
                if not mm:
                    continue
                pname = mm.group(1)
                ptype = head[:mm.start()].strip()
                nullable = (not ptype) or ptype in ('dynamic', 'var') or ptype.endswith('?') \
                    or bool(re.fullmatch(r'[A-Z]', ptype))
            entry = dict(name=pname, required=req and not has_default,
                         default=has_default, nullable=nullable, type=ptype.strip(),
                         this=head.startswith('this.'))
            if md == 'named':
                named.append(entry)
                if entry['required']:
                    required.append(pname)
            elif md == 'opt':
                optpos.append(entry)
            else:
                pos.append(entry)
        return dict(pos=pos, optpos=optpos, named=named, required=required)

    # -- checks -----------------------------------------------------------
    def check_imports_and_duplicates(self):
        owners = defaultdict(set)
        for f in self.files:
            for kind, uri, _ in self.info[f]['imports']:
                r = self.resolve(f, uri)
                if r is None or isinstance(r, tuple):
                    continue
                if not os.path.exists(r):
                    self.add(f, 1, uri, 'import does not resolve to a file in %s/' % self.root)
        for name, t in self.types.items():
            owners[name].add(t['file'])
        for f in self.files:
            for d in self.info[f]['decls']:
                owners[d].add(f)
        for name, fs in sorted(owners.items()):
            if len(fs) > 1 and not name.startswith('_'):
                self.add(sorted(fs)[0], 1, name,
                         'declared in more than one library: %s (importing both paths is an '
                         'ambiguous-import error)' % ', '.join(sorted(fs)))

        decl_owner = defaultdict(set)
        for name, t in self.types.items():
            decl_owner[name].add(t['file'])
        id_re = re.compile(r'\b(' + UPPER + r')\b')
        for f in self.files:
            visible = {f} | self.closure(f)
            vis_decls = set()
            for g in visible:
                vis_decls |= self.info[g]['decls']
                vis_decls |= {n for n, t in self.types.items() if t['file'] == g}
            for nm in sorted(set(id_re.findall(self.info[f]['src'])) & set(decl_owner)):
                if nm in vis_decls or decl_owner[nm] <= visible:
                    continue
                self.add(f, self.line_of(self.info[f]['src'],
                                         self.info[f]['src'].find(nm)),
                         nm, 'used but its library is not imported (declared only in %s)'
                         % ', '.join(sorted(decl_owner[nm])))

    def check_structure(self):
        for f in self.files:
            src = self.info[f]['src']
            for op, cl in (('{', '}'), ('(', ')'), ('[', ']')):
                if src.count(op) != src.count(cl):
                    self.add(f, 1, op + cl,
                             'unbalanced %s (%d vs %d)' % (op + cl, src.count(op), src.count(cl)))
            depth, i = 0, 0
            while i < len(src):
                if depth > 0:
                    m = re.match(r'(?:class|mixin|enum|extension)\s+(' + IDENT + r')', src[i:])
                    if m and src[i] in 'cme':
                        self.add(f, self.line_of(src, i), m.group(1),
                                 'nested type declaration (Dart has no nested classes)')
                if src[i] == '{':
                    depth += 1
                elif src[i] == '}':
                    depth -= 1
                i += 1

    def _visible_types(self, f):
        visible = {f} | self.closure(f)
        return {n for n, t in self.types.items() if t['file'] in visible}

    def _scope(self, f):
        """variable -> project type, per enclosing class (+ file scope)."""
        src = self.info[f]['src']
        vis = self._visible_types(f)
        own = [(n, t) for n, t in self.types.items() if t['file'] == f]
        file_vars = defaultdict(set)
        class_vars = defaultdict(lambda: defaultdict(set))
        opaque = defaultdict(set)

        def owner_of(idx):
            for n, t in own:
                if t['start'] <= idx <= t['end']:
                    return n
            return None

        for n, t in own:
            for fm in FIELD_DECL.finditer(t['body']):
                if fm.group(1) not in vis:
                    opaque[n].add(fm.group(2))      # Rx<Model?> x -> `.value` is GetX
            gv = GETVIEW.search(src[max(0, t['start'] - 400):t['start'] + 1])
            if gv and gv.group(1) in vis:
                class_vars[n]['controller'].add(gv.group(1))
            for tm in THIS_FIELD.finditer(t['body']):
                fld = tm.group(1)
                fm = re.search(r'^[ \t]*(?:(?:final|const|late)\s+)?(' + UPPER + r')(?:<[^;=]*?>)?\??\s+'
                               + re.escape(fld) + r'\s*(?:=[^=]|;)', t['body'], re.M)  # type only
                if fm and fm.group(1) in vis:
                    class_vars[n][fld].add(fm.group(1))
        for fm in FIELD_DECL.finditer(src):
            if fm.group(1) in vis and fm.group(3) not in STMT_KW:
                owner = owner_of(fm.start())
                (class_vars[owner] if owner else file_vars)[fm.group(3)].add(fm.group(1))
        for m in VAR_DECL.finditer(src):
            typ, var = m.group(2), m.group(3)
            if typ not in vis or var in STMT_KW:
                continue
                owner = owner_of(m.start())
                (class_vars[owner] if owner else file_vars)[var].add(typ)

        def var_type(idx, var):
            owner = owner_of(idx)
            if owner and var in opaque[owner]:
                return None
            cands = set(file_vars.get(var, ()))
            if owner:
                cands |= class_vars[owner].get(var, set())
            return next(iter(cands)) if len(cands) == 1 else None

        return var_type, vis, own, owner_of

    def check_members(self):
        static_ref = re.compile(r'(?<![\w.$])(' + UPPER + r')\.(' + IDENT + r')\b')
        inst_ref = re.compile(r'(?<![\w.$])(' + IDENT + r')\.(' + IDENT + r')\b')
        new_ref = re.compile(r'(?<![\w.$])(' + UPPER + r')\s*(?:<[^<>;{}()]*>)?\s*\(')
        for f in self.files:
            src = self.info[f]['src']
            var_type, vis, own, owner_of = self._scope(f)
            for m in static_ref.finditer(src):
                cls, member = m.group(1), m.group(2)
                if cls not in vis:
                    continue
                t = self.types[cls]
                mem, ctors, vals = self.chain(cls)
                ln = self.line_of(src, m.start())
                if t['kind'] == 'enum':
                    if member in vals or member in mem:
                        continue
                    self.add(f, ln, '%s.%s' % (cls, member),
                             'enum has no such value (declares: %s)' % ', '.join(sorted(t['values'])),
                             t['file'])
                    continue
                if member in mem:
                    continue
                self.add(f, ln, '%s.%s' % (cls, member),
                         'no such member on %s' % cls, t['file'])
            for m in new_ref.finditer(src):
                cls = m.group(1)
                if cls not in vis or self.types[cls]['kind'] != 'class':
                    continue
                ctors = self.types[cls]['ctors']
                if not ctors or '' in ctors:
                    continue
                self.add(f, self.line_of(src, m.start()), '%s()' % cls,
                         'only named constructors exist: %s'
                         % ', '.join(sorted(c for c in ctors if c)), self.types[cls]['file'])
            for m in inst_ref.finditer(src):
                var, member = m.group(1), m.group(2)
                if var[0].isupper():
                    continue
                typ = var_type(m.start(), var)
                if not typ:
                    continue
                mem, ctors, vals = self.chain(typ)
                if member in mem or member in vals:
                    continue
                if member.startswith('_') and self.types[typ]['file'] != f:
                    self.add(f, self.line_of(src, m.start()), '%s.%s' % (var, member),
                             'private member of %s used from another library' % typ,
                             self.types[typ]['file'])
                    continue
                self.add(f, self.line_of(src, m.start()), '%s.%s' % (var, member),
                         'no such member on %s (%s)' % (var, typ), self.types[typ]['file'])

    def _check_call(self, f, src, idx, label, sig, arg_src, target):
        named_seen, pos_count, spread = set(), 0, False
        for a in split_top(arg_src):
            a = a.strip()
            nm = re.match(r'^(' + IDENT + r')\s*:(?!:)', a)
            if nm:
                named_seen.add(nm.group(1))
            elif a.startswith('...'):
                spread = True
                break
            else:
                pos_count += 1
        if spread:
            return
        ln = self.line_of(src, idx)
        for n in sorted(named_seen):
            if n not in [p['name'] for p in sig['named']]:
                self.add(f, ln, '%s(%s:)' % (label, n),
                         'no such named parameter on %s (accepts: %s)'
                         % (target, ', '.join(p['name'] for p in sig['named']) or 'none'), sig['file'])
        max_pos = len(sig['pos']) + len(sig['optpos'])
        req_pos = sum(1 for p in sig['pos'] if not p['default'])
        if pos_count > max_pos:
            self.add(f, ln, '%s()' % label,
                     'too many positional arguments for %s (%d given, %d accepted)'
                     % (target, pos_count, max_pos), sig['file'])
        elif pos_count < req_pos:
            self.add(f, ln, '%s()' % label,
                     'missing positional arguments for %s (%d given, %d required)'
                     % (target, pos_count, req_pos), sig['file'])
        for n in sig['required']:
            if n not in named_seen:
                self.add(f, ln, '%s()' % label,
                         'missing required named parameter `%s` on %s' % (n, target), sig['file'])

    def check_calls(self):
        names = sorted(self.types, key=len, reverse=True)
        call_re = re.compile(r'(?<![\w.$])(' + '|'.join(re.escape(n) for n in names) +
                             r')(?:\.(' + IDENT + r'))?\s*\(')
        inst_call = re.compile(r'(?<![\w.$])(' + IDENT + r')\.(' + IDENT + r')\s*\(')
        for f in self.files:
            src = self.info[f]['src']
            var_type, vis, own, owner_of = self._scope(f)
            spans = self.decl_spans.get(f, ())
            for m in call_re.finditer(src):
                idx = m.end() - 1
                if any(s <= idx < e for s, e in spans):
                    continue
                cls, member = m.group(1), m.group(2) or ''
                if cls not in vis:
                    continue
                sig = self.sig_of.get((cls, member))
                if sig is None:
                    continue
                close = balanced(src, idx)
                label = cls + ('.' + member if member else '')
                self._check_call(f, src, m.start(), label, sig, src[idx + 1:close - 1], label)
            for m in inst_call.finditer(src):
                idx = m.end() - 1
                if any(s <= idx < e for s, e in spans):
                    continue
                var, member = m.group(1), m.group(2)
                if var[0].isupper():
                    continue
                typ = var_type(m.start(), var)
                if not typ:
                    continue
                sig = self.sig_of.get((typ, member))
                if sig is None:
                    continue
                close = balanced(src, idx)
                self._check_call(f, src, m.start(), '%s.%s' % (var, member), sig,
                                 src[idx + 1:close - 1], '%s.%s' % (typ, member))

    def check_declarations(self):
        for name, t in self.types.items():
            if t['kind'] != 'class':
                continue
            body, base, fsrc = t['body'], t['start'] + 1, self.info[t['file']]['src']
            is_abstract = bool(re.search(r'\babstract\s+class\s+' + re.escape(name) + r'\b', fsrc))
            fields, ctors = {}, []
            depth, line_start, i, n = 0, 0, 0, len(body)
            while i <= n:
                if i == n or body[i] == '\n':
                    line = body[line_start:i]
                    if depth == 0:
                        fm = FIELD_DECL.match(line)
                        if fm:
                            fields[fm.group(3)] = dict(
                                nullable=fm.group(2).strip().endswith('?') or fm.group(1) == 'dynamic',
                                has_init=fm.group(4).startswith('='),
                                late=bool(re.match(r'^[ \t]*(?:static\s+)?late\b', line)),
                                static=bool(re.match(r'^[ \t]*static\b', line)),
                                line=self.line_of(fsrc, base + line_start),
                                type=fm.group(1) + fm.group(2))
                        cm = re.match(r'^[ \t]*(?:(const|factory)\s+)?' + re.escape(name) +
                                      r'(?:\.(' + IDENT + r'))?[ \t]*\(', line)
                        if cm and not cm.group(2):
                            open_idx = line_start + line.index('(', cm.start())
                            close = balanced(body, open_idx)
                            ctors.append(dict(open=open_idx, close=close,
                                              params=body[open_idx + 1:close - 1],
                                              init=self._init_list(body, close),
                                              body=self._ctor_body(body, close),
                                              line=self.line_of(fsrc, base + line_start)))
                    depth += line.count('{') + line.count('(') + line.count('[')
                    depth -= line.count('}') + line.count(')') + line.count(']')
                    depth = max(depth, 0)
                    line_start = i + 1
                i += 1

            for ctor in ctors:
                for mode, raw, off in self._param_segments(ctor['params']):
                    p = raw.strip()
                    req = bool(re.match(r'^required\s+', p))
                    head, _, has_default = split_default(re.sub(r'^required\s+', '', p).strip())
                    head = head.strip()
                    ln = self.line_of(fsrc, base + ctor['open'] + off)
                    if req and has_default:
                        self.add(t['file'], ln, name,
                                 'required parameter with a default value: `%s`' % p)
                    if mode == 'pos' or head.startswith('super.'):
                        continue
                    if head.startswith('this.'):
                        fname = head[5:]
                        fld = fields.get(fname)
                        nullable = fld['nullable'] if fld else True
                        ptype = fld['type'] if fld else '?'
                        pname = fname
                    else:
                        mm = re.search(r'(' + IDENT + r')\s*$', head)
                        if not mm:
                            continue
                        pname = mm.group(1)
                        ptype = head[:mm.start()].strip()
                        nullable = (not ptype) or ptype in ('dynamic', 'var') or ptype.endswith('?')
                    if mode == 'named' and req:
                        continue        # `required` never needs a default
                    if not nullable and not has_default:
                        self.add(t['file'], ln, name,
                                 'optional parameter `%s` of non-nullable type `%s` has no default value'
                                 % (pname, ptype))

            if not is_abstract:
                for fname, fld in fields.items():
                    if fld['static'] or fld['nullable'] or fld['has_init'] or fld['late']:
                        continue
                    ok = False
                    for ctor in ctors:
                        if re.search(r'\bthis\.' + re.escape(fname) + r'\b', ctor['params']) \
                           or re.search(r'(^|[:,])\s*' + re.escape(fname) + r'\s*=(?!=)', ctor['init']) \
                           or re.search(r'(^|[;{}\n])\s*' + re.escape(fname) + r'\s*=(?!=)', ctor['body']):
                            ok = True
                            break
                    if not ok:
                        self.add(t['file'], fld['line'], name,
                                 'non-nullable field `%s` (%s) is not initialised%s'
                                 % (fname, fld['type'],
                                    '' if ctors else ' and the class declares no constructor'))

    @staticmethod
    def _init_list(body, close):
        after = body[close:close + 4000]
        m = re.match(r'\s*(?:async\s*)?:', after)
        if not m:
            return ''
        j, d2, k = close + m.end(), 0, close + m.end()
        while k < len(body):
            ch = body[k]
            if ch in '([{':
                d2 += 1
            elif ch in ')]}':
                d2 -= 1
            elif d2 == 0 and ch in ';{':
                break
            k += 1
        return body[j:k]

    @staticmethod
    def _ctor_body(body, close):
        after = body[close:close + 200]
        m = re.match(r'\s*(?:async\s*)?\{', after)
        if not m:
            return ''
        k = close + m.end() - 1
        e = balanced(body, k)
        return body[k + 1:e - 1]

    @staticmethod
    def _param_segments(param_src):
        mode, depth, angle, start, i, n = 'pos', 0, 0, 0, 0, len(param_src)
        while i < n:
            c = param_src[i]
            if c == '<':
                angle += 1
                i += 1
                continue
            if c == '>':
                angle = max(0, angle - 1)
                i += 1
                continue
            if angle == 0:
                if c in '{[':
                    if depth == 0:
                        mode = 'named' if c == '{' else 'opt'
                        start = i + 1
                    depth += 1
                    i += 1
                    continue
                if c in '}]':
                    depth -= 1
                    if depth == 0:
                        yield mode, param_src[start:i], start
                        mode, start = 'pos', i + 1
                    i += 1
                    continue
                if c in '([':
                    depth += 1
                elif c in ')]':
                    depth = max(0, depth - 1)
                elif c == ',' and depth == (1 if mode != 'pos' else 0):
                    yield mode, param_src[start:i], start
                    start = i + 1
                    i += 1
                    continue
            i += 1
        if start < n and mode == 'pos':
            yield mode, param_src[start:n], start

    def check_const_and_super(self):
        const_ctors, all_ctors = defaultdict(set), defaultdict(set)
        super_params = {}
        for name, t in self.types.items():
            body = t['body']
            for m in re.finditer(r'^[ \t]*(const\s+|factory\s+)?' + re.escape(name) +
                                 r'(?:\.(' + IDENT + r'))?[ \t]*\(', body, re.M):
                ctor = m.group(2) or ''
                all_ctors[name].add(ctor)
                if m.group(1) == 'const ':
                    const_ctors[name].add(ctor)
            cm = re.search(r'^[ \t]*(?:const\s+)?' + re.escape(name) +
                           r'(?:\.' + IDENT + r')?[ \t]*\(', body, re.M)
            if cm:
                open_idx = body.index('(', cm.start())
                close = balanced(body, open_idx)
                sup = []
                for seg in split_top(body[open_idx + 1:close - 1]):
                    sm = re.match(r'^\s*super\.(' + IDENT + r')', seg)
                    if sm:
                        sup.append(sm.group(1))
                super_params[name] = sup

        const_call = re.compile(r'\bconst\s+(?:<[^;{}()]*>\s*)?(' + UPPER + r')(?:\.(' + IDENT + r'))?\s*\(')
        for f in self.files:
            src = self.info[f]['src']
            vis = self._visible_types(f)
            for m in const_call.finditer(src):
                cls, named = m.group(1), m.group(2) or ''
                if cls not in vis or cls not in all_ctors:
                    continue
                ln = self.line_of(src, m.start())
                label = 'const %s%s(...)' % (cls, '.' + named if named else '')
                if named not in all_ctors[cls]:
                    self.add(f, ln, label, 'no such constructor (declared: %s)'
                             % (', '.join(sorted(c or '(unnamed)' for c in all_ctors[cls])) or 'none'))
                elif named not in const_ctors[cls]:
                    self.add(f, ln, label, 'constructor is not const')

        for name, params in super_params.items():
            t = self.types[name]
            sup = [s for s in t['supers'] if s in self.types]
            if len(sup) != 1 or not params:
                continue
            parent = sup[0]
            pbody = self.types[parent]['body']
            pm = re.search(r'^[ \t]*(?:const\s+)?' + re.escape(parent) +
                           r'(?:\.' + IDENT + r')?[ \t]*\(', pbody, re.M)
            if not pm:
                continue
            open_idx = pbody.index('(', pm.start())
            close = balanced(pbody, open_idx)
            accepted = set()
            for seg in split_top(pbody[open_idx + 1:close - 1]):
                s = seg.strip()
                mm = re.match(r'^(?:required\s+)?(?:this\.|super\.)?(' + IDENT + r')', s)
                if not mm:
                    mm = re.search(r'(' + IDENT + r')\s*(?:=[^=].*)?$', s)
                if mm:
                    accepted.add(mm.group(1))
            for pname in params:
                if pname not in accepted:
                    self.add(t['file'], self.line_of(self.info[t['file']]['src'], t['start']),
                             '%s(super.%s)' % (name, pname),
                             'super-class %s constructor has no parameter `%s` (accepts: %s)'
                             % (parent, pname, ', '.join(sorted(accepted))))

    def _const_names(self):
        """Every name declared with `const` anywhere in the project (these ARE
        compile-time constants and may appear inside a const expression)."""
        cache = getattr(self, '_const_names_cache', None)
        if cache is None:
            cache = set()
            pat = re.compile(r'(?<![\w.$])const\s+(?:' + UPPER +
                             r'(?:<[^;=(){}\[\]]*>)?\s+)?(' + IDENT + r')\s*=')
            for f in self.files:
                for m in pat.finditer(self.info[f]['src']):
                    cache.add(m.group(1))
            self._const_names_cache = cache
        return cache

    # -- const expressions must not depend on runtime values --------------
    def _runtime_names(self, f):
        """Locals, parameters and non-const fields declared in `f`.

        These are the only bare identifiers that can legally NOT appear inside a
        `const` expression (a `const` argument must be a compile-time constant),
        so they are what check_const_args() looks for."""
        cached = self.info[f].get('runtime_names')
        if cached is not None:
            return cached
        src = self.info[f]['src']
        names = set()
        # locals / typed declarations: `final int attempt = 0;`, `var x = ...`,
        # `late final Foo bar;`, `const String s = ''` is excluded below.
        for m in re.finditer(r'(?<![\w.$])(?:final|var|late)\s+'
                             r'(?:(?:' + UPPER + r'|' + IDENT + r')'
                             r'(?:<[^;=(){}\[\]]*>)?\??\s+)?(' + IDENT + r')'
                             r'\s*(?:=[^=]|;|\bin\b)', src):
            names.add(m.group(1))
        # non-const instance/static fields: `final Dio dio;`, `String baseUrl;`
        for m in re.finditer(r'^[ \t]*(?:static\s+)?(?:final\s+|late\s+)?'
                             r'(?:' + UPPER + r'|' + IDENT + r')'
                             r'(?:<[^;=(){}\[\]]*>)?\??\s+(' + IDENT + r')'
                             r'\s*(?:=[^=]|;)', src, re.M):
            names.add(m.group(1))
        # parameters of every signature-shaped (...) in the file
        for m in re.finditer(r'(?<![\w.$])(' + IDENT + r')\s*\(', src):
            open_idx = src.index('(', m.start())
            close = balanced(src, open_idx)
            tail = src[close:close + 24].lstrip()
            if not re.match(r'^(?:async\s*)?\{|^;|^=>|^:', tail):
                continue                      # a call, not a declaration
            for seg in split_top(src[open_idx + 1:close - 1]):
                s2 = seg.strip()
                if not s2:
                    continue
                pm = re.search(r'(' + IDENT + r')\s*(?:=[^=].*)?$', s2)
                if pm:
                    names.add(pm.group(1))
        names -= self._const_names()
        self.info[f]['runtime_names'] = names
        return names

    def check_const_args(self):
        const_expr = re.compile(r'(?<![\w.$])const\s+(?:<[^;{}()]*>\s*)?'
                                r'(?:' + UPPER + r'(?:\.' + IDENT + r')?\s*'
                                r'(?:<[^;{}()]*>)?\s*)?[\(\[]')
        # Greedy, with the named-argument-label test done in Python: a trailing
        # `(?!\s*:)` lookahead would backtrack (`days:` matching as `day`).
        ident = re.compile(r'(?<![\w.$"\'])([a-z_$][\w$]*)')
        for f in self.files:
            src = self.info[f]['src']
            runtime = self._runtime_names(f)
            if not runtime:
                continue
            for m in const_expr.finditer(src):
                open_idx = src.index(m.group(0)[-1], m.start())
                region = src[open_idx:balanced(src, open_idx)]
                # collection-for loops may legally bind their own variables
                region = re.sub(r'\bfor\s*\([^()]*\)', ' ', region)
                for im in ident.finditer(region):
                    nm = im.group(1)
                    if nm not in runtime or nm in ('true', 'false', 'null'):
                        continue
                    rest = region[im.end():].lstrip()
                    if rest.startswith(':'):
                        continue          # named-argument label, not a value
                    idx = open_idx + im.start(1)
                    self.add(f, self.line_of(src, idx),
                             'const ...(%s)' % nm,
                             'a const expression cannot use the runtime value '
                             '`%s` (locals, parameters and non-const fields are '
                             'not compile-time constants)' % nm)

    # -- lexical scope: bare identifiers that are not in scope ------------
    #
    # `Widget _initials() { ... Theme.of(context) ... }` in a StatelessWidget
    # has no `context` in scope -- a hard "Undefined name" error that the member
    # and import checks cannot see (nothing is dotted, nothing is imported).
    # Only names that ARE declared somewhere in the project (as a parameter,
    # field or member) are reported: an unknown lowercase name is far more
    # likely to be an external global (`kIsWeb`, `unawaited`, `ever`, ...) whose
    # declaration this tool cannot see.

    def _blank_type_bodies(self, f):
        src = self.info[f]['src']
        chars = list(src)
        for t in self.types.values():
            if t['file'] != f:
                continue
            for i in range(t['start'], min(t['end'], len(chars))):
                chars[i] = ' '
        return ''.join(chars)

    def _file_toplevel(self, f):
        """Top-level function and variable names declared in `f`."""
        cached = self.info[f].get('toplevel')
        if cached is not None:
            return cached
        top = self._blank_type_bodies(f)
        names = set()
        for m in re.finditer(r'(?<![\w.$@])(' + IDENT + r')\s*(?:<[^;=(){}\[\]]*>)?\s*\(', top):
            nm = m.group(1)
            if nm in DART_KEYWORDS:
                continue
            oi = top.index('(', m.start(1))
            tail = top[balanced(top, oi):balanced(top, oi) + 24].lstrip()
            if re.match(r'^(?:async\s*)?\{|^=>|^;', tail):
                names.add(nm)
        for m in re.finditer(r'(?<![\w.$@])(?:const|final|var|late)\s+'
                             r'(?:(?:' + UPPER + r'|' + IDENT + r')'
                             r'(?:<[^;=(){}\[\]]*>)?\??\s+)?(' + IDENT + r')\s*(?:=[^=]|;)', top):
            names.add(m.group(1))
        self.info[f]['toplevel'] = names
        return names

    def _functions(self, f):
        """Every function/method in `f` that has a body: name, spans, params."""
        cached = self.info[f].get('funcs')
        if cached is not None:
            return cached
        src = self.info[f]['src']
        funcs = []
        for m in re.finditer(r'(?<![\w.$@])(' + IDENT + r')\s*(?:<[^;=(){}\[\]]*>)?\s*\(', src):
            nm = m.group(1)
            if nm in DART_KEYWORDS:
                continue
            oi = src.index('(', m.start(1))
            cl = balanced(src, oi)
            tail = src[cl:cl + 24].lstrip()
            if not re.match(r'^(?:async\s*)?\{|^=>', tail):
                continue                      # no body (abstract / ctor init list)
            try:
                sig = self.parse_params(src[oi + 1:cl - 1])
            except Exception:
                continue
            params = {p['name'] for p in sig['pos'] + sig['optpos'] + sig['named']}
            if re.match(r'^(?:async\s*)?\{', tail):
                b0 = src.index('{', cl)
                b1 = balanced(src, b0)
            else:
                b0 = src.index('=>', cl) + 2
                b1 = src.find(';', b0)
                b1 = len(src) if b1 < 0 else b1 + 1
            funcs.append(dict(name=nm, head=m.start(1), params=params, body=(b0, b1)))
        funcs.sort(key=lambda d: d['head'])
        self.info[f]['funcs'] = funcs
        return funcs

    def _locals(self, body):
        """Names bound inside a function body (locals, lambdas, loops, catch)."""
        names = set()
        for m in re.finditer(r'(?<![\w.$])(?:final|var|late|const)\s+'
                             r'(?:' + IDENT + r'(?:\.' + IDENT + r')*'
                             r'(?:<[^;=(){}\[\]]*>)?\??\s+)?(' + IDENT + r')'
                             r'\s*(?:=[^=]|;|\bin\b)', body):
            names.add(m.group(1))
        for m in re.finditer(r'(?<![\w.$])' + IDENT + r'(?:\.' + IDENT + r')*'
                             r'(?:<[^;=(){}\[\]]*>)?\??\s+(' + IDENT + r')\s*=[^=]', body):
            names.add(m.group(1))
        # typed declaration without an initializer: `DateTime? d;`
        for m in re.finditer(r'(?<![\w.$])(?:' + UPPER + r'|int|double|num|bool|dynamic)'
                             r'(?:\.' + IDENT + r')*(?:<[^;=(){}\[\]]*>)?\??'
                             r'\s+([a-z_$][\w$]*)\s*;', body):
            names.add(m.group(1))
        for m in re.finditer(r'\bfor\s*\((?:[^()]|\([^()]*\))*?'
                             r'([a-z_$][\w$]*)\s+in\b', body):
            names.add(m.group(1))
        for m in re.finditer(r'\bcatch\s*\(\s*(' + IDENT + r')(?:\s*,\s*(' + IDENT + r'))?\s*\)', body):
            names.add(m.group(1))
            if m.group(2):
                names.add(m.group(2))
        for m in re.finditer(r'\b(?:get|set)\s+(' + IDENT + r')', body):
            names.add(m.group(1))
        for m in re.finditer(r'\(([^()]*)\)\s*(?:async\s*)?(?:=>|\{)', body):
            for seg in split_top(m.group(1)):
                pm = re.search(r'(' + IDENT + r')\s*(?:=[^=].*)?$', seg.strip())
                if pm:
                    names.add(pm.group(1))
        return {n for n in names if n not in DART_KEYWORDS}

    def _scope_names(self):
        """Every name bound as a parameter, local or member anywhere in the repo."""
        cached = getattr(self, '_scope_names_cache', None)
        if cached is not None:
            return cached
        names = set()
        for t in self.types.values():
            names |= t['members'] | t['ctors']
        for f in self.files:
            for fn in self._functions(f):
                names |= fn['params']
                names |= self._locals(self.info[f]['src'][fn['body'][0]:fn['body'][1]])
        self._scope_names_cache = {n for n in names if n[:1].islower() or n.startswith('_')}
        return self._scope_names_cache

    def _decl_files(self):
        """name -> libraries that declare it (from the per-file type spans)."""
        cache = getattr(self, '_decl_files_cache', None)
        if cache is None:
            cache = defaultdict(set)
            for f in self.files:
                for t in self.info[f].get('tspans', []):
                    cache[t['name']].add(f)
            self._decl_files_cache = cache
        return cache

    @staticmethod
    def _trustworthy(rec, f, decl_files):
        """`self.types` keeps one record per name, so a private class declared in
        two libraries (`_LineRow`) shadows one of them -- trust a record only when
        it belongs to this file or the name is declared in exactly one library."""
        return rec['file'] == f or len(decl_files.get(rec['name'], ())) <= 1

    def _super_chain(self, supers, seen=None):
        """`supers` plus every project supertype above them (members are
        inherited transitively, e.g. InvoiceModel -> BaseModel -> id/createdAt)."""
        if seen is None:
            seen = set()
        out = []
        for sup in supers:
            if sup in seen:
                continue
            seen.add(sup)
            out.append(sup)
            st = self.types.get(sup)
            if st:
                out.extend(self._super_chain(st['supers'], seen))
        return out

    def check_scope(self):
        bare = re.compile(r'(?<![\w.$@\'"#])([a-z_$][\w$]*)')
        known = self._scope_names()
        for f in self.files:
            src = self.info[f]['src']
            funcs = self._functions(f)
            types = self.info[f].get('tspans', [])
            vis = self._file_toplevel(f) | self.info[f]['decls']
            for g in self.closure(f):
                vis |= self._file_toplevel(g) | self.info[g]['decls']
            for fn in funcs:
                b0, b1 = fn['body']
                body = src[b0:b1]
                scope = set(fn['params']) | self._locals(body) | vis | DART_KEYWORDS
                owner = None
                for t in types:
                    if t['start'] <= fn['head'] < t['end']:
                        if owner is None or t['start'] > owner['start']:
                            owner = t
                opaque = False
                if owner is not None:
                    decl_files = self._decl_files()
                    rec = self.types.get(owner['name'])
                    if rec is not None and self._trustworthy(rec, f, decl_files):
                        scope |= rec['members'] | rec['ctors'] | rec['values']
                    else:
                        opaque = True     # shadowed by a same-named type elsewhere
                    scope |= UNIVERSAL
                    for sup in self._super_chain(owner['supers']):
                        st = self.types.get(sup)
                        if st is not None and self._trustworthy(st, f, decl_files):
                            scope |= st['members'] | st['ctors'] | st['values']
                        elif sup in EXTERNAL_BASE_MEMBERS:
                            scope |= EXTERNAL_BASE_MEMBERS[sup]
                        else:
                            opaque = True
                for outer in funcs:                       # nested functions
                    if outer is fn:
                        continue
                    o0, o1 = outer['body']
                    if o0 <= b0 and b1 <= o1:
                        scope |= outer['params'] | self._locals(src[o0:o1])
                        scope.add(outer['name'])          # a local function name
                    elif b0 <= o0 and o1 <= b1:
                        scope.add(outer['name'])
                for im in bare.finditer(body):
                    nm = im.group(1)
                    if nm in scope or nm not in known:
                        continue
                    rest = body[im.end():].lstrip()
                    if rest.startswith(':'):
                        continue              # named-argument label (or map key)
                    if opaque:
                        continue              # inherits from a base we cannot read
                    self.add(f, self.line_of(src, b0 + im.start(1)), nm,
                             '`%s` is not in scope inside %s() -- it is declared '
                             'elsewhere in the project, so this is an undefined '
                             'name at compile time' % (nm, fn['name']))

    def run(self):
        self.parse()
        self.parse_signatures()
        self.check_imports_and_duplicates()
        self.check_structure()
        self.check_members()
        self.check_calls()
        self.check_declarations()
        self.check_const_and_super()
        self.check_const_args()
        self.check_scope()
        return self.issues


# -- informational: rare external-looking names ---------------------------
#
# The passes above can only reason about declarations they can see (this repo).
# A name invented for an external package -- e.g. fl_chart has no DonutChart --
# is invisible to them, so it surfaces as "Type not found" only at build time.
# Heuristic below lists identifiers used in type/call positions that are not
# declared in the repo and appear at most `max_count` times overall: real
# Flutter/package APIs almost always recur, so one-offs deserve a human look.
SUSPECT_PATTERNS = (
    r'\bfinal\s+([A-Z][\w$]*)',
    r'\blate\s+(?:final\s+)?([A-Z][\w$]*)',
    r'\bextends\s+([A-Z][\w$]*)',
    r'\bimplements\s+([A-Z][\w$]*)',
    r'\bas\s+([A-Z][\w$]*)',
    r'\bis\s+!?\s*([A-Z][\w$]*)',
    r'<\s*([A-Z][\w$]*)',
    r'^\s*(?:static\s+)?([A-Z][\w$]*)\s*\??\s+[a-z_$][\w$]*\s*(?:=[^=]|;)',
    r'(?<![\w.$])([A-Z][\w$]*)\s*(?:<[^<>;{}()]*>)?\s*\(',
)

DART_CORE_NAMES = frozenset(    'Object String int double num bool List Map Set Iterable Future Stream '
    'DateTime Duration void dynamic Null Function Record Enum Type Symbol '
    'Error Exception StackTrace Pattern Match Never'.split())


def suspect_names(project, max_count=2):
    declared = set(project.types)
    for f in project.files:
        declared |= project.info[f]['decls']
    counts, where = {}, {}
    for f in project.files:
        src = project.info[f]['src']
        for pat in SUSPECT_PATTERNS:
            for m in re.finditer(pat, src, re.M):
                n = m.group(1)
                counts[n] = counts.get(n, 0) + 1
                if n not in where:
                    where[n] = []
                if len(where[n]) < 2:
                    where[n].append('%s:%d' % (f, project.line_of(src, m.start())))
    out = [(n, c, where[n]) for n, c in counts.items()
           if n not in declared and n not in DART_CORE_NAMES and c <= max_count]
    out.sort(key=lambda x: (x[1], x[0]))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', default='lib', help='Dart source root (default: lib)')
    ap.add_argument('--package', default=None,
                    help='package name (default: `name:` from pubspec.yaml)')
    ap.add_argument('--json', action='store_true', help='emit JSON')
    ap.add_argument('--suspect-names', action='store_true',
                    help='also list rare external-looking names for a human '
                         'review (informational; never affects the exit code)')
    args = ap.parse_args()

    package = args.package
    if package is None and os.path.exists('pubspec.yaml'):
        m = re.search(r'^name:\s*(\S+)', open('pubspec.yaml', encoding='utf-8').read(), re.M)
        package = m.group(1) if m else os.path.basename(os.getcwd())
    package = package or 'app'

    if not os.path.isdir(args.root):
        print('no such directory: %s' % args.root, file=sys.stderr)
        return 2

    project = Project(args.root, package)
    issues = project.run()

    if args.suspect_names:
        sus = suspect_names(project)
        print('\n=== rare external-looking names: %d (review by hand) ===' % len(sus))
        for n, c, wh in sus:
            print('  %-40s %dx  %s' % (n, c, ', '.join(wh)))

    if args.json:
        print(json.dumps(dict(files=len(project.files), types=len(project.types),
                              issues=issues), indent=2))
    else:
        print('%s: %d libraries, %d top-level types' % (args.root, len(project.files), len(project.types)))
        if not issues:
            print('OK — no compile-time errors detected by the static checks.')
        else:
            print('\n%d issue(s):' % len(issues))
            for i in sorted(issues, key=lambda x: (x['file'], x['line'])):
                print('  %s:%s  %s\n      %s%s' % (
                    i['file'], i['line'], i['ref'], i['why'],
                    '\n      declared in %s' % i['owner'] if i['owner'] else ''))
            print('\nThese are the checks that do not need a Dart SDK; run '
                  '`flutter analyze` for the full picture.')
    return 1 if issues else 0


if __name__ == '__main__':
    sys.exit(main())

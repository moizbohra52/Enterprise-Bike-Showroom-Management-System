"""Find GetX `Rx` values used where a plain Dart value is required.

`RxBool` is not a `bool`, and `RxList<T>` is not a `List<T>`, so all of these
are compile errors, not lints:

    isLoading: saving,                 // RxBool -> bool
    onPressed: saving ? null : ...,    // RxBool in a condition
    items: controller.items,           // RxList<T> -> List<T>

The check needs no Dart SDK. It reuses dart_verify's project model to resolve

  * Rx-typed fields and getters of every project class,
  * `controller.<field>` inside a GetView<T> / GetWidget<T> / GetX<T>,
  * Rx-typed locals (`final RxBool saving = _saving;`),
  * the declared type of each named parameter label in the project,

and reports Rx accesses sitting in a position that demands a plain value.
Reads `.value` (and element access `x[i].y`) are correct and are skipped.

Usage:  python3 scripts/dart_rx_check.py [--root lib] [--package NAME]
Exit:   0 = nothing suspicious, 1 = findings (each one is a likely error).
"""
import argparse
import importlib.util
import os
import re
import sys
from collections import defaultdict

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'dv', os.path.join(_HERE, 'dart_verify.py'))
dv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dv)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', default='lib', help='Dart source root (default: lib)')
    ap.add_argument('--package', default=None,
                    help='package name (default: `name:` from pubspec.yaml)')
    args = ap.parse_args()

    package = args.package
    if package is None and os.path.exists('pubspec.yaml'):
        m = re.search(r'^name:\s*(\S+)',
                      open('pubspec.yaml', encoding='utf-8').read(), re.M)
        package = m.group(1) if m else os.path.basename(os.getcwd())
    if not os.path.isdir(args.root):
        print('no such directory: %s' % args.root, file=sys.stderr)
        return 2

    p = dv.Project(args.root, package or 'app')
    p.parse()
    p.parse_signatures()
    findings = scan(p)
    for f, ln, label, typ, why, line in sorted(findings):
        print('%s:%d  %s (%s) %s\n      %s' % (f, ln, label, typ, why, line))
    print('%s: %d suspicious Rx use(s).' % (args.root, len(findings)))
    if findings:
        print('Read the Rx value with `.value` (keep it inside Obx/GetX so the '
              'widget still rebuilds).')
    return 1 if findings else 0


def scan(p):
    RX = re.compile(r'^(Rx[A-Za-z]*(?:<.*>)?|Rxn<.*>)$')
    FIELD = re.compile(
        r'^[ \t]*(?!static\b)(?:late\s+)?(?:final\s+)?'
        r'([A-Za-z_$][\w$]*(?:<[^;=(){}]*>)?\??)\s+([a-z_$][\w$]*)\s*(?:=[^=]|;)', re.M)
    GETTER = re.compile(r'^[ \t]*([A-Za-z_$][\w$]*(?:<[^;=(){}]*>)?\??)\s+get\s+'
                        r'([a-z_$][\w$]*)', re.M)

    # 1) Rx fields per project class
    rx_fields = defaultdict(dict)      # class -> {field: type}
    all_fields = defaultdict(dict)     # class -> {field: type}
    for name, t in p.types.items():
        if t['kind'] != 'class':
            continue
        body = t['body']
        spans = []
        for m in re.finditer(r'\)', body):
            tail = body[m.end():m.end() + 24].lstrip()
            if re.match(r'^(?:async\s*)?\{', tail):
                b0 = body.index('{', m.end())
                spans.append((b0, dv.balanced(body, b0)))
        chars = list(body)
        for a, b in spans:
            for i in range(a, min(b, len(chars))):
                chars[i] = ' '
        shell = ''.join(chars)
        for rx in (FIELD, GETTER):
            for m in rx.finditer(shell):
                typ, fname = m.group(1).strip(), m.group(2)
                if fname in ('get', 'set'):
                    continue
                all_fields[name][fname] = typ
                if RX.match(typ):
                    rx_fields[name][fname] = typ

    # 2) param label -> declared types across the project (approximate target typing).
    #    `this.isLoading = false` field formals take their type from the field.
    label_types = defaultdict(set)
    for (cls, member), sig in p.sig_of.items():
        for entry in sig['named'] + sig['pos'] + sig['optpos']:
            t = (entry.get('type') or '').strip()
            if not t and entry.get('this'):
                t = all_fields.get(cls, {}).get(entry['name'], '')
            if t:
                label_types[entry['name']].add(t)

    def is_rx(typ):
        return bool(RX.match(typ or ''))

    findings = []
    for f in p.files:
        raw = p.info[f]['raw']
        lines = raw.split('\n')
        # which classes live in this file, and their spans (raw coords)
        classes = []
        for name, t in p.types.items():
            if t['file'] != f or t['kind'] != 'class':
                continue
            m = re.search(r'^[ \t]*(?:abstract\s+)?(?:class|mixin|extension)\s+'
                          + re.escape(name) + r'\b', raw, re.M)
            if not m:
                continue
            start = raw.count('\n', 0, m.start()) + 1
            end = raw.count('\n', 0, t['start']) + 1 + t['body'].count('\n')
            supers = t['supers']
            gm = re.search(r'(?:GetView|GetWidget|GetX|GetxController)\s*<\s*([\w$]+)',
                           raw[m.start():m.start() + 240])
            ctrl = gm.group(1) if gm else None
            classes.append((start, end, name, ctrl))
        if not classes:
            continue
        shadowed = set()
        local_rx = {}
        for start, end, name, ctrl in classes:
            for (cls, member), sig in p.sig_of.items():
                if cls != name:
                    continue
                for entry in sig['named'] + sig['pos'] + sig['optpos']:
                    shadowed.add(entry['name'])
        # only *locals* shadow a field: they are indented deeper than the class body
        for m in re.finditer(r'(?<![\w.$])(?:final|var|late)\s+(?:[A-Za-z_$][\w$]*(?:<[^;=(){}]*>)?\??\s+)?([a-z_$][\w$]*)\s*=[^=]', raw):
            ls = raw.rfind('\n', 0, m.start()) + 1
            indent = len(raw[ls:m.start()]) - len(raw[ls:m.start()].lstrip())
            if indent >= 4:
                decl = raw[max(0, m.start() - 60):m.start(1)]
                tm = re.search(r'(Rx[A-Za-z]*(?:<[^;=(){}]*>)?)\s*$', decl)
                if tm:
                    local_rx[m.group(1)] = tm.group(1)   # an Rx-typed local is still Rx
                else:
                    shadowed.add(m.group(1))
        for idx, line in enumerate(lines, start=1):
            code = line.split('//')[0]
            owner = None
            for start, end, name, ctrl in classes:
                if start <= idx <= end:
                    if owner is None or start > owner[0]:
                        owner = (start, name, ctrl)
            if owner is None:
                continue
            _, cname, ctrl = owner
            # candidate Rx access expressions on this line
            accesses = []
            merged = dict(rx_fields.get(cname, {}))
            merged.update(local_rx)
            for fld, typ in merged.items():
                if fld in shadowed:
                    continue
                for m in re.finditer(r'(?<![\w.$])' + re.escape(fld) + r'(?![\w$])', code):
                    if re.search(r'(?:final|late|var)\s+(?:[A-Za-z_$][\w$]*\s+)?'
                                 + re.escape(fld) + r'\s*=', code[:m.start() + len(fld) + 3]):
                        continue
                    accesses.append((m.start(), m.end(), fld, typ))
            if ctrl and ctrl in rx_fields:
                for m in re.finditer(r'(?<![\w.$])controller\.([a-z_$][\w$]*)(?![\w$])', code):
                    fld = m.group(1)
                    if fld in shadowed:
                        continue
                    if fld in rx_fields[ctrl]:
                        accesses.append((m.start(), m.end(), 'controller.' + fld,
                                         rx_fields[ctrl][fld]))
            for m in re.finditer(r'(?<![\w.$])([a-z_$][\w$]*)\.([a-z_$][\w$]*)(?![\w$])', code):
                var, fld = m.group(1), m.group(2)
                if var == 'controller':
                    continue
                decl = re.search(r'final\s+([A-Z][\w$]*)\s+' + re.escape(var) + r'\s*=', code)
                typ_owner = decl.group(1) if decl else None
                if typ_owner and fld in rx_fields.get(typ_owner, {}):
                    accesses.append((m.start(), m.end(), '%s.%s' % (var, fld),
                                     rx_fields[typ_owner][fld]))
            for s, e, label, typ in sorted(accesses):
                after = code[e:]
                if after.lstrip().startswith('.') or after.lstrip().startswith('['):
                    continue                       # .value / [i].x / method call: fine
                why = None
                if re.match(r'\s*(=[^=]|;|\s*$)', after):
                    continue                       # declaration / assignment target
                nm = re.search(r'([a-z_$][\w$]*)\s*:\s*$', code[:s])
                if nm:
                    lab = nm.group(1)
                    types = label_types.get(lab, set())
                    if types and not any(is_rx(t) or t in ('dynamic', 'Object', 'Object?')
                                         for t in types):
                        why = 'named arg `%s:` expects %s' % (
                            lab, '/'.join(sorted(types))[:40])
                if why is None:
                    pre = code[:s]
                    if re.search(r'(?:\bif\s*\(|\bwhile\s*\(|!|\?\s*|&&|\|\|)\s*$', pre) or \
                            re.match(r'\s*\?', after):
                        why = 'used as a bool condition'
                    elif re.search(r'[+\-*/]\s*$', pre) or re.match(r'\s*[+\-*/<>]=?', after):
                        why = 'used in arithmetic/comparison'
                if why:
                    findings.append((f, idx, label, typ, why, line.strip()[:96]))
    return findings


if __name__ == '__main__':
    sys.exit(main())

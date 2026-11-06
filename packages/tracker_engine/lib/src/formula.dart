import 'dart:math' as math;

import 'property.dart';

/// Formula language: literals, `prop("…")`, arithmetic, comparison, if/and/or/not, text, math,
/// date and list functions. No I/O, no recursion, bounded evaluation (see [FormulaLimits]).
///
/// Persisted source references properties by **id** (`prop("p_abc")`) so renames are safe;
/// [displayFormula]/[canonicalizeFormula] convert to and from names for the editor.

class FormulaError {
  const FormulaError(this.code, [this.detail]);
  final String code; // '#SYNTAX' '#REF' '#TYPE' '#DIV0' '#LIMIT' '#ARGS' '#NAME'
  final String? detail;
  @override
  String toString() => detail == null ? code : '$code: $detail';
  @override
  bool operator ==(Object other) => other is FormulaError && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

class FormulaSyntaxException implements Exception {
  FormulaSyntaxException(this.message, this.offset);
  final String message;
  final int offset;
  @override
  String toString() => 'Syntax error at $offset: $message';
}

abstract final class FormulaLimits {
  static const maxSteps = 20000;
  static const maxDepth = 64;
  static const maxSourceLength = 4000;
}

// ---------------------------------------------------------------- lexer
enum _T { num, str, ident, op, lparen, rparen, comma, eof }

class _Tok {
  _Tok(this.t, this.text, this.start, this.end, [this.value]);
  final _T t;
  final String text;
  final int start, end;
  final Object? value;
}

List<_Tok> _lex(String s) {
  if (s.length > FormulaLimits.maxSourceLength) throw FormulaSyntaxException('Formula is too long', 0);
  final out = <_Tok>[];
  var i = 0;
  bool isId(int c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || (c >= 48 && c <= 57);
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == 32 || c == 9 || c == 10 || c == 13) {
      i++;
    } else if ((c >= 48 && c <= 57) || (c == 46 && i + 1 < s.length && s.codeUnitAt(i + 1) >= 48 && s.codeUnitAt(i + 1) <= 57)) {
      final m = RegExp(r'\d*\.?\d+(?:[eE][+-]?\d+)?|\d+\.').matchAsPrefix(s, i)!;
      out.add(_Tok(_T.num, m[0]!, i, m.end, double.parse(m[0]!)));
      i = m.end;
    } else if (c == 34 || c == 39) {
      final q = c;
      final b = StringBuffer();
      var j = i + 1;
      var closed = false;
      while (j < s.length) {
        final d = s.codeUnitAt(j);
        if (d == 92 && j + 1 < s.length) {
          final n = s[j + 1];
          b.write(n == 'n' ? '\n' : n == 't' ? '\t' : n);
          j += 2;
        } else if (d == q) {
          closed = true;
          j++;
          break;
        } else {
          b.writeCharCode(d);
          j++;
        }
      }
      if (!closed) throw FormulaSyntaxException('Unterminated text', i);
      out.add(_Tok(_T.str, s.substring(i, j), i, j, b.toString()));
      i = j;
    } else if (isId(c) && !(c >= 48 && c <= 57)) {
      var j = i;
      while (j < s.length && isId(s.codeUnitAt(j))) {
        j++;
      }
      out.add(_Tok(_T.ident, s.substring(i, j), i, j));
      i = j;
    } else if (c == 40) {
      out.add(_Tok(_T.lparen, '(', i, ++i));
    } else if (c == 41) {
      out.add(_Tok(_T.rparen, ')', i, ++i));
    } else if (c == 44) {
      out.add(_Tok(_T.comma, ',', i, ++i));
    } else {
      final two = i + 1 < s.length ? s.substring(i, i + 2) : '';
      if (const {'==', '!=', '<>', '<=', '>=', '&&', '||'}.contains(two)) {
        out.add(_Tok(_T.op, two, i, i + 2));
        i += 2;
      } else if ('+-*/%<>=!'.contains(s[i])) {
        out.add(_Tok(_T.op, s[i], i, i + 1));
        i++;
      } else {
        throw FormulaSyntaxException('Unexpected "${s[i]}"', i);
      }
    }
  }
  out.add(_Tok(_T.eof, '', s.length, s.length));
  return out;
}

// ---------------------------------------------------------------- AST
sealed class Node {}

class Lit extends Node {
  Lit(this.value);
  final Object? value;
}

class Call extends Node {
  Call(this.name, this.args);
  final String name;
  final List<Node> args;
}

class Unary extends Node {
  Unary(this.op, this.arg);
  final String op;
  final Node arg;
}

class Binary extends Node {
  Binary(this.op, this.l, this.r);
  final String op;
  final Node l, r;
}

class _Parser {
  _Parser(this.toks);
  final List<_Tok> toks;
  var p = 0;
  var depth = 0;
  _Tok get cur => toks[p];

  Node parse() {
    final n = _or();
    if (cur.t != _T.eof) throw FormulaSyntaxException('Unexpected "${cur.text}"', cur.start);
    return n;
  }

  bool _isOp(String o) => cur.t == _T.op && cur.text == o;
  bool _isWord(String w) => cur.t == _T.ident && cur.text.toLowerCase() == w;

  Node _enter(Node Function() f) {
    if (++depth > FormulaLimits.maxDepth) throw FormulaSyntaxException('Formula is nested too deeply', cur.start);
    try {
      return f();
    } finally {
      depth--;
    }
  }

  Node _or() => _enter(() {
        var l = _and();
        while (_isOp('||') || _isWord('or')) {
          p++;
          l = Binary('or', l, _and());
        }
        return l;
      });

  Node _and() {
    var l = _not();
    while (_isOp('&&') || _isWord('and')) {
      p++;
      l = Binary('and', l, _not());
    }
    return l;
  }

  Node _not() => _enter(() {
        if (_isOp('!') || _isWord('not')) {
          p++;
          return Unary('not', _not());
        }
        return _cmp();
      });

  Node _cmp() {
    final l = _add();
    for (final o in const ['==', '=', '!=', '<>', '<=', '>=', '<', '>']) {
      if (_isOp(o)) {
        p++;
        final r = _add();
        return Binary(o == '=' ? '==' : o == '<>' ? '!=' : o, l, r);
      }
    }
    return l;
  }

  Node _add() {
    var l = _mul();
    while (_isOp('+') || _isOp('-')) {
      final o = cur.text;
      p++;
      l = Binary(o, l, _mul());
    }
    return l;
  }

  Node _mul() {
    var l = _unary();
    while (_isOp('*') || _isOp('/') || _isOp('%')) {
      final o = cur.text;
      p++;
      l = Binary(o, l, _unary());
    }
    return l;
  }

  Node _unary() => _enter(() {
        if (_isOp('-')) {
          p++;
          return Unary('-', _unary());
        }
        return _primary();
      });

  Node _primary() {
    final t = cur;
    switch (t.t) {
      case _T.num:
        p++;
        return Lit(t.value);
      case _T.str:
        p++;
        return Lit(t.value);
      case _T.lparen:
        p++;
        final e = _or();
        if (cur.t != _T.rparen) throw FormulaSyntaxException('Missing ")"', cur.start);
        p++;
        return e;
      case _T.ident:
        p++;
        final lower = t.text.toLowerCase();
        if (cur.t == _T.lparen) {
          p++;
          final args = <Node>[];
          if (cur.t != _T.rparen) {
            args.add(_or());
            while (cur.t == _T.comma) {
              p++;
              args.add(_or());
            }
          }
          if (cur.t != _T.rparen) throw FormulaSyntaxException('Missing ")" after arguments', cur.start);
          p++;
          return Call(lower, args);
        }
        if (lower == 'true') return Lit(true);
        if (lower == 'false') return Lit(false);
        if (lower == 'null' || lower == 'empty') return Lit(null);
        throw FormulaSyntaxException('Unknown name "${t.text}" (use prop("…") for properties)', t.start);
      default:
        throw FormulaSyntaxException(t.t == _T.eof ? 'Formula ended unexpectedly' : 'Unexpected "${t.text}"', t.start);
    }
  }
}

Node parseFormula(String source) => _Parser(_lex(source)).parse();

/// Property ids referenced by `prop("id")` calls.
Set<String> formulaDependencies(Node n) {
  final out = <String>{};
  void walk(Node x) {
    switch (x) {
      case Call c:
        if (c.name == 'prop' && c.args.length == 1 && c.args.first is Lit && (c.args.first as Lit).value is String) {
          out.add((c.args.first as Lit).value! as String);
        }
        c.args.forEach(walk);
      case Unary u:
        walk(u.arg);
      case Binary b:
        walk(b.l);
        walk(b.r);
      case Lit _:
    }
  }

  walk(n);
  return out;
}

/// Replace names with ids inside `prop("…")` (editor -> storage). Unknown names are left as written
/// so evaluation reports `#REF` instead of silently binding to something else.
String canonicalizeFormula(String source, List<PropertyDef> defs) => _mapPropArgs(source, (arg) {
      final byName = defs.where((d) => d.name == arg).toList();
      return byName.length == 1 ? byName.single.id : arg;
    });

/// Replace ids with names (storage -> editor).
String displayFormula(String source, List<PropertyDef> defs) => _mapPropArgs(source, (arg) {
      for (final d in defs) {
        if (d.id == arg) return d.name;
      }
      return arg;
    });

/// Rewrite every `prop("…")` argument through [f] (used when copying templates / duplicating trackers).
String remapFormulaRefs(String source, String Function(String) f) => _mapPropArgs(source, f);

String _mapPropArgs(String source, String Function(String) f) {
  final List<_Tok> toks;
  try {
    toks = _lex(source);
  } on FormulaSyntaxException {
    return source;
  }
  final edits = <(int, int, String)>[];
  for (var i = 0; i + 3 < toks.length; i++) {
    if (toks[i].t == _T.ident && toks[i].text.toLowerCase() == 'prop' && toks[i + 1].t == _T.lparen && toks[i + 2].t == _T.str && toks[i + 3].t == _T.rparen) {
      final arg = toks[i + 2].value! as String;
      final mapped = f(arg);
      if (mapped != arg) {
        final q = toks[i + 2].text[0];
        edits.add((toks[i + 2].start, toks[i + 2].end, '$q${mapped.replaceAll(r'\', r'\\').replaceAll(q, '\\$q')}$q'));
      }
    }
  }
  var out = source;
  for (final e in edits.reversed) {
    out = out.replaceRange(e.$1, e.$2, e.$3);
  }
  return out;
}

class FormulaCycleException implements Exception {
  FormulaCycleException(this.path);
  final List<String> path; // property names
  @override
  String toString() => 'Formulas reference each other in a loop: ${path.join(' → ')}';
}

/// Evaluation order for formula properties (dependencies first). Throws [FormulaCycleException].
List<PropertyDef> formulaOrder(List<PropertyDef> defs) {
  final formulas = {for (final d in defs.where((d) => d.type == PropertyType.formula)) d.id: d};
  final deps = <String, Set<String>>{};
  for (final f in formulas.values) {
    try {
      deps[f.id] = formulaDependencies(parseFormula(f.formulaSource)).where(formulas.containsKey).toSet();
    } on FormulaSyntaxException {
      deps[f.id] = {}; // reported when evaluated
    }
  }
  final order = <PropertyDef>[];
  final state = <String, int>{}; // 1 visiting, 2 done
  final stack = <String>[];
  void visit(String id) {
    if (state[id] == 2) return;
    if (state[id] == 1) {
      final cycle = [...stack.sublist(stack.indexOf(id)), id];
      throw FormulaCycleException([for (final c in cycle) formulas[c]!.name]);
    }
    state[id] = 1;
    stack.add(id);
    for (final d in deps[id]!) {
      visit(d);
    }
    stack.removeLast();
    state[id] = 2;
    order.add(formulas[id]!);
  }

  for (final id in formulas.keys) {
    visit(id);
  }
  return order;
}

// ---------------------------------------------------------------- evaluation
abstract interface class FormulaContext {
  /// Value of property [propertyId] for the current record, already in formula form
  /// (num, String, bool, DateTime(UTC), List, null) - or null if unknown id.
  Object? read(String propertyId);
  bool knows(String propertyId);
  DateTime get now;
}

class _Abort implements Exception {
  _Abort(this.error);
  final FormulaError error;
}

/// Evaluates [source]. Never throws: problems become a [FormulaError] result.
Object? evaluateFormula(String source, FormulaContext ctx) {
  final Node ast;
  try {
    ast = parseFormula(source);
  } on FormulaSyntaxException catch (e) {
    return FormulaError('#SYNTAX', e.message);
  }
  return evaluateNode(ast, ctx);
}

Object? evaluateNode(Node ast, FormulaContext ctx) {
  var steps = 0;
  Object? ev(Node n) {
    if (++steps > FormulaLimits.maxSteps) throw _Abort(const FormulaError('#LIMIT', 'Formula is too complex'));
    switch (n) {
      case Lit l:
        return l.value;
      case Unary u:
        final a = ev(u.arg);
        if (a is FormulaError) return a;
        if (u.op == '-') return a is num ? -a : const FormulaError('#TYPE', 'Can\'t negate non-number');
        return !_truthy(a);
      case Binary b:
        return _binary(b, ev);
      case Call c:
        return _call(c, ev, ctx);
    }
  }

  try {
    return ev(ast);
  } on _Abort catch (a) {
    return a.error;
  }
}

bool _truthy(Object? v) => v is bool ? v : (v is num ? v != 0 : (v is String ? v.isNotEmpty : (v is List ? v.isNotEmpty : v != null)));

Object? _binary(Binary b, Object? Function(Node) ev) {
  if (b.op == 'and') {
    final l = ev(b.l);
    if (l is FormulaError) return l;
    if (!_truthy(l)) return false;
    final r = ev(b.r);
    return r is FormulaError ? r : _truthy(r);
  }
  if (b.op == 'or') {
    final l = ev(b.l);
    if (l is FormulaError) return l;
    if (_truthy(l)) return true;
    final r = ev(b.r);
    return r is FormulaError ? r : _truthy(r);
  }
  final l = ev(b.l), r = ev(b.r);
  if (l is FormulaError) return l;
  if (r is FormulaError) return r;
  switch (b.op) {
    case '+':
      if (l is num && r is num) return l + r;
      if (l is String || r is String) return '${_str(l)}${_str(r)}';
      if (l is DateTime && r is num) return l.add(Duration(milliseconds: (r * 86400000).round()));
      return const FormulaError('#TYPE', 'Can\'t add these values');
    case '-':
      if (l is num && r is num) return l - r;
      if (l is DateTime && r is DateTime) return l.difference(r).inMilliseconds / 86400000;
      if (l is DateTime && r is num) return l.subtract(Duration(milliseconds: (r * 86400000).round()));
      return const FormulaError('#TYPE', 'Can\'t subtract these values');
    case '*':
      return l is num && r is num ? l * r : const FormulaError('#TYPE', 'Multiplication needs numbers');
    case '/':
      if (l is! num || r is! num) return const FormulaError('#TYPE', 'Division needs numbers');
      return r == 0 ? const FormulaError('#DIV0', 'Division by zero') : l / r;
    case '%':
      if (l is! num || r is! num) return const FormulaError('#TYPE', 'Modulo needs numbers');
      return r == 0 ? const FormulaError('#DIV0', 'Division by zero') : l % r;
    case '==':
      return _equals(l, r);
    case '!=':
      return !_equals(l, r);
    default:
      final c = _compare(l, r);
      if (c == null) return const FormulaError('#TYPE', 'Can\'t compare these values');
      return switch (b.op) { '<' => c < 0, '<=' => c <= 0, '>' => c > 0, _ => c >= 0 };
  }
}

bool _equals(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is String && b is String) return a == b;
  if (a is DateTime && b is DateTime) return a.isAtSameMomentAs(b);
  if (a is List && b is List) return a.length == b.length && List.generate(a.length, (i) => _equals(a[i], b[i])).every((x) => x);
  return a == b;
}

int? _compare(Object? a, Object? b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is DateTime && b is DateTime) return a.compareTo(b);
  if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
  return null;
}

String _str(Object? v) {
  if (v == null) return '';
  if (v is double) return v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt().toString() : v.toString();
  if (v is DateTime) return v.toIso8601String();
  if (v is List) return v.map(_str).join(', ');
  return v.toString();
}

Object? _call(Call c, Object? Function(Node) ev, FormulaContext ctx) {
  final name = c.name;
  FormulaError argErr(String m) => FormulaError('#ARGS', '$name: $m');

  if (name == 'prop') {
    if (c.args.length != 1 || c.args.first is! Lit || (c.args.first as Lit).value is! String) {
      return argErr('expects one property name in quotes');
    }
    final id = (c.args.first as Lit).value! as String;
    if (!ctx.knows(id)) return FormulaError('#REF', 'No property "$id"');
    final v = ctx.read(id);
    return v;
  }
  if (name == 'if') {
    if (c.args.length != 3) return argErr('needs (condition, then, else)');
    final cond = ev(c.args[0]);
    if (cond is FormulaError) return cond;
    return _truthy(cond) ? ev(c.args[1]) : ev(c.args[2]);
  }

  final args = <Object?>[];
  for (final a in c.args) {
    final v = ev(a);
    if (v is FormulaError) return v;
    args.add(v);
  }
  int n(int min, [int? max]) => (args.length >= min && args.length <= (max ?? min)) ? 0 : 1;
  List<num> nums() => [for (final a in args) ...(a is List ? a.whereType<num>() : a is num ? [a] : const <num>[])];

  switch (name) {
    case 'and':
      return args.every(_truthy);
    case 'or':
      return args.any(_truthy);
    case 'not':
      return n(1) != 0 ? argErr('needs 1 value') : !_truthy(args[0]);
    case 'concat':
      return args.map(_str).join();
    case 'length':
      if (n(1) != 0) return argErr('needs 1 value');
      return args[0] is List ? (args[0] as List).length : _str(args[0]).runes.length;
    case 'upper':
      return n(1) != 0 ? argErr('needs 1 value') : _str(args[0]).toUpperCase();
    case 'lower':
      return n(1) != 0 ? argErr('needs 1 value') : _str(args[0]).toLowerCase();
    case 'trim':
      return n(1) != 0 ? argErr('needs 1 value') : _str(args[0]).trim();
    case 'contains':
      if (n(2) != 0) return argErr('needs (text or list, search)');
      return args[0] is List ? (args[0] as List).any((e) => _equals(e, args[1])) : _str(args[0]).contains(_str(args[1]));
    case 'replace':
      return n(3) != 0 ? argErr('needs (text, find, replacement)') : _str(args[0]).replaceAll(_str(args[1]), _str(args[2]));
    case 'isempty':
      if (n(1) != 0) return argErr('needs 1 value');
      final v = args[0];
      return v == null || (v is String && v.isEmpty) || (v is List && v.isEmpty);
    case 'tonumber':
      if (n(1) != 0) return argErr('needs 1 value');
      final v = args[0];
      if (v is num) return v;
      return double.tryParse(_str(v).trim()) ?? const FormulaError('#TYPE', 'Not a number');
    case 'totext':
      return n(1) != 0 ? argErr('needs 1 value') : _str(args[0]);
    case 'round':
      if (n(1, 2) != 0 || args[0] is! num) return argErr('needs (number, [decimals])');
      final d = args.length > 1 && args[1] is num ? (args[1] as num).toInt() : 0;
      final f = math.pow(10, d).toDouble();
      return ((args[0] as num) * f).roundToDouble() / f;
    case 'floor':
      return n(1) != 0 || args[0] is! num ? argErr('needs 1 number') : (args[0] as num).floorToDouble();
    case 'ceil':
      return n(1) != 0 || args[0] is! num ? argErr('needs 1 number') : (args[0] as num).ceilToDouble();
    case 'abs':
      return n(1) != 0 || args[0] is! num ? argErr('needs 1 number') : (args[0] as num).abs();
    case 'sqrt':
      if (n(1) != 0 || args[0] is! num) return argErr('needs 1 number');
      return (args[0] as num) < 0 ? const FormulaError('#TYPE', 'sqrt of negative') : math.sqrt(args[0] as num);
    case 'pow':
      return n(2) != 0 || args[0] is! num || args[1] is! num ? argErr('needs 2 numbers') : math.pow(args[0] as num, args[1] as num).toDouble();
    case 'min':
      final v = nums();
      return v.isEmpty ? null : v.reduce(math.min);
    case 'max':
      final v = nums();
      return v.isEmpty ? null : v.reduce(math.max);
    case 'sum':
      return nums().fold<num>(0, (a, b) => a + b);
    case 'avg':
      final v = nums();
      return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    case 'count':
      return args.fold<int>(0, (a, b) => a + (b is List ? b.where((e) => e != null).length : (b == null ? 0 : 1)));
    case 'join':
      if (n(1, 2) != 0 || args[0] is! List) return argErr('needs (list, [separator])');
      return (args[0] as List).map(_str).join(args.length > 1 ? _str(args[1]) : ', ');
    case 'now':
      return ctx.now;
    case 'today':
      final t = ctx.now;
      return DateTime.utc(t.year, t.month, t.day);
    case 'dateadd':
      if (n(3) != 0 || args[0] is! DateTime || args[1] is! num) return argErr('needs (date, amount, unit)');
      return _dateAdd(args[0] as DateTime, (args[1] as num).toInt(), _str(args[2])) ?? argErr('unit must be days, weeks, months, years, hours or minutes');
    case 'datebetween':
      if (n(3) != 0 || args[0] is! DateTime || args[1] is! DateTime) return argErr('needs (date, date, unit)');
      return _dateBetween(args[0] as DateTime, args[1] as DateTime, _str(args[2])) ?? argErr('unit must be days, weeks, months, years, hours or minutes');
    case 'formatdate':
      if (n(1, 2) != 0 || args[0] is! DateTime) return argErr('needs (date, [format])');
      return _formatDate(args[0] as DateTime, args.length > 1 ? _str(args[1]) : 'YYYY-MM-DD');
    default:
      return FormulaError('#NAME', 'Unknown function "$name"');
  }
}

DateTime? _dateAdd(DateTime d, int n, String unit) {
  switch (unit.toLowerCase()) {
    case 'days':
    case 'day':
      return d.add(Duration(days: n));
    case 'weeks':
    case 'week':
      return d.add(Duration(days: 7 * n));
    case 'hours':
    case 'hour':
      return d.add(Duration(hours: n));
    case 'minutes':
    case 'minute':
      return d.add(Duration(minutes: n));
    case 'months':
    case 'month':
      final total = d.year * 12 + (d.month - 1) + n;
      final y = total ~/ 12, m = total % 12 + 1;
      final last = DateTime.utc(y, m + 1, 0).day; // clamp 31 Jan + 1 month -> 28/29 Feb
      return DateTime.utc(y, m, math.min(d.day, last), d.hour, d.minute, d.second);
    case 'years':
    case 'year':
      return _dateAdd(d, n * 12, 'months');
  }
  return null;
}

num? _dateBetween(DateTime a, DateTime b, String unit) {
  final diff = a.difference(b);
  switch (unit.toLowerCase()) {
    case 'days':
    case 'day':
      return (diff.inMilliseconds / 86400000).truncate();
    case 'weeks':
    case 'week':
      return (diff.inMilliseconds / (7 * 86400000)).truncate();
    case 'hours':
    case 'hour':
      return diff.inHours;
    case 'minutes':
    case 'minute':
      return diff.inMinutes;
    case 'months':
    case 'month':
      return (a.year - b.year) * 12 + (a.month - b.month) - (a.day < b.day && a.isAfter(b) ? 1 : 0) + (a.day > b.day && a.isBefore(b) ? 1 : 0);
    case 'years':
    case 'year':
      return (_dateBetween(a, b, 'months')! / 12).truncate();
  }
  return null;
}

String _formatDate(DateTime d, String f) {
  String two(int v) => v.toString().padLeft(2, '0');
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return f
      .replaceAll('YYYY', d.year.toString().padLeft(4, '0'))
      .replaceAll('MMM', months[d.month - 1])
      .replaceAll('MM', two(d.month))
      .replaceAll('DD', two(d.day))
      .replaceAll('HH', two(d.hour))
      .replaceAll('mm', two(d.minute));
}

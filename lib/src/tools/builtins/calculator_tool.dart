import '../agentic_tool.dart';
import '../tool_param.dart';

/// Evaluates arithmetic expressions: +, -, *, /, ^ (power), % (modulo),
/// parentheses, and common constants (pi, e).
///
/// Zero dependencies, works on all platforms.
///
/// Usage:
/// ```dart
/// tools: [AgenticTools.calculator]
/// ```
///
/// Agent can then answer: "What is 15% of 2340?" or "sqrt of 144?"
final AgenticTool calculatorTool = AgenticTool.define(
  name: 'calculate',
  description:
      'Evaluates mathematical expressions. Supports +, -, *, /, '
      '^ (power), % (modulo), parentheses, sqrt(), abs(), and constants pi and e. '
      'Always use this tool for any numerical calculation instead of guessing.',
  params: {
    'expression': ToolParam.string(
      description:
          'The math expression to evaluate, e.g. "sqrt(144)" or "15/100 * 2340"',
      required: true,
    ),
  },
  execute: (args) async {
    final expr = args['expression'] as String;
    try {
      final result = _ExprParser(expr.replaceAll(' ', '')).parse();
      final display = result == result.truncateToDouble()
          ? result.toInt().toString()
          : double.parse(result.toStringAsFixed(10))
              .toString()
              .replaceAll(RegExp(r'0+$'), '');
      return {'result': display, 'expression': expr};
    } catch (e) {
      return {
        'error': 'Could not evaluate "$expr". '
            'Check the expression format. ($e)'
      };
    }
  },
);

// ── Parser ──────────────────────────────────────────────────────────────────

class _ExprParser {
  final String src;
  int _pos = 0;

  _ExprParser(this.src);

  double parse() {
    final v = _expr();
    if (_pos != src.length) {
      throw FormatException('Unexpected token at position $_pos: "${src[_pos]}"');
    }
    return v;
  }

  double _expr() => _addSub();

  double _addSub() {
    var v = _mulDiv();
    while (_pos < src.length && (src[_pos] == '+' || src[_pos] == '-')) {
      final op = src[_pos++];
      final r = _mulDiv();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _mulDiv() {
    var v = _power();
    while (_pos < src.length &&
        (src[_pos] == '*' || src[_pos] == '/' || src[_pos] == '%')) {
      final op = src[_pos++];
      final r = _power();
      v = op == '*'
          ? v * r
          : op == '/'
              ? v / r
              : v % r;
    }
    return v;
  }

  double _power() {
    var base = _unary();
    if (_pos < src.length && src[_pos] == '^') {
      _pos++;
      final exp = _unary();
      base = _pow(base, exp);
    }
    return base;
  }

  double _unary() {
    if (_pos < src.length && src[_pos] == '-') {
      _pos++;
      return -_primary();
    }
    if (_pos < src.length && src[_pos] == '+') {
      _pos++;
    }
    return _primary();
  }

  double _primary() {
    // Parenthesised expression
    if (_pos < src.length && src[_pos] == '(') {
      _pos++;
      final v = _expr();
      if (_pos < src.length && src[_pos] == ')') _pos++;
      return v;
    }
    // Named functions and constants
    if (_pos < src.length && RegExp(r'[a-zA-Z]').hasMatch(src[_pos])) {
      return _nameOrFn();
    }
    return _number();
  }

  double _nameOrFn() {
    final start = _pos;
    while (_pos < src.length && RegExp(r'[a-zA-Z0-9_]').hasMatch(src[_pos])) {
      _pos++;
    }
    final name = src.substring(start, _pos).toLowerCase();

    // Function call: name(expr)
    if (_pos < src.length && src[_pos] == '(') {
      _pos++; // consume '('
      final arg = _expr();
      if (_pos < src.length && src[_pos] == ')') _pos++;
      return switch (name) {
        'sqrt' => _sqrt(arg),
        'abs' => arg.abs(),
        'ceil' => arg.ceilToDouble(),
        'floor' => arg.floorToDouble(),
        'round' => arg.roundToDouble(),
        'log' => _log(arg),
        'log2' => _log(arg) / _log(2),
        'log10' => _log(arg) / _log(10),
        'sin' => _sin(arg),
        'cos' => _cos(arg),
        'tan' => _tan(arg),
        _ => throw FormatException('Unknown function: $name'),
      };
    }

    // Constants
    return switch (name) {
      'pi' || 'π' => 3.141592653589793,
      'e' => 2.718281828459045,
      'inf' || 'infinity' => double.infinity,
      _ => throw FormatException('Unknown constant: $name'),
    };
  }

  double _number() {
    final start = _pos;
    if (_pos < src.length && (src[_pos] == '-' || src[_pos] == '+')) _pos++;
    while (_pos < src.length && RegExp(r'[0-9.]').hasMatch(src[_pos])) {
      _pos++;
    }
    // Scientific notation: 1.5e10
    if (_pos < src.length && (src[_pos] == 'e' || src[_pos] == 'E')) {
      _pos++;
      if (_pos < src.length && (src[_pos] == '+' || src[_pos] == '-')) _pos++;
      while (_pos < src.length && RegExp(r'[0-9]').hasMatch(src[_pos])) {
        _pos++;
      }
    }
    if (_pos == start) {
      throw FormatException('Expected number at position $_pos');
    }
    return double.parse(src.substring(start, _pos));
  }

  // Dart's dart:math is not available without importing — use inline impls
  double _sqrt(double x) {
    if (x < 0) throw FormatException('sqrt of negative number');
    if (x == 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 100; i++) {
      final next = (guess + x / guess) / 2;
      if ((next - guess).abs() < 1e-12) return next;
      guess = next;
    }
    return guess;
  }

  double _pow(double base, double exp) {
    if (exp == 0) return 1;
    if (exp == 1) return base;
    if (exp == 0.5) return _sqrt(base);
    // Integer exponent fast path
    if (exp == exp.truncateToDouble() && exp > 0 && exp < 1000) {
      double result = 1;
      for (int i = 0; i < exp.toInt(); i++) { result *= base; }
      return result;
    }
    // x^y = e^(y*ln(x))
    return _exp(exp * _log(base));
  }

  // Taylor series approximations for transcendentals
  double _log(double x) {
    if (x <= 0) throw FormatException('log of non-positive number');
    // Use ln(x) = 2*atanh((x-1)/(x+1))
    double y = (x - 1) / (x + 1);
    double result = 0;
    for (int n = 0; n < 100; n++) {
      result += _pow(y, (2 * n + 1).toDouble()) / (2 * n + 1);
    }
    return 2 * result;
  }

  double _exp(double x) {
    double sum = 1, term = 1;
    for (int n = 1; n < 100; n++) {
      term *= x / n;
      sum += term;
      if (term.abs() < 1e-15) break;
    }
    return sum;
  }

  double _sin(double x) {
    // Reduce to [-pi, pi]
    const pi = 3.141592653589793;
    x = x % (2 * pi);
    double sum = 0, term = x;
    for (int n = 1; n < 20; n++) {
      sum += term;
      term *= (-x * x) / ((2 * n) * (2 * n + 1));
    }
    return sum;
  }

  double _cos(double x) => _sin(3.141592653589793 / 2 - x);

  double _tan(double x) {
    final c = _cos(x);
    if (c.abs() < 1e-10) throw FormatException('tan undefined at $x');
    return _sin(x) / c;
  }
}

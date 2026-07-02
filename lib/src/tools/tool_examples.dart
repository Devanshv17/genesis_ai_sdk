// ignore_for_file: unused_element
/// Developer reference: real-world tool patterns for flutter_agentic.
///
/// Copy-paste any example as your starting point.
/// All examples compile and use only the public SDK API.
///
/// Patterns covered:
///  1. Simple lookup tool              [_simpleWeatherTool]
///  2. Tool with validation            [_validatingEmailTool]
///  3. Tool with optional params       [_searchTool]
///  4. Tool with nested object param   [_createOrderTool]
///  5. Tool with array param           [_bulkLookupTool]
///  6. Tool returning typed error      [_paymentTool]
///  7. Multi-step pipeline tool        [_documentAnalysisTool]
///  8. Tool with progress reporting    [_longRunningTool]
///  9. Stateful tool (closure capture) [_counterTool]
/// 10. Tool composed of other tools    [_composedTool]
library;

import 'package:flutter_agentic/flutter_agentic.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. Simple lookup tool
// The most common pattern: take a few string params, call an API, return data.
// ─────────────────────────────────────────────────────────────────────────────
final _simpleWeatherTool = AgenticTool.define(
  name: 'get_weather',
  description: 'Returns current weather conditions for a city. '
      'Call this whenever the user asks about weather or temperature.',
  params: {
    'city': ToolParam.string(
        description: 'City name, e.g. "Mumbai" or "New York"', required: true),
    'unit': ToolParam.stringEnum(
      ['celsius', 'fahrenheit'],
      description: 'Temperature unit. Default: celsius.',
    ),
  },
  execute: (args) async {
    final city = args['city'] as String;
    final unit = args['unit'] as String? ?? 'celsius';
    // Replace with a real weather API call:
    return {
      'city': city,
      'temperature': unit == 'celsius' ? 28 : 82,
      'unit': unit,
      'condition': 'Sunny',
    };
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// 2. Tool with input validation (rich context version)
// Use ToolArgs for safe typed access and ToolResult for structured errors.
// ─────────────────────────────────────────────────────────────────────────────
final _validatingEmailTool = AgenticTool.withContext(
  name: 'send_email',
  description: 'Sends an email to a recipient. '
      'Requires a valid email address and a non-empty subject.',
  params: {
    'to': ToolParam.string(
        description: 'Recipient email address', required: true),
    'subject': ToolParam.string(description: 'Email subject', required: true),
    'body': ToolParam.string(description: 'Email body (plain text)'),
    'html': ToolParam.boolean(description: 'Set true to send as HTML'),
  },
  execute: (args, ctx) async {
    final to = args.string('to');
    final subject = args.string('subject');
    ctx.log('Sending email to $to');

    // ── Validate ──────────────────────────────────────────────────────────
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(to)) {
      return ToolError(
        '"$to" is not a valid email address.',
        code: 'INVALID_EMAIL',
      );
    }
    if (subject.trim().isEmpty) {
      return ToolError('Subject must not be empty.', code: 'MISSING_SUBJECT');
    }

    // ── Execute ───────────────────────────────────────────────────────────
    ctx.progress(50, 'Sending...');
    // await emailService.send(to: to, subject: subject, body: args.string('body'));
    ctx.progress(100, 'Sent');

    return ToolSuccess({
      'status': 'sent',
      'to': to,
      'subject': subject,
      'message_id': 'msg_${DateTime.now().millisecondsSinceEpoch}',
    });
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// 3. Tool with optional params + enum filtering
// ─────────────────────────────────────────────────────────────────────────────
final _searchTool = AgenticTool.withContext(
  name: 'search_products',
  description: 'Searches the product catalogue. '
      'Use when the user wants to find, browse, or compare products.',
  params: {
    'query': ToolParam.string(description: 'Search terms', required: true),
    'category': ToolParam.stringEnum(
      ['electronics', 'clothing', 'books', 'home', 'sports'],
      description: 'Filter by category. Omit to search all.',
    ),
    'max_price': ToolParam.number(
        description: 'Maximum price in USD. Omit for no limit.'),
    'limit': ToolParam.integer(
        description: 'Max results to return (1–50). Default: 10.'),
    'in_stock_only': ToolParam.boolean(
        description: 'If true, only return in-stock items.'),
  },
  execute: (args, ctx) async {
    final query = args.string('query');
    final limit = args.integer('limit', fallback: 10).clamp(1, 50);
    final maxPrice = args.optional<double>('max_price');
    final category = args.optional<String>('category');
    ctx.log('Searching "$query" | cat=$category max=\$$maxPrice limit=$limit inStock=${args.boolean("in_stock_only")}');
    ctx.progress(0, 'Querying catalogue...');

    // Replace with real DB/search call:
    final results = <Map<String, dynamic>>[
      {'id': '1', 'name': 'Example Product', 'price': 29.99, 'in_stock': true},
    ];

    ctx.progress(100, 'Found ${results.length} results');
    return ToolSuccess({
      'results': results,
      'total_found': results.length,
      'query': query,
      if (category != null) 'category_filter': category,
      if (maxPrice != null) 'max_price_filter': maxPrice,
    });
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// 4. Tool with nested object parameter
// The `address` param is itself an object with its own typed fields.
// ─────────────────────────────────────────────────────────────────────────────
final _createOrderTool = AgenticTool.withContext(
  name: 'create_order',
  description: 'Creates a new order in the system.',
  params: {
    'product_id': ToolParam.string(description: 'Product ID', required: true),
    'quantity': ToolParam.integer(description: 'Units to order', required: true),
    'shipping_address': ToolParam.object(
      description: 'Delivery address',
      required: true,
      properties: {
        'street': ToolParam.string(description: 'Street line', required: true),
        'city': ToolParam.string(description: 'City', required: true),
        'country': ToolParam.string(
            description: 'ISO 2-letter country code', required: true),
        'postal_code': ToolParam.string(description: 'ZIP / postal code'),
      },
    ),
  },
  execute: (args, ctx) async {
    final productId = args.string('product_id');
    final quantity  = args.integer('quantity', fallback: 1);
    final address   = args.nested('shipping_address'); // ToolArgs accessor

    final city    = address.string('city');
    final country = address.string('country');
    ctx.log('Order: $quantity × $productId → $city, $country');

    if (quantity < 1) {
      return ToolError('Quantity must be at least 1.', code: 'INVALID_QTY');
    }

    return ToolSuccess({
      'order_id': 'ord_${DateTime.now().millisecondsSinceEpoch}',
      'product_id': productId,
      'quantity': quantity,
      'shipping_to': '$city, $country',
      'status': 'created',
    });
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// 5. Tool with array parameter
// Accepts a list of IDs and looks them all up in one call.
// ─────────────────────────────────────────────────────────────────────────────
final _bulkLookupTool = AgenticTool.withContext(
  name: 'bulk_user_lookup',
  description: 'Looks up multiple users by their IDs in a single call.',
  params: {
    'user_ids': ToolParam.array(
      description: 'List of user IDs to look up',
      required: true,
      items: ToolParam.string(description: 'A user ID'),
    ),
    'fields': ToolParam.array(
      description: 'Which fields to return. Defaults to ["name","email"].',
      items: ToolParam.stringEnum(
        ['id', 'name', 'email', 'role', 'created_at'],
        description: 'A field name',
      ),
    ),
  },
  execute: (args, ctx) async {
    final ids    = args.list<String>('user_ids');
    final fields = args.list<String>('fields');
    final wantedFields = fields.isEmpty ? ['name', 'email'] : fields;

    ctx.log('Looking up ${ids.length} users, fields: $wantedFields');
    if (ids.isEmpty) return ToolError('user_ids must not be empty.', code: 'EMPTY_LIST');
    if (ids.length > 100) {
      return ToolError('Max 100 IDs per call. Got ${ids.length}.', code: 'LIMIT_EXCEEDED');
    }

    // Replace with real bulk DB query:
    final users = ids.map((id) => {
      'id': id,
      if (wantedFields.contains('name')) 'name': 'User $id',
      if (wantedFields.contains('email')) 'email': '$id@example.com',
    }).toList();

    return ToolSuccess({'users': users, 'count': users.length});
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// 6. Tool with typed error codes the agent can reason about
// ─────────────────────────────────────────────────────────────────────────────
final _paymentTool = AgenticTool.withContext(
  name: 'charge_card',
  description: 'Charges a payment card. Returns a charge ID on success.',
  params: {
    'amount_cents': ToolParam.integer(
        description: 'Amount to charge in cents (e.g. 999 = \$9.99)',
        required: true),
    'card_token': ToolParam.string(
        description: 'Tokenised card reference from your payment gateway',
        required: true),
    'description': ToolParam.string(description: 'Charge description'),
  },
  execute: (args, ctx) async {
    final amount = args.integer('amount_cents');
    final token  = args.string('card_token');

    if (amount <= 0) return ToolError('Amount must be > 0.', code: 'INVALID_AMOUNT');

    ctx.progress(30, 'Contacting payment gateway...');

    // Simulate payment errors for demo:
    if (token == 'declined') {
      return ToolError(
        'Card was declined by the issuing bank.',
        code: 'CARD_DECLINED',
      );
    }
    if (token == 'insufficient') {
      return ToolError(
        'Insufficient funds on the card.',
        code: 'INSUFFICIENT_FUNDS',
      );
    }

    ctx.progress(100, 'Charged');
    return ToolSuccess({
      'charge_id': 'ch_${DateTime.now().millisecondsSinceEpoch}',
      'amount_cents': amount,
      'status': 'succeeded',
    });
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// 7. Multi-step pipeline tool
// Fetches a URL, extracts text, counts words — three sequential steps.
// Each step can access outputs of all previous steps via the shared state.
// ─────────────────────────────────────────────────────────────────────────────
final _documentAnalysisTool = AgenticTool.pipeline(
  name: 'analyse_url',
  description: 'Fetches a URL and analyses its text content: '
      'word count, character count, and a preview.',
  params: {
    'url': ToolParam.string(
        description: 'The URL to fetch and analyse', required: true),
    'preview_chars': ToolParam.integer(
        description: 'How many characters of preview to return. Default: 300.'),
  },
  steps: [
    // ── Step 1: fetch ────────────────────────────────────────────────────
    PipelineStep(
      name: 'fetch',
      run: (state, ctx) async {
        final url = state['url'] as String;
        ctx.progress(10, 'Fetching $url...');

        // In production, use HttpTool or your own http client:
        // final response = await http.get(Uri.parse(url));
        // Simulated for the example:
        final fakeHtml = '<html><body><p>Hello from $url. '
            'This is sample content.</p></body></html>';

        if (fakeHtml.isEmpty) throw ToolStepException('URL returned empty response');
        return {'raw_html': fakeHtml};
      },
    ),
    // ── Step 2: extract text ─────────────────────────────────────────────
    PipelineStep(
      name: 'extract',
      run: (state, ctx) async {
        ctx.progress(50, 'Extracting text...');
        final html = state['raw_html'] as String;
        // Strip HTML tags (simple; use html package for production):
        final text = html.replaceAll(RegExp(r'<[^>]+>'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        return {'text': text};
      },
    ),
    // ── Step 3: analyse ──────────────────────────────────────────────────
    PipelineStep(
      name: 'analyse',
      run: (state, ctx) async {
        ctx.progress(90, 'Analysing...');
        final text    = state['text'] as String;
        final preview = (state['preview_chars'] as int? ?? 300).clamp(0, text.length);
        ctx.progress(100, 'Done');
        // Return only the final output — not the raw intermediate data
        return {
          'word_count': text.split(RegExp(r'\s+')).length,
          'char_count': text.length,
          'preview': text.substring(0, preview),
          'url': state['url'],
        };
      },
    ),
  ],
);

// ─────────────────────────────────────────────────────────────────────────────
// 8. Long-running tool with progress reporting
// Progress updates surface in the agent's onStep callback.
// ─────────────────────────────────────────────────────────────────────────────
final _longRunningTool = AgenticTool.withContext(
  name: 'generate_report',
  description: 'Generates a detailed sales report for a date range. '
      'This takes a few seconds.',
  params: {
    'start_date': ToolParam.string(
        description: 'Start date ISO 8601 (e.g. 2025-01-01)', required: true),
    'end_date': ToolParam.string(
        description: 'End date ISO 8601 (e.g. 2025-12-31)', required: true),
    'format': ToolParam.stringEnum(
      ['summary', 'detailed', 'csv'],
      description: 'Report format',
    ),
  },
  execute: (args, ctx) async {
    final start  = args.string('start_date');
    final end    = args.string('end_date');
    final format = args.oneOf('format', ['summary', 'detailed', 'csv'], fallback: 'summary');

    ctx.log('Generating $format report: $start → $end');

    ctx.progress(10, 'Querying sales database...');
    await Future<void>.delayed(const Duration(milliseconds: 200)); // sim latency

    ctx.progress(40, 'Aggregating by product...');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    ctx.progress(70, 'Formatting output...');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    ctx.progress(100, 'Report ready');
    return ToolSuccess({
      'report_id': 'rpt_${DateTime.now().millisecondsSinceEpoch}',
      'format': format,
      'period': '$start to $end',
      'total_sales': 42_350.75,
      'top_product': 'Widget Pro',
      'download_url': 'https://your-app.com/reports/latest.$format',
    });
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// 9. Stateful tool via closure capture
// Useful for tools that maintain counters, caches, or rate-limit state.
// ─────────────────────────────────────────────────────────────────────────────
AgenticTool buildCounterTool() {
  var count = 0; // state captured in closure

  return AgenticTool.withContext(
    name: 'session_counter',
    description: 'Increments and returns a session counter. '
        'Use to track how many times something has been done.',
    params: {
      'increment_by': ToolParam.integer(
          description: 'Amount to add (default 1)'),
    },
    execute: (args, ctx) async {
      final by = args.integer('increment_by', fallback: 1);
      count += by;
      ctx.log('Counter: $count (added $by)');
      return ToolSuccess({'count': count, 'added': by});
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 10. Composed tool — one tool calls logic from another
// ─────────────────────────────────────────────────────────────────────────────
final _composedTool = AgenticTool.withContext(
  name: 'order_with_weather',
  description: 'Creates an order AND includes local weather at the destination.',
  params: {
    'product_id': ToolParam.string(description: 'Product ID', required: true),
    'city': ToolParam.string(description: 'Destination city', required: true),
  },
  execute: (args, ctx) async {
    final productId = args.string('product_id');
    final city      = args.string('city');

    ctx.progress(20, 'Fetching weather...');
    // Reuse logic from another tool's execute directly:
    final weather = await _simpleWeatherTool.execute({'city': city, 'unit': 'celsius'});

    ctx.progress(60, 'Creating order...');
    // Or call sub-steps inline:
    final orderId = 'ord_${DateTime.now().millisecondsSinceEpoch}';

    ctx.progress(100, 'Done');
    return ToolSuccess({
      'order_id': orderId,
      'product_id': productId,
      'destination': city,
      'weather_at_destination': weather,
    });
  },
);

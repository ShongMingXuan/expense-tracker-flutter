import 'dart:convert';
import 'package:http/http.dart' as http;

// ============================================================
// API SERVICE - isolates all network/HTTP logic, same principle
// as DatabaseHelper isolating all SQL logic. The rest of the app
// should never need to know HTTP or JSON exist.
// ============================================================
class ExchangeRateService {
  // A free, no-API-key-needed endpoint - good for learning/testing,
  // real production apps would typically need an API key + auth.
  static const String _baseUrl = 'https://open.er-api.com/v6/latest/USD';

  // The return type Future<Map<String, double>> is an honest promise:
  // "eventually, either a Map of currency->rate, OR this throws."
  Future<Map<String, double>> fetchRates() async {
    final response = await http.get(Uri.parse(_baseUrl));

    // HTTP status codes: 200 means success. Anything else (404, 500,
    // etc.) means something went wrong - we throw our OWN exception
    // here rather than pretending the call succeeded.
    if (response.statusCode != 200) {
      throw Exception('Failed to load exchange rates (status ${response.statusCode})');
    }

    // response.body is a raw JSON STRING at this point - jsonDecode
    // parses it into actual Dart objects (Map/List/String/num).
    final Map<String, dynamic> data = jsonDecode(response.body);

    // The API nests actual rates inside a "rates" key - this is
    // specific to THIS api's response shape, which you'd only know
    // by reading its documentation or inspecting a sample response.
    final Map<String, dynamic> rawRates = data['rates'];

    // Convert Map<String, dynamic> into a properly-typed
    // Map<String, double> - dynamic values from JSON need explicit
    // casting/conversion before you can treat them as a specific type.
    return rawRates.map((key, value) => MapEntry(key, (value as num).toDouble()));
  }

  // NEW: the API only ever gives us USD-based rates (1 USD = ? X),
  // but our app's base currency is MYR now. This re-derives every
  // rate as "1 [baseCurrency] = ? X" using cross-multiplication:
  //   1 USD = rawRates['MYR'] MYR   ...and...   1 USD = rawRates['EUR'] EUR
  //   => 1 MYR = rawRates['EUR'] / rawRates['MYR']  EUR
  // Dividing every USD-based rate by the USD->base rate re-bases
  // the whole table in one pass, without a second network call.
  Future<Map<String, double>> fetchRatesRelativeTo(String baseCurrency) async {
    final usdBasedRates = await fetchRates();

    final baseRate = usdBasedRates[baseCurrency];
    if (baseRate == null) {
      throw Exception('Base currency "$baseCurrency" not found in API response');
    }

    return usdBasedRates.map((currency, usdRate) {
      return MapEntry(currency, usdRate / baseRate);
    });
  }
}
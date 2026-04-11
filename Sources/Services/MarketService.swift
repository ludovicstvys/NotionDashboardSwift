import Foundation

struct MarketService {
  func fetchQuotes(symbols: [String]) async throws -> [MarketQuote] {
    guard !symbols.isEmpty else { return [] }
    let joined = symbols.joined(separator: ",")
    var components = URLComponents(string: "https://query1.finance.yahoo.com/v7/finance/quote")
    components?.queryItems = [.init(name: "symbols", value: joined)]
    guard let url = components?.url else { return [] }

    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }

    guard
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let quoteResponse = object["quoteResponse"] as? [String: Any],
      let results = quoteResponse["result"] as? [[String: Any]]
    else {
      return []
    }

    return results.compactMap { row in
      guard let symbol = row["symbol"] as? String else { return nil }
      let shortName = (row["shortName"] as? String) ?? (row["longName"] as? String) ?? symbol
      let price = (row["regularMarketPrice"] as? NSNumber)?.doubleValue ?? 0
      let changePercent = (row["regularMarketChangePercent"] as? NSNumber)?.doubleValue ?? 0
      let marketTimeUnix = (row["regularMarketTime"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
      return MarketQuote(
        symbol: symbol,
        shortName: shortName,
        price: price,
        changePercent: changePercent,
        marketTime: Date(timeIntervalSince1970: marketTimeUnix)
      )
    }
  }
}

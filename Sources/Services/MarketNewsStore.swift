import Foundation
import SwiftUI

private struct MarketNewsSnapshot: Codable {
  var news: [NewsItem]
  var quotes: [MarketQuote]
  var lastRefreshDate: Date?
}

@MainActor
final class MarketNewsStore: ObservableObject {
  @Published private(set) var news: [NewsItem] = []
  @Published private(set) var quotes: [MarketQuote] = []
  @Published var isLoadingNews: Bool = false
  @Published var isLoadingQuotes: Bool = false
  @Published var statusMessage: String = ""
  @Published private(set) var lastRefreshDate: Date?

  private let cacheStorageKey = "swift_notion_dashboard_market_news_cache_v1"
  private let staleInterval: TimeInterval = 15 * 60
  private let defaults: UserDefaults
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let newsService: NewsService
  private let marketService: MarketService
  private let persistenceScheduler = DebouncedWorkScheduler(
    label: "com.loldashboard.notiondashboard.market-news-persist",
    delay: 0.2
  )
  private weak var configStore: ConfigStore?
  private weak var diagnostics: DiagnosticsStore?
  private var isRefreshing = false

  init(
    configStore: ConfigStore,
    diagnostics: DiagnosticsStore?,
    defaults: UserDefaults = .standard,
    newsService: NewsService = NewsService(),
    marketService: MarketService = MarketService()
  ) {
    self.configStore = configStore
    self.diagnostics = diagnostics
    self.defaults = defaults
    self.newsService = newsService
    self.marketService = marketService

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder

    loadCache()
  }

  func prepareForLaunch(force: Bool = false) async {
    guard force || shouldRefreshAtLaunch else { return }
    await refreshAll()
  }

  func refreshAll() async {
    guard let configStore else { return }
    guard !isRefreshing else { return }

    let config = configStore.config
    let newsEnabled = config.newsEnabled
    let marketsEnabled = config.marketsEnabled
    let marketSymbols = config.marketSymbols

    isRefreshing = true
    isLoadingNews = newsEnabled
    isLoadingQuotes = marketsEnabled
    defer {
      isRefreshing = false
      isLoadingNews = false
      isLoadingQuotes = false
    }

    async let newsResult = fetchNews(enabled: newsEnabled)
    async let quoteResult = fetchQuotes(enabled: marketsEnabled, symbols: marketSymbols)

    let resolvedNews = await newsResult
    let resolvedQuotes = await quoteResult

    var fragments: [String] = []

    switch resolvedNews {
    case let .success(items):
      news = items
      fragments.append("News: \(items.count)")
      diagnostics?.log(category: "news", message: "News refreshed.", metadata: ["count": "\(items.count)"])
    case let .failure(error):
      statusMessage = "News refresh failed: \(error.localizedDescription)"
      fragments.append("News error")
      diagnostics?.log(
        severity: .warning,
        category: "news",
        message: statusMessage
      )
    case .none:
      news = []
    }

    switch resolvedQuotes {
    case let .success(items):
      quotes = items
      fragments.append("Quotes: \(items.count)")
      diagnostics?.log(category: "markets", message: "Quotes refreshed.", metadata: ["count": "\(items.count)"])
    case let .failure(error):
      statusMessage = "Quotes refresh failed: \(error.localizedDescription)"
      fragments.append("Quotes error")
      diagnostics?.log(
        severity: .warning,
        category: "markets",
        message: statusMessage
      )
    case .none:
      quotes = []
    }

    lastRefreshDate = Date()
    persistCache()

    if !fragments.isEmpty {
      statusMessage = fragments.joined(separator: " | ")
    }
  }

  func refreshNews() async {
    guard let configStore else { return }
    switch await fetchNews(enabled: configStore.config.newsEnabled) {
    case let .success(items):
      news = items
      lastRefreshDate = Date()
      persistCache()
      diagnostics?.log(category: "news", message: "News refreshed.", metadata: ["count": "\(items.count)"])
    case let .failure(error):
      statusMessage = "News refresh failed: \(error.localizedDescription)"
      diagnostics?.log(
        severity: .warning,
        category: "news",
        message: statusMessage
      )
    case .none:
      news = []
      lastRefreshDate = Date()
      persistCache()
    }
  }

  func refreshQuotes() async {
    guard let configStore else { return }
    switch await fetchQuotes(enabled: configStore.config.marketsEnabled, symbols: configStore.config.marketSymbols) {
    case let .success(items):
      quotes = items
      lastRefreshDate = Date()
      persistCache()
      diagnostics?.log(category: "markets", message: "Quotes refreshed.", metadata: ["count": "\(items.count)"])
    case let .failure(error):
      statusMessage = "Quotes refresh failed: \(error.localizedDescription)"
      diagnostics?.log(
        severity: .warning,
        category: "markets",
        message: statusMessage
      )
    case .none:
      quotes = []
      lastRefreshDate = Date()
      persistCache()
    }
  }

  private var shouldRefreshAtLaunch: Bool {
    if news.isEmpty && quotes.isEmpty {
      return true
    }
    guard let lastRefreshDate else { return true }
    return Date().timeIntervalSince(lastRefreshDate) >= staleInterval
  }

  private func fetchNews(enabled: Bool) async -> Result<[NewsItem], Error>? {
    guard enabled else { return nil }
    do {
      return .success(try await newsService.fetchTopNews(limit: 20))
    } catch {
      return .failure(error)
    }
  }

  private func fetchQuotes(enabled: Bool, symbols: [String]) async -> Result<[MarketQuote], Error>? {
    guard enabled else { return nil }
    do {
      return .success(try await marketService.fetchQuotes(symbols: symbols))
    } catch {
      return .failure(error)
    }
  }

  private func loadCache() {
    guard
      let data = defaults.data(forKey: cacheStorageKey),
      let snapshot = try? decoder.decode(MarketNewsSnapshot.self, from: data)
    else {
      return
    }

    news = snapshot.news
    quotes = snapshot.quotes
    lastRefreshDate = snapshot.lastRefreshDate
  }

  private func persistCache() {
    let snapshot = MarketNewsSnapshot(
      news: news,
      quotes: quotes,
      lastRefreshDate: lastRefreshDate
    )
    let defaults = self.defaults
    let cacheStorageKey = self.cacheStorageKey
    persistenceScheduler.schedule {
      let start = CFAbsoluteTimeGetCurrent()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      guard let data = try? encoder.encode(snapshot) else { return }
      defaults.set(data, forKey: cacheStorageKey)
      let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1_000
      PerformanceMonitor.recordPersistence(label: "MarketNewsStore.persistCache", durationMs: durationMs)
    }
  }
}

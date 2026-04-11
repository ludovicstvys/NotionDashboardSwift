import Foundation

struct NewsService {
  func fetchTopNews(limit: Int = 20) async throws -> [NewsItem] {
    let url = URL(string: "https://feeds.finance.yahoo.com/rss/2.0/headline?s=^GSPC&region=US&lang=en-US")!
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return NewsRSSParser.parse(data: data).prefix(limit).map { $0 }
  }
}

private final class NewsRSSParser: NSObject, XMLParserDelegate {
  private var items: [NewsItem] = []
  private var currentElement: String = ""
  private var currentTitle: String = ""
  private var currentLink: String = ""
  private var currentSource: String = ""
  private var currentDate: String = ""
  private var insideItem: Bool = false

  static func parse(data: Data) -> [NewsItem] {
    let parser = XMLParser(data: data)
    let delegate = NewsRSSParser()
    parser.delegate = delegate
    parser.parse()
    return delegate.items.sorted { $0.publishedAt > $1.publishedAt }
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    currentElement = elementName.lowercased()
    if currentElement == "item" {
      insideItem = true
      currentTitle = ""
      currentLink = ""
      currentSource = ""
      currentDate = ""
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard insideItem else { return }
    switch currentElement {
    case "title":
      currentTitle += string
    case "link":
      currentLink += string
    case "source":
      currentSource += string
    case "pubdate":
      currentDate += string
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
    if elementName.lowercased() == "item" {
      insideItem = false
      let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty, !link.isEmpty else { return }
      let source = currentSource.trimmingCharacters(in: .whitespacesAndNewlines)
      let publishedAt = parsePubDate(currentDate) ?? Date()
      items.append(
        NewsItem(
          id: link,
          title: title,
          link: link,
          source: source.isEmpty ? "Yahoo Finance" : source,
          publishedAt: publishedAt
        )
      )
    }
    currentElement = ""
  }

  private func parsePubDate(_ raw: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    return formatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

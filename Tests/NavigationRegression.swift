// Standalone regression harness for the Command Line Tools environment, which has no XCTest.
// These inert page identities replace network-facing models; navigation and filters are production code.
import Foundation

enum CollectionKind: Hashable {
    case pornstarsFemale, playlists, searchPornstars(String), searchPlaylists(String)
    var title: String { String(describing: self) }
}
struct UserLink: Hashable {
    struct Kind: Hashable { var label: String }
    var kind: Kind
}
struct Route: Hashable { let title: String; let path: String }

@main
struct NavigationRegression {
    @MainActor static func main() {
        let filters = FilterStore.shared
        filters.search("")
        let nav = NavState()
        let home = nav.tabs[0]
        filters.search("first query")
        nav.showSearchResults()
        let first = nav.tabs.last!
        filters.search("second query")
        nav.searchType = .playlists
        nav.showSearchResults()
        let second = nav.tabs.last!
        precondition(first.id != second.id, "Different searches must have different tabs")
        nav.select(first)
        precondition(filters.searchText == "first query" && nav.searchType == .videos)
        precondition(nav.section == .videos)
        nav.select(second)
        precondition(filters.searchText == "second query" && nav.searchType == .playlists)
        precondition(nav.section == .collection(.searchPlaylists("second query")))
        let tabCount = nav.tabs.count
        nav.showSearchResults()
        precondition(nav.tabs.count == tabCount, "Identical searches must reuse a tab")
        nav.close(second)
        precondition(nav.activeTabID == first.id && filters.searchText == "first query")
        nav.close(first)
        precondition(nav.activeTabID == home.id && filters.searchText.isEmpty)
        nav.close(home)
        precondition(nav.tabs.count == 1, "Last tab must remain open")
        nav.open(Route(title: "Channel", path: "/channel/test/"))
        let route = nav.tabs.last!
        nav.section = .best
        precondition(nav.path.isEmpty)
        nav.select(route)
        precondition(nav.path.count == 1 && nav.path[0].path == "/channel/test/")
        print("PASS: query/type restoration, search identity, deduplication, close selection, last-tab guard, route restoration")
    }
}

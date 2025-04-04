import UIKit
import Kingfisher
import Alamofire
import SwiftSoup
import SafariServices

class SearchResultsViewController: UIViewController {

    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private lazy var changeSourceButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Change Source", for: .normal)
        button.addTarget(self, action: #selector(changeSourceButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let errorLabel = UILabel()
    private let noResultsLabel = UILabel()

    var searchResults: [(title: String, imageUrl: String, href: String)] = []
    var filteredResults: [(title: String, imageUrl: String, href: String)] = []
    var query: String = ""
    // selectedSource seems redundant if UserDefaults is the source of truth. Can be removed if not used elsewhere.
    // var selectedSource: String = ""

    private lazy var sortButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: UIImage(systemName: "arrow.up.arrow.down"), style: .plain, target: self, action: #selector(sortButtonTapped))
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        setupUI()
        fetchResults()
    }

    private func setupUI() {
        navigationItem.largeTitleDisplayMode = .never // Keep titles small in results

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemBackground
        tableView.register(SearchResultCell.self, forCellReuseIdentifier: "resultCell")

        setupLoadingIndicator()
        setupErrorLabel()
        setupNoResultsLabel()

        // Show sort button based on the source that *was* selected for the search
        if let currentSource = UserDefaults.standard.selectedMediaSource {
             switch currentSource {
             case .animeWorld, .gogoanime, .kuramanime, .animefire, .anilist: // Added .anilist
                 navigationItem.rightBarButtonItem = sortButton
             default:
                 navigationItem.rightBarButtonItem = nil // Hide sort for others
             }
         } else {
             navigationItem.rightBarButtonItem = nil // Hide if no source somehow
         }
    }

    private func setupLoadingIndicator() {
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupErrorLabel() {
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        view.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    private func setupNoResultsLabel() {
        noResultsLabel.translatesAutoresizingMaskIntoConstraints = false
        noResultsLabel.textAlignment = .center
        noResultsLabel.text = "No results found"
        noResultsLabel.isHidden = true

        view.addSubview(noResultsLabel)
        view.addSubview(changeSourceButton)

        NSLayoutConstraint.activate([
            noResultsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            noResultsLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20), // Move label up slightly

            changeSourceButton.topAnchor.constraint(equalTo: noResultsLabel.bottomAnchor, constant: 15),
            changeSourceButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func sortButtonTapped() {
        let alertController = UIAlertController(title: "Sort Anime", message: nil, preferredStyle: .actionSheet)

        let allAction = UIAlertAction(title: "All", style: .default) { [weak self] _ in
            self?.filterResults(option: .all)
        }

        if let currentSource = UserDefaults.standard.selectedMediaSource {
            switch currentSource {
            case .gogoanime:
                let dubAction = UIAlertAction(title: "Dub", style: .default) { [weak self] _ in
                    self?.filterResults(option: .dub)
                }
                let subAction = UIAlertAction(title: "Sub", style: .default) { [weak self] _ in
                    self?.filterResults(option: .sub)
                }
                alertController.addAction(dubAction)
                alertController.addAction(subAction)
            case .animeWorld, .animeunity: // Grouped Italian sources
                let itaAction = UIAlertAction(title: "ITA", style: .default) { [weak self] _ in
                    self?.filterResults(option: .ita)
                }
                alertController.addAction(itaAction)
            case .kuramanime:
                let dubAction = UIAlertAction(title: "Dub", style: .default) { [weak self] _ in
                    self?.filterResults(option: .dub)
                }
                alertController.addAction(dubAction)
            case .animefire:
                let dubAction = UIAlertAction(title: "Dub", style: .default) { [weak self] _ in
                    self?.filterResults(option: .dub)
                }
                alertController.addAction(dubAction)
            case .anilist: // Added Anilist case
                 let dubAction = UIAlertAction(title: "Dub", style: .default) { [weak self] _ in
                     self?.filterResults(option: .dub)
                 }
                 let subAction = UIAlertAction(title: "Sub", style: .default) { [weak self] _ in
                     self?.filterResults(option: .sub)
                 }
                 alertController.addAction(dubAction)
                 alertController.addAction(subAction)
            default:
                break // No specific filters for other sources shown
            }
        }


        alertController.addAction(allAction)

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(cancelAction)

        if let popoverController = alertController.popoverPresentationController {
            popoverController.barButtonItem = sortButton
        }

        present(alertController, animated: true, completion: nil)
    }

    private enum FilterOption {
        case all, dub, sub, ita
    }

    private func filterResults(option: FilterOption) {
        guard let currentSource = UserDefaults.standard.selectedMediaSource else { return }

        switch option {
        case .all:
            filteredResults = searchResults
        case .dub:
            switch currentSource {
            case .gogoanime, .anilist: // Added Anilist
                filteredResults = searchResults.filter { $0.title.lowercased().contains("(dub)") }
            case .kuramanime:
                filteredResults = searchResults.filter { $0.title.contains("(Dub ID)") }
            case .animefire:
                filteredResults = searchResults.filter { $0.title.contains("(Dublado)") }
            default:
                filteredResults = searchResults // No specific dub filter for others
            }
        case .sub:
             switch currentSource {
             case .gogoanime, .anilist: // Added Anilist
                 filteredResults = searchResults.filter { !$0.title.lowercased().contains("(dub)") }
             default:
                 filteredResults = searchResults // Assume non-dub is sub or only sub exists
             }
        case .ita:
             switch currentSource {
             case .animeWorld, .animeunity: // Grouped Italian filter logic
                 filteredResults = searchResults.filter { $0.title.contains("ITA") }
             default:
                 filteredResults = searchResults // No specific ITA filter for others
             }
        }

        tableView.reloadData()
        updateNoResultsLabelVisibility()
    }

     private func updateNoResultsLabelVisibility() {
         noResultsLabel.isHidden = !filteredResults.isEmpty
         changeSourceButton.isHidden = !filteredResults.isEmpty
     }

    @objc private func changeSourceButtonTapped() {
        SourceMenu.showSourceSelector(from: self, sourceView: changeSourceButton) { [weak self] in
            self?.refreshResults()
        }
    }

    func refreshResults() {
        fetchResults()
    }

    private func fetchResults() {
        let session = proxySession.createAlamofireProxySession()

        loadingIndicator.startAnimating()
        tableView.isHidden = true
        errorLabel.isHidden = true
        noResultsLabel.isHidden = true
        changeSourceButton.isHidden = true

        guard let selectedSource = UserDefaults.standard.selectedMediaSource else {
            loadingIndicator.stopAnimating()
            SourceMenu.showSourceSelector(from: self, sourceView: view) { [weak self] in
                self?.refreshResults()
            }
            return
        }
        // self.selectedSource = selectedSource.rawValue // Update internal string if needed

        guard let urlParameters = getUrlAndParameters(for: selectedSource.rawValue) else {
            showError("Unsupported media source.")
            SourceMenu.showSourceSelector(from: self, sourceView: view) { [weak self] in
                self?.refreshResults()
            }
            return
        }

        if selectedSource == .gogoanime { // Special handling for GoGoAnime pagination
            DispatchQueue.main.async {
                self.fetchGoGoResults(urlParameters: urlParameters)
            }
        } else { // General handling for other sources
            session.request(urlParameters.url, method: .get, parameters: urlParameters.parameters).responseString { [weak self] response in
                // Use guard let self = self to safely unwrap
                guard let self = self else { return }
                self.loadingIndicator.stopAnimating()

                switch response.result {
                case .success(let value):
                    let results: [(title: String, imageUrl: String, href: String)]
                    // Special filtering for AniWorld within the response handling
                    if selectedSource == .aniworld {
                        results = self.parseHTML(html: value, for: selectedSource)
                        self.searchResults = results // Store unfiltered results
                        self.filteredResults = self.fuzzySearch(self.query, in: results) // Apply fuzzy search filter
                    } else {
                        results = self.parseHTML(html: value, for: selectedSource)
                        self.searchResults = results
                        self.filteredResults = results // Initially show all for non-AniWorld
                    }

                    if self.filteredResults.isEmpty { // Check filtered results
                        self.showNoResults()
                    } else {
                        self.tableView.isHidden = false
                        self.tableView.reloadData()
                        self.updateNoResultsLabelVisibility()
                    }
                case .failure(let error):
                    // Handle errors as before
                    if let httpStatusCode = response.response?.statusCode {
                        switch httpStatusCode {
                        // ... (keep existing status code handling) ...
                        case 400: self.showError("Bad request. Please check your input and try again.")
                        case 403: self.showError("Access forbidden. You don't have permission to access this resource.")
                        case 404: self.showError("Resource not found. Please try a different search.")
                        case 429: self.showError("Too many requests. Please slow down and try again later.")
                        case 500: self.showError("Internal server error. Please try again later.")
                        case 502: self.showError("Bad gateway. The server is temporarily unable to handle the request.")
                        case 503: self.showError("Service unavailable. Please try again later.")
                        case 504: self.showError("Gateway timeout. The server took too long to respond.")
                        default: self.showError("Unexpected error occurred (Status: \(httpStatusCode)). Please try again later.")
                        }
                    } else if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain {
                        switch nsError.code {
                        case NSURLErrorNotConnectedToInternet: self.showError("No internet connection. Please check your network and try again.")
                        case NSURLErrorTimedOut: self.showError("Request timed out. Please try again later.")
                        default: self.showError("Network error occurred (\(nsError.code)). Please try again later.")
                        }
                    } else {
                        self.showError("Failed to fetch data: \(error.localizedDescription). Please try again later.")
                    }
                    self.showNoResults() // Show "No results" and change source button on error
                }
            }
        }
    }

    private func fetchGoGoResults(urlParameters: (url: String, parameters: Parameters)) {
        let session = proxySession.createAlamofireProxySession()
        let group = DispatchGroup()
        var allResults: [(title: String, imageUrl: String, href: String)] = []
        var fetchError: Error? = nil // Track potential errors

        // Define fetch function to avoid repetition
        func fetchPage(page: Int) {
            group.enter()
            let pageUrl = page > 1 ? "\(urlParameters.url)?page=\(page)" : urlParameters.url
            session.request(pageUrl, method: .get, parameters: urlParameters.parameters).responseString { response in
                defer { group.leave() }
                switch response.result {
                case .success(let value):
                    if let document = try? SwiftSoup.parse(value), let results = self.parseGoGoAnime(document) {
                         allResults.append(contentsOf: results)
                    }
                case .failure(let error):
                     print("Error fetching GoGo page \(page): \(error)")
                     // Store the first error encountered
                     if fetchError == nil { fetchError = error }
                }
            }
        }

        // Fetch pages 1, 2, 3
        fetchPage(page: 1)
        fetchPage(page: 2)
        fetchPage(page: 3)

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.loadingIndicator.stopAnimating()

            if let error = fetchError, allResults.isEmpty {
                 // Show error only if there are no results AND an error occurred
                 self.showError("Failed to fetch GoGoAnime results: \(error.localizedDescription)")
                 self.showNoResults() // Show "Change Source" button
             } else {
                 self.searchResults = allResults
                 self.filteredResults = allResults // Initially show all results
                 if allResults.isEmpty {
                     self.showNoResults()
                 } else {
                     self.tableView.isHidden = false
                     self.tableView.reloadData()
                     self.updateNoResultsLabelVisibility()
                 }
             }
        }
    }

    // Updated to use MediaSource enum
    private func getUrlAndParameters(for source: String) -> (url: String, parameters: Parameters)? {
        guard let mediaSource = MediaSource(rawValue: source) else { return nil }

        let url: String
        var parameters: Parameters = [:]

        switch mediaSource {
        case .animeWorld:
            url = "https://animeworld.so/search"
            parameters["keyword"] = query
        case .gogoanime:
            url = "https://anitaku.bz/search.html" // Base search URL
            parameters["keyword"] = query
        case .animeheaven:
            url = "https://animeheaven.me/search.php"
            parameters["s"] = query
        case .animefire:
            let encodedQuery = query.lowercased().replacingOccurrences(of: " ", with: "-").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
            url = "https://animefire.plus/pesquisar/\(encodedQuery)"
        case .kuramanime:
            url = "https://kuramanime.red/anime"
            parameters["search"] = query
        case .anime3rb:
            url = "https://anime3rb.com/search"
            parameters["q"] = query
        case .anilist: // Renamed from hianime
            let baseUrls = ["https://aniwatch-api-gp1w.onrender.com/anime/search"] // Using provided logic's URL
            url = baseUrls.randomElement()!
            parameters["q"] = query
        case .anilibria:
            url = "https://api.anilibria.tv/v3/title/search"
            parameters["search"] = query
            parameters["filter"] = "id,names,posters"
        case .animesrbija:
            url = "https://www.animesrbija.com/filter"
            parameters["search"] = query
        case .aniworld:
            url = "https://aniworld.to/animes"
            parameters = [:] // No query parameter for this source; filtering done after fetching all
        case .tokyoinsider:
            url = "https://www.tokyoinsider.com/anime/search"
            parameters["k"] = query
        case .anivibe:
            url = "https://anivibe.net/search.html"
            parameters["keyword"] = query
        case .animeunity:
            url = "https://www.animeunity.to/archivio"
            parameters["title"] = query
        case .animeflv:
            url = "https://www3.animeflv.net/browse"
            parameters["q"] = query
        case .animebalkan:
            url = "https://animebalkan.gg/" // Using .gg as per extension
            parameters["s"] = query
        case .anibunker:
            url = "https://www.anibunker.com/search"
            parameters["q"] = query
        }

        return (url, parameters)
    }

    // Fuzzy search remains the same
    private func fuzzySearch(_ query: String, in results: [(title: String, imageUrl: String, href: String)]) -> [(title: String, imageUrl: String, href: String)] {
        return results.filter { result in
            let title = result.title.lowercased()
            let searchQuery = query.lowercased()

            if title.contains(searchQuery) {
                return true
            }
            // Basic word matching (can be improved)
            let titleWords = Set(title.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
            let queryWords = Set(searchQuery.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })

            return !titleWords.intersection(queryWords).isEmpty
        }
    }


    private func showError(_ message: String) {
        loadingIndicator.stopAnimating()
        errorLabel.text = message
        errorLabel.isHidden = false
        showNoResults() // Also show "Change Source" button on error
    }

    private func showNoResults() {
        noResultsLabel.isHidden = false
        changeSourceButton.isHidden = false
        tableView.isHidden = true // Hide table view when no results or error
    }

    // Updated to take MediaSource enum
    func parseHTML(html: String, for source: MediaSource) -> [(title: String, imageUrl: String, href: String)] {
        switch source {
        case .anilist, .anilibria: // Handle JSON sources
            // Use the previously defined parsing functions (ensure they handle String input)
            do {
                if source == .anilist { return try parseAniListFeatured(nil, html) }
                if source == .anilibria { return try parseAniLibriaFeatured(nil, html) }
                return [] // Should not happen
            } catch {
                print("Error parsing JSON for \(source.rawValue): \(error.localizedDescription)")
                return []
            }
        default: // Handle HTML sources
            do {
                let document = try SwiftSoup.parse(html)
                return parseDocument(document, jsonString: nil, for: source)
            } catch {
                print("Error parsing HTML for \(source.rawValue): \(error.localizedDescription)")
                return []
            }
        }
    }

    // Updated to take MediaSource enum
    private func parseDocument(_ document: Document?, jsonString: String?, for source: MediaSource) -> [(title: String, imageUrl: String, href: String)] {
        switch source {
        case .animeWorld:
            guard let document = document else { return [] }
            return parseAnimeWorld(document)
        case .gogoanime:
            guard let document = document else { return [] }
            return parseGoGoAnime(document)
        case .animeheaven:
            guard let document = document else { return [] }
            return parseAnimeHeaven(document)
        case .animefire:
            guard let document = document else { return [] }
            return parseAnimeFire(document)
        case .kuramanime:
            guard let document = document else { return [] }
            return parseKuramanime(document)
        case .anime3rb:
            guard let document = document else { return [] }
            return parseAnime3rb(document)
        case .anilist: // Renamed from hianime
            guard let jsonString = jsonString else { return [] }
            return parseAniList(jsonString) // Use renamed parsing function
        case .anilibria:
            guard let jsonString = jsonString else { return [] }
            return parseAnilibria(jsonString)
        case .animesrbija:
            guard let document = document else { return [] }
            return parseAnimeSRBIJA(document)
        case .aniworld:
            guard let document = document else { return [] }
            return parseAniWorld(document) // This returns ALL, filtering happens in fetchResults
        case .tokyoinsider:
            guard let document = document else { return [] }
            return parseTokyoInsider(document)
        case .anivibe:
            guard let document = document else { return [] }
            return parseAniVibe(document)
        case .animeunity:
            guard let document = document else { return [] }
            return parseAnimeUnity(document)
        case .animeflv:
            guard let document = document else { return [] }
            return parseAnimeFLV(document)
        case .animebalkan:
            guard let document = document else { return [] }
            return parseAnimeBalkan(document)
        case .anibunker:
            guard let document = document else { return [] }
            return parseAniBunker(document)
        }
    }

    private func navigateToAnimeDetail(title: String, imageUrl: String, href: String) {
        let detailVC = AnimeDetailViewController()
        // Get the currently selected source string for passing to configure
        let selectedMediaSourceString = UserDefaults.standard.selectedMediaSource?.rawValue ?? ""

        detailVC.configure(title: title, imageUrl: imageUrl, href: href, source: selectedMediaSourceString)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

extension SearchResultsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "resultCell", for: indexPath) as! SearchResultCell
        let result = filteredResults[indexPath.row]
        cell.configure(with: result)

        // Add context menu interaction to each cell
        let interaction = UIContextMenuInteraction(delegate: self)
        cell.addInteraction(interaction)

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedResult = filteredResults[indexPath.row]
        navigateToAnimeDetail(title: selectedResult.title, imageUrl: selectedResult.imageUrl, href: selectedResult.href)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 160 // Adjust as needed for your cell height
    }
}

extension SearchResultsViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        let locationInTableView = interaction.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: locationInTableView) else {
                  return nil
        }

        let result = filteredResults[indexPath.row] // Use filtered results

        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: { [weak self] in // Use weak self
            // Use guard let self = self
            guard let self = self else { return nil }
            let detailVC = AnimeDetailViewController()
            let selectedMediaSourceString = UserDefaults.standard.selectedMediaSource?.rawValue ?? ""

            detailVC.configure(title: result.title, imageUrl: result.imageUrl, href: result.href, source: selectedMediaSourceString)
            return detailVC
        }, actionProvider: { [weak self] _ in
            // Use guard let self = self
            guard let self = self else { return nil }

            let openAction = UIAction(title: "Open", image: UIImage(systemName: "arrow.up.right.square")) { _ in
                self.navigateToAnimeDetail(title: result.title, imageUrl: result.imageUrl, href: result.href)
            }

            let openInBrowserAction = UIAction(title: "Open in Browser", image: UIImage(systemName: "globe")) { _ in
                self.openInBrowser(path: result.href)
            }

            let isFav = self.isFavorite(for: result)
            let favoriteAction = UIAction(
                title: isFav ? "Remove from Library" : "Add to Library",
                image: UIImage(systemName: isFav ? "bookmark.fill" : "bookmark")
            ) { _ in
                self.toggleFavorite(for: result, at: indexPath) // Pass indexPath
            }

            return UIMenu(title: "", children: [openAction, openInBrowserAction, favoriteAction])
        })
    }

    // Function to handle opening in browser
    private func openInBrowser(path: String) {
        guard let selectedSource = UserDefaults.standard.selectedMediaSource else { return }
        let baseUrl: String

        switch selectedSource {
        case .animeWorld: baseUrl = "https://animeworld.so"
        case .gogoanime: baseUrl = "https://anitaku.bz"
        case .animeheaven: baseUrl = "https://animeheaven.me/"
        case .anilist: baseUrl = "https://hianime.to" // Base site URL, path is likely the slug
        case .anilibria: baseUrl = "https://anilibria.tv/release/" // Path is likely the ID
        case .animefire: baseUrl = "https://animefire.plus"
        case .kuramanime, .anime3rb, .animesrbija, .aniworld, .tokyoinsider, .anivibe, .animeunity, .animeflv, .animebalkan, .anibunker:
            baseUrl = "" // Assume path is already absolute or needs source-specific base
        }

        let fullUrlString: String
        if source == .anilist { // Special case for anilist slug
             fullUrlString = "\(baseUrl)/\(path)"
         } else if source == .anilibria { // Special case for anilibria ID
              fullUrlString = "\(baseUrl)\(path).html"
          } else if !baseUrl.isEmpty && !path.hasPrefix("http") {
            fullUrlString = baseUrl + (path.hasPrefix("/") ? path : "/\(path)")
        } else {
            fullUrlString = path // Assume path is already a full URL
        }

        guard let url = URL(string: fullUrlString) else {
            print("Invalid URL string: \(fullUrlString)")
            // Use self.showAlert
            self.showAlert(title: "Error", message: "The URL is invalid.")
            return
        }

        let safariViewController = SFSafariViewController(url: url)
        present(safariViewController, animated: true, completion: nil)
    }

    // Use the showAlert defined in this class
    private func showAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alertController, animated: true, completion: nil)
    }


    private func isFavorite(for result: (title: String, imageUrl: String, href: String)) -> Bool {
        guard let anime = createFavoriteAnime(from: result) else { return false }
        return FavoritesManager.shared.isFavorite(anime)
    }

    // Updated toggleFavorite to reload cell at specific index path
    private func toggleFavorite(for result: (title: String, imageUrl: String, href: String), at indexPath: IndexPath) {
        guard let anime = createFavoriteAnime(from: result) else { return }

        if FavoritesManager.shared.isFavorite(anime) {
            FavoritesManager.shared.removeFavorite(anime)
        } else {
            FavoritesManager.shared.addFavorite(anime)
        }

        // Reload only the specific cell that was acted upon
        // Check if the index path is still valid before reloading
        if indexPath.section < tableView.numberOfSections && indexPath.row < tableView.numberOfRows(inSection: indexPath.section) {
             tableView.reloadRows(at: [indexPath], with: .none) // Use .none for less jarring update
        }
    }

    private func createFavoriteAnime(from result: (title: String, imageUrl: String, href: String)) -> FavoriteItem? {
        guard let imageURL = URL(string: result.imageUrl),
              let contentURL = URL(string: result.href),
              // Get source from UserDefaults, not the potentially outdated 'selectedSource' string property
              let sourceString = UserDefaults.standard.selectedMediaSource?.rawValue
        else {
            return nil
        }
        return FavoriteItem(title: result.title, imageURL: imageURL, contentURL: contentURL, source: sourceString)
    }

    // Added preview provider methods
     func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
         guard let indexPath = configuration.identifier as? IndexPath,
               let cell = tableView.cellForRow(at: indexPath) else {
                   return nil
               }

         let parameters = UIPreviewParameters()
         parameters.backgroundColor = .clear
         // Target the cell's content view for the preview highlight
         let target = UITargetedPreview(view: cell.contentView, parameters: parameters)
         return target
     }

     func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
         guard let indexPath = configuration.identifier as? IndexPath,
               let cell = tableView.cellForRow(at: indexPath) else {
                   return nil
               }

         let parameters = UIPreviewParameters()
         parameters.backgroundColor = .clear
         // Target the cell's content view for the dismissal preview
         let target = UITargetedPreview(view: cell.contentView, parameters: parameters)
         return target
     }
}

// Cell class remains the same
class SearchResultCell: UITableViewCell {
    let animeImageView = UIImageView()
    let titleLabel = UILabel()
    let disclosureIndicatorImageView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
        configureAppearance()
    }

     override func setHighlighted(_ highlighted: Bool, animated: Bool) {
         super.setHighlighted(highlighted, animated: animated)
         UIView.animate(withDuration: 0.1) {
             self.contentView.alpha = highlighted ? 0.7 : 1.0
         }
     }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        animeImageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        disclosureIndicatorImageView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(animeImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(disclosureIndicatorImageView)

        NSLayoutConstraint.activate([
            animeImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            animeImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            animeImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            animeImageView.widthAnchor.constraint(equalToConstant: 100), // Adjust width as needed

            titleLabel.leadingAnchor.constraint(equalTo: animeImageView.trailingAnchor, constant: 15),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: disclosureIndicatorImageView.leadingAnchor, constant: -10), // Space before indicator

            disclosureIndicatorImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16), // Adjust padding
            disclosureIndicatorImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            disclosureIndicatorImageView.widthAnchor.constraint(equalToConstant: 10), // Adjust size
            disclosureIndicatorImageView.heightAnchor.constraint(equalToConstant: 15) // Adjust size
        ])

        // Make sure the cell height is sufficient
         contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true // Example height


        animeImageView.clipsToBounds = true
        animeImageView.contentMode = .scaleAspectFill // Changed to fill
        animeImageView.layer.cornerRadius = 8 // Added corner radius

        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        titleLabel.numberOfLines = 0 // Allow multiple lines
        titleLabel.lineBreakMode = .byWordWrapping // Wrap words

        disclosureIndicatorImageView.image = UIImage(systemName: "chevron.compact.right")
        disclosureIndicatorImageView.tintColor = .gray // Or your preferred color
    }

    private func configureAppearance() {
        backgroundColor = UIColor.systemBackground // Use system background
    }

    func configure(with result: (title: String, imageUrl: String, href: String)) {
        titleLabel.text = result.title
        if let url = URL(string: result.imageUrl) {
            animeImageView.kf.setImage(with: url, placeholder: UIImage(systemName: "photo"), options: [.transition(.fade(0.2)), .cacheOriginalImage])
        } else {
             animeImageView.image = UIImage(systemName: "photo") // Set placeholder if URL is invalid
        }
    }
}

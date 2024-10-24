
import SwiftUI

// public
public enum RALInfiniteScrollVListScrollDirection {
    case upward
    case downward
}

public struct RALInfiniteScrollVList<T: Identifiable, V: View>: View {
    
    public typealias ScrollDirection = RALInfiniteScrollVListScrollDirection
    public let itemViewProvider: (T) -> V
    public let scrollDirection: ScrollDirection
    
    @ObservedObject private var viewModel: RALInfiniteScrollVListVM<T>

    public init(viewModel: RALInfiniteScrollVListVM<T>,
                itemViewProvider: @escaping (T) -> V) {
        self.viewModel = viewModel
        self.itemViewProvider = itemViewProvider
        self.scrollDirection = viewModel.scrollDirection
    }

    private let kScrollViewCoordSpaceName = "scroll_view"
    @State private var activeId: T.ID?
    
    public var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack {
                    if viewModel.isLoading && scrollDirection == .upward {
                        progressView()
                    }
                    
                    itemsListView()

                    if viewModel.isLoading && scrollDirection == .downward {
                        progressView()
                    }
                }
                .scrollTargetLayout()
                .background {
                    geometryTrackingView(containerCoordName: kScrollViewCoordSpaceName)
                }
            }
            .coordinateSpace(name: kScrollViewCoordSpaceName)
            .scrollPosition(id: $activeId, anchor: .center)
        }
    }
    
    private func progressView() -> some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle())
            .scaleEffect(0.7)
            .padding()
    }
    
    private func itemsListView() -> some View {
        ForEach(viewModel.items) { item in
            self.itemViewProvider(item)
        }
    }
    
    private func geometryTrackingView(containerCoordName: String) -> some View {
        GeometryReader { geometry in
            Color.clear
                .onChange(of: geometry.frame(in: .named(containerCoordName))) { oldValue, newValue in
                    checkAndFetchNextPageIfNeeded(withOld: oldValue, andNew: newValue, containerCoordName: containerCoordName)
                }
        }
    }
    
    private func checkAndFetchNextPageIfNeeded(withOld oldFrame: CGRect, andNew frame: CGRect, containerCoordName: String) {
        guard (checkNeedsToLoadMore(withOld: oldFrame, andNew: frame)) else { return }
        Task {
            await viewModel.loadNextPage()
        }
    }
    
    private func checkNeedsToLoadMore(withOld oldFrame: CGRect, andNew frame: CGRect) -> Bool {
        let threshold: CGFloat = 5.0
        let reachedLimit: Bool
        
        let scrollViewHeightChanged = oldFrame.size.height != frame.size.height
        guard !viewModel.isLoading, !scrollViewHeightChanged else { return false }

        switch scrollDirection {
        case .upward:
            reachedLimit = (frame.minY > oldFrame.minY + threshold)
        case .downward:
            reachedLimit = (frame.maxY < oldFrame.maxY - threshold)
        }
        return reachedLimit
    }
}


// import SwiftUI

open class RALInfiniteScrollVListVM<T: Identifiable>: ObservableObject {
    @MainActor @Published public var items: [T] = []
    @MainActor @Published public var isLoading: Bool = false
    
    private let fetchNextPage: @Sendable () async throws -> [T]
    let scrollDirection: RALInfiniteScrollVListScrollDirection

    public init(initialItems: [T] = [],
         fetchNextPage: @escaping @Sendable () async throws -> [T],
         scrollDirection: RALInfiniteScrollVListScrollDirection) {
        self.fetchNextPage = fetchNextPage
        self.scrollDirection = scrollDirection
        
        Task {
            await MainActor.run { self.items = initialItems }
        }
    }

    @MainActor public func loadNextPage() async {
        guard await !isLoading else { return }
        isLoading = true
        do {
            let newItems = try await fetchNextPage()
            switch self.scrollDirection {
            case .upward:
                self.items.insert(contentsOf: newItems, at: 0)
            case .downward:
                self.items.append(contentsOf: newItems)
            }
        } catch {
            print("Failed to fetch items: \(error)")
        }
        isLoading = false
    }
}

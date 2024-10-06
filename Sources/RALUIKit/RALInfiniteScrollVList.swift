// The Swift Programming Language
// https://docs.swift.org/swift-book
import SwiftUI

public struct RALInfiniteScrollVList<T:Identifiable, V: View>: View {
    // public
    public enum ScrollDirection {
        case upward
        case downward
    }
    @Binding var items: [T]
    public let scrollDirection: ScrollDirection
    // #takeaway @Sendable: Mark the closure as @Sendable to ensure that it’s safe to be run in concurrent contexts (although this is optional, it’s a good practice in modern Swift concurrency).
    public let fetchNextPage: @Sendable () async throws -> [T]
    public let itemViewProvider: (T) -> V
    
    public init(items: Binding<[T]>, scrollDirection: ScrollDirection, fetchNextPage: @escaping @Sendable () async throws -> [T], itemViewProvider: @escaping (T) -> V) {
        self._items = items
        self.scrollDirection = scrollDirection
        self.fetchNextPage = fetchNextPage
        self.itemViewProvider = itemViewProvider
    }

    //private
    private let kScrollViewCoordSpaceName = "scroll_view"
    @State private var isLoading = false
    
    @State private var activeId: T.ID?
    @State private var savedActiveId: T.ID?

    public var body: some View {
        
        ScrollViewReader { scrollProxy in
            
            ScrollView {
                VStack {
                    if isLoading && scrollDirection == .upward {
                        progressView()
                    }

                    itemsListView()
                    
                    if isLoading && scrollDirection == .downward {
                        progressView()
                    }
                }
                /// #takeaway tells what is the content that you want to keep track of in `scrollPosition`
                .scrollTargetLayout()
                // #takeaway trick: add GeometryReader as a background fo the view we're interested in detecting changes, bc BG will have same geometry as the View we're interested.
                .background {
                    geometryTrackingView(conatinerCoordName: kScrollViewCoordSpaceName)
                }
            }
            .coordinateSpace(name: kScrollViewCoordSpaceName)
            /// #takeaway this is a two way sync to keep a scroll position for my scroillView
            .scrollPosition(id: $activeId, anchor: .center)
            /// #takeaway this tracks changes in the activeId if we need to observe it
//            .onChange(of: activeId) { oldValue, newValue in
//                print("changed activeId: \(String(describing: newValue))")
//            }
        }
    }
}

private extension RALInfiniteScrollVList {
    
    @ViewBuilder
    func progressView() -> some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle())
            .scaleEffect(0.7)
            .padding()
            .background {
                Color.yellow
            }
    }
    
    @ViewBuilder
    func itemsListView() -> some View {
        ForEach(items) { item in
            self.itemViewProvider(item)
            // #takeaway we can use `.onAppear` and `.onDisappear` to track visible items on the scrollable list
//                            .onAppear {
//                                visibleIds.insert(item.id)
//                                print("added VISIBLE ID: \(item.id)")
//                            }
//                            .onDisappear {
//                                visibleIds.remove(item.id)
//                                print("removed VISIBLE ID: \(item.id)")
//                            }
        }
    }
    
    @ViewBuilder
    func geometryTrackingView(conatinerCoordName: String) -> some View {
        
        GeometryReader { geometry in
            // #takeaway if we called here `checkNeedsToLoadMore`, we'd have to update any @state in the UI thread or the state changes won't be detected
            Color.clear
                .onChange(of: geometry.frame(in: .named(conatinerCoordName))) { oldValue, newValue in // in scrollView coords
                    
                    guard var containerBounds = geometry.bounds(of: .named(kScrollViewCoordSpaceName)) else { // scrollView in local coords
                        assertionFailure("INCONSISTENCY: could not find the scroll_view bound in the local coordinate space")
                        return
                    }
                    containerBounds.origin = CGPoint(x: 0, y: 0)
                    // #takeaway if we call `checkNeedsToLoadMore` here, since we're OUT of a View building block (we're inside `onChange` instead), we don't need to embed in mainQueue.async, so this is preferable
                    checkAndFetchNextPageIfNeeded(withOld: oldValue, andNew: newValue, in: containerBounds)
                }
        }
    }
    
    func checkAndFetchNextPageIfNeeded(withOld oldFrame: CGRect, andNew frame: CGRect, in container: CGRect) {
        guard (checkNeedsToLoadMore(withOld: oldFrame,
                                    andNew: frame,
                                    in: container,
                                    scrollDirection: scrollDirection,
                                    isLoading: isLoading)) else { return }
        
        Task {
            // save visible item to restore scrollView offset after a page reload
            savedActiveId = activeId
            
            await setIsLoading(true)
            await performFetch()
            // #learning using `try? await Task.sleep(for: .seconds(1))` (to leave time for UI to update, to protect against loading unwated pages (protecred via `isLoading = true`) ) DOES NOT WORK! bc changing isLoading = false after will still refresh the UI (removing the spinner) and change the scrollView frame
            await setIsLoading(false)
            
            await restoreContextOffsetIfNeeded()
        }
    }

    // #TODO: we can extract this loginc into helper entity.
    func checkNeedsToLoadMore(withOld oldFrame: CGRect, andNew frame: CGRect, in container: CGRect, scrollDirection: ScrollDirection, isLoading: Bool) -> Bool {
        let threshold: CGFloat = 5.0
        let reachedLimit: Bool
        
        // we want to avoid detecting scroll `reachedLimit` when we're scrolling in a scroll direction opposite from the one we expect
        let detectedScrollDirection: ScrollDirection
        switch scrollDirection {
        case .upward: detectedScrollDirection = (frame.minY - oldFrame.minY <= 0) ? .downward : .upward
        case .downward: detectedScrollDirection = (frame.maxY - oldFrame.maxY >= 0) ? .upward : .downward
        }
        // we want to avoid detecting scroll `reachedLimit` when the update is due to a change in the size of the scrollView (content added or removed)
        let scrollViewHeightChanged = oldFrame.size.height != frame.height
        
        guard !isLoading, !scrollViewHeightChanged, detectedScrollDirection == scrollDirection else { return false }

        switch scrollDirection {
        case .upward: reachedLimit = (frame.minY > container.minY + threshold)
        case .downward: reachedLimit = (frame.maxY < container.maxY - threshold)
        }
                
        return reachedLimit
    }
    
    func performFetch() async {
        do {
            let nextPage = try await fetchNextPage()
            await self.updateItems(nextPage: nextPage)
        } catch let error {
            print("Error fetching next page: \(error)")
        }
    }
    
    @MainActor
    func updateItems(nextPage: [T]) {
        switch scrollDirection {
        case .upward:
            items.insert(contentsOf: nextPage, at: 0)
        case .downward:
            items.append(contentsOf: nextPage)
        }
    }
    
    @MainActor
    func setIsLoading(_ isLoading: Bool) {
        self.isLoading = isLoading
    }
    
    @MainActor
    func restoreContextOffsetIfNeeded() {
        // #takeaway since `.scrollPosition(id:, anchor:)` takes a binding, assigning  `activeId` will scroll to it in the UI!!
        activeId = savedActiveId
    }
}

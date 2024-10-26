
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
    private let infiniteScrollGeometryHelper: InfiniteScrollGeometryHelper

    public init(viewModel: RALInfiniteScrollVListVM<T>,
                itemViewProvider: @escaping (T) -> V,
                infiniteScrollGeometryHelper: InfiniteScrollGeometryHelper = RALInfiniteScrollGeometryHelper()) {
        self.viewModel = viewModel
        self.itemViewProvider = itemViewProvider
        self.scrollDirection = viewModel.scrollDirection
        self.infiniteScrollGeometryHelper = infiniteScrollGeometryHelper
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
        guard infiniteScrollGeometryHelper.checkNeedsToLoadMore(withOld: oldFrame, andNew: frame, scrollDirection: scrollDirection, isLoading: viewModel.isLoading) else { return }
        Task {
            await viewModel.loadNextPage()
        }
    }
}


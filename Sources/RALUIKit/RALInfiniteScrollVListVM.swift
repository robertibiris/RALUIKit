//
//  InfiniteScrollVListVM.swift
//  RALUIKit
//
//  Created by Roberto Arreaza on 26/10/24.
//

import Foundation

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

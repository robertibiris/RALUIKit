//
//  InfiniteScrollGeometryHelper.swift
//  RALUIKit
//
//  Created by Roberto Arreaza on 26/10/24.
//
import Foundation

public protocol InfiniteScrollGeometryHelper {
    typealias ScrollDirection = RALInfiniteScrollVListScrollDirection
    func checkNeedsToLoadMore(withOld oldFrame: CGRect, andNew frame: CGRect, scrollDirection: ScrollDirection, isLoading: Bool) -> Bool
}

// Implementation
public struct RALInfiniteScrollGeometryHelper: InfiniteScrollGeometryHelper {
    
    public init() {}
    
    public func checkNeedsToLoadMore(withOld oldFrame: CGRect, andNew frame: CGRect, scrollDirection: ScrollDirection, isLoading: Bool) -> Bool {
        let threshold: CGFloat = 5.0
        let reachedLimit: Bool
        
        let scrollViewHeightChanged = oldFrame.size.height != frame.size.height
        guard !isLoading, !scrollViewHeightChanged else { return false }

        switch scrollDirection {
        case .upward:
            reachedLimit = (frame.minY > oldFrame.minY + threshold)
        case .downward:
            reachedLimit = (frame.maxY < oldFrame.maxY - threshold)
        }
        return reachedLimit
    }
}

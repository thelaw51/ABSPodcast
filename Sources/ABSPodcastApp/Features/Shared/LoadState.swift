import Foundation

/// The three states every server-backed screen moves through.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

import Foundation
import Dispatch

// Indirect so futures can be nested
public final class FutureResult<Expectation> {
    let _error: Error!
    let _expectation: Expectation!
    
    var isError: Bool

    /// Returns the result error or
    /// nil if the result contains expectation.
    public var error: Error? {
        if isError {
            return _error
        }
        
        return nil
    }

    /// Returns the result expectation or
    /// nil if the result contains an error.
    public var expectation: Expectation? {
        if !isError {
            return _expectation
        }
        
        return nil
    }
    
    /// Throws an error if this contains an error, returns the Expectation otherwise
    public func unwrap() throws -> Expectation {
        if isError {
            throw _error
        }
        
        return _expectation
    }
    
    public init(error: Error) {
        self._error = error
        self._expectation = nil
        self.isError = true
    }
    
    public init(expectation: Expectation) {
        self._error = nil
        self._expectation = expectation
        self.isError = false
    }
}

extension Promise {
    /// Fulfills the promise on the next tick of the supplied eventLoop.
    public func complete(_ expectation: T, onNextTick worker: Worker) {
        let source = worker.eventLoop.onNextTick { eof in
            assert(eof)
            self.complete(expectation)
        }
        source.resume()
    }

    /// Fulfills the promise on the next tick of the supplied eventLoop.
    public func fail(_ error: Error, onNextTick worker: Worker) {
        let source = worker.eventLoop.onNextTick { eof in
            assert(eof)
            self.fail(error)
        }
        source.resume()
    }
}

extension Promise where T == Void {
    /// Fulfills the promise on the next tick of the supplied eventLoop.
    public func complete(onNextTick worker: Worker) {
        self.complete((), onNextTick: worker)
    }
}

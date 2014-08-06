//
//  Future.swift
//  Swifter
//
//  Created by Daniel Hanggi on 6/19/14.
//  Copyright (c) 2014 Yahoo!. All rights reserved.
//

import Foundation

class Future<T> {
    
    typealias E = NSException
    typealias PNSE = PredicateNotSatisfiedException
    
    // TODO: make protected
    let promise: Promise<T>
    
    /* Optionally returns the current value of the Future, dependent on its completion status. */
    var value: Try<T>? {
    get {
        return self.promise.value
    }
    }
    
    /* Creates a already-completed Future whose value is `value`. */
    init(value: T) {
        self.promise = Promise<T>(value: .Success([value]))
    }
    
    /* Creates a Future whose value will be determined from the completion of task. */
    init(task: (() -> T)) {
        self.promise = Promise<T>()
        self.promise.executeOrMap(Executable<T>(task: { _ in task() }, thread: NSOperationQueue(), observed: self.promise)) // TODO
    }
    
    /* Creates a Future whose status is directly linked to the state of the Promise. */
    init(linkedPromise: Promise<T>) {
        self.promise = linkedPromise
    }
    
    /* Creates a copied Promise, bound to the original, that will be used as the
     * state of this Future. */
    init(copiedPromise: Promise<T>) {
        self.promise = Promise<T>()
        copiedPromise.alsoFulfill(self.promise)
    }
    
    /* Creates a new future from the application of `f` to the resulting PromiseState. */
    func fold<S>(f: ((Try<T>) -> Try<S>)) -> Future<S> {
        let promise = Promise<S>()
        
        self.promise.executeOrMap(Executable<T>(task: {
            (t: Try<T>) -> Any in
            promise.tryFulfill(f(t))
            }, thread: Scheduler.assignThread(), observed: self))
        
        return Future<S>(linkedPromise: promise)
    }
    
    /* Creates a new Future whose value is the application of `f` to the result
     * of this Future. */
    func map<S>(f: ((T) -> S)) -> Future<S> {
        Log(.FutureFolded, "Future is mapped to a new Future")
        return self.fold { $0.map(f) }
    }
    
    /* Creates a new Future from the application of `f` to the result of this
     * Future. */
    func bind<S>(f: ((T) -> Future<S>)) -> Future<S> {
        Log(.FutureFolded, "Future is bound to a new Future")
        
        let promise = Promise<S>()

        self.promise.executeOrMap(Executable<T>(task: {
            (t: Try<T>) -> () in
            _ = t.map(f).fold( {
                (s: Future<S>) -> Any in
                s.promise.alsoFulfill(promise)
                }, { promise.tryFail($0) })
            }, thread: Scheduler.assignThread(), observed: self))
        
        return Future<S>(linkedPromise: promise)
    }
    
    /* Creates a new future by filtering the value of the current Future with a
     * predicate. */
    func filter(p: ((T) -> Bool)) -> Future<T> {
        Log(.FutureFolded, "Future is filtered.")
        return self.fold { $0.filter(p) }
    }
    
    /* Applies the PartialFunction to the successful result of this Future. */
    func onSuccess<S>(pf: PartialFunction<T,S>) -> () {
        self.fold { $0.onSuccess(pf.tryApply) }
    }

    /* Applies the PartialFunction to the failure of this Future. */
    func onFailure<S>(pf: PartialFunction<E,S>) -> () {
        self.fold { $0.onFailure(pf.tryApply) }
    }
 
    /* Applies the PartialFunction to the completed result of this Future. */
    func onComplete<S>(pf: PartialFunction<Try<T>,S>) -> () {
        self.fold(pf.tryApply)
    }
   
    /* Creates a new future that will handle any matching throwable that this 
     * future might contain. */
    func recover(pf: PartialFunction<E,T>) -> Future<T> {
        return self.fold { $0.recover(pf) }
    }
    
    /* Applies the PartialFunction to the result of this Future, and returns a new 
     * Future with the result of this Future. */
    func andThen<S>(pf: PartialFunction<Try<T>,S>) -> Future<S> {
        return self.fold { pf.tryApply($0) }
    }
    
    /* Returns a single Future whose value, when completed, will be a tuple of the 
     * completed values of the two Futures. */
    func and<S>(other: Future<S>) -> Future<(T,S)> {
        // Fix mapping and binding.
        return self.bind {
            (first: T) -> Future<(T,S)> in
            other.bind {
                (second: S) -> Future<(T,S)> in
                return Future<(T,S)>(value: (first, second))
            }
        }
    }
    
}

extension Future : Awaitable {
    
    /* The final type of the action that is awaited. */
    typealias AwaitedResult = Future<T>
    
    typealias CompletedResult = T
    
    /* The result of the awaited action at completion. */
    var completedResult: T {
    get {
        self.await()
        return self.value!.toOption()!
    }
    }
    
    /* Returns if the awaited action has completed. */
    func isComplete() -> Bool {
        return self.promise.isFulfilled()
    }
    
    /* Awaits indefinitely until the action has completed. */
    func await() -> Future<T> {
        return self.await(NSTimeInterval.infinity)
    }
    
    /* Returns an attempt at awaiting the action for an NSTimeInterval duration. */
    func await(time: NSTimeInterval) -> Future<T> {
        let future = Future<T>(copiedPromise: self.promise)
        future.promise.timeout(time)
        return future
    }
    
}

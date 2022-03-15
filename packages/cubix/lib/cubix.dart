import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// cancel all action rule
Rule cancelAll<TAction extends Object?>(
    [bool Function(ActionBase)? predicate]) {
  return (dispatcher, next) {
    if (predicate != null) {
      // cancel all actions that matches a predicate
      for (final other in dispatcher.dispatching) {
        if (predicate(other.action) == true) {
          other.cancel();
        }
      }
    } else if (null is TAction) {
      // cancel all dispatching actions
      for (final other in dispatcher.dispatching) {
        other.cancel();
      }
    } else {
      for (final other in dispatcher.dispatching) {
        if (other.action is TAction) {
          other.cancel();
        }
      }
    }
    next();
  };
}

/// debounce action dispatching in specified duration
Rule debounce([Duration duration = Duration.zero]) {
  return (dispatcher, next) {
    for (final prevDispatcher in dispatcher.dispatching) {
      if (prevDispatcher.action.runtimeType == dispatcher.action.runtimeType) {
        prevDispatcher.cancel();
      }
    }
    dispatcher.on(cancel: Timer(duration, next).cancel);
  };
}

/// drop current dispatching if there is any instance of current action is dispatching
Rule droppable() {
  return (dispatcher, next) {
    final last = dispatcher.dispatching.lastWhereOrNull((element) =>
        element.action.runtimeType == dispatcher.action.runtimeType);

    if (last != null) {
      dispatcher.cancel();
    } else {
      next();
    }
  };
}

/// dispatch actions sequentially
Rule sequential() {
  return (dispatcher, next) {
    final last = dispatcher.dispatching.lastWhereOrNull((element) =>
        element.action.runtimeType == dispatcher.action.runtimeType);
    if (last == null) {
      next();
    } else {
      last.on(detach: next);
    }
  };
}

Rule throttle(Duration duration) {
  return (dispatcher, next) {
    final lastTime =
        dispatcher.data[_Props.throttleLastExecutionTime] as DateTime?;
    final now = DateTime.now();
    final nextTime = lastTime?.add(duration);
    if (nextTime == null || nextTime.compareTo(now) <= 0) {
      dispatcher.data[_Props.throttleLastExecutionTime] = now;
      next();
    }
  };
}

typedef ActionData = Map<Object?, Object?>;

typedef CreateCubix<T extends Cubix> = T Function();

typedef Rule = void Function(Dispatcher dispatcher, VoidCallback next);

typedef VoidCallback = void Function();

abstract class ActionBase<TResult, TState> {
  late final Dispatcher dispatcher;
  final _doneEmitter = _Emitter();
  final _errorEmitter = _Emitter<Object>();
  final _successEmitter = _Emitter();

  var _dispatched = false;

  ActionBase() {
    on(error: onError, success: onSuccess, done: onDone);
  }

  bool get cancelled => dispatcher.cancelled;

  Cubix<TState> get cubix => dispatcher.cubix as Cubix<TState>;

  bool get dispatched => _dispatched;

  bool get done => dispatched && dispatcher.done;

  Object? get error => dispatched ? dispatcher.error : null;

  TResult? get result => dispatcher.result as TResult;

  @protected
  TState get state => cubix.state;

  @protected
  set state(TState state) {
    if (cancelled) return;
    cubix.state = state;
  }

  bool get success => done && error == null;

  @protected
  Future<Map<TKey, Object?>> all<TKey>(Map<TKey, Object?> awatiable) {
    return _handleAwaitable(_AwaitType.all, awatiable);
  }

  @protected
  Future<Map<TKey, Object?>> allSettled<TKey>(Map<TKey, Object?> awatiable) {
    return _handleAwaitable(_AwaitType.allSettled, awatiable);
  }

  @protected
  TResult body();

  void cancel() => dispatcher.cancel();

  bool canDispatch(Cubix cubix) {
    return cubix._dispatchTest is List<TState>;
  }

  // dispatch other action
  @protected
  TActionResult dispatch<TActionResult>(
    ActionBase<TActionResult, TState> action, {
    CancelToken? cancelToken,
  }) {
    return cubix.dispatch(action, cancelToken: cancelToken);
  }

  void on(
      {VoidCallback? done,
      VoidCallback? success,
      void Function(Object)? error}) {
    if (done != null) _doneEmitter.on(done);
    if (success != null) _successEmitter.on(success);
    if (error != null) _errorEmitter.on(error);
  }

  void onAttach(Dispatcher dispatcher) {
    if (_dispatched) {
      throw Exception('Action is already dispatched');
    }
    _dispatched = true;
    this.dispatcher = dispatcher;
    dispatcher.on(
      done: () => _doneEmitter.emit(null),
      success: () => _successEmitter.emit(null),
      error: (e) => _errorEmitter.emit(e),
    );
  }

  @protected
  TResult onDispatch(Dispatcher dispatcher);

  @protected
  void onDone() {}

  @protected
  void onError(Object error) {}

  @protected
  void onResolve(DependencyResolver resolver) {}

  @protected
  void onSuccess() {}

  @protected
  Future<Map<TKey, Object?>> race<TKey>(Map<TKey, Object?> awatiable) {
    return _handleAwaitable(_AwaitType.race, awatiable);
  }

  void selfDispatch(Cubix<TState> cubix, {CancelToken? cancelToken}) {
    cubix.dispatch(this, cancelToken: cancelToken);
  }

  /// wait until action dispatching is completed
  Future<Object?> wait();

  @protected
  Future<ActionBase> when(bool Function(ActionBase action) predicate,
      {Cubix? cubix}) {
    final completer = Completer<ActionBase>();
    cubix ??= this.cubix;
    VoidCallback? removeListener;
    removeListener = cubix.listen((action) {
      if (predicate(action)) {
        removeListener?.call();
        completer.complete(action);
      }
    });
    dispatcher.on(detach: removeListener);
    return completer.future;
  }

  Future<Map<TKey, Object?>> _handleAwaitable<TKey>(
      _AwaitType type, Map<TKey, Object?> awatiable) {
    final actions = <ActionBase>[];
    final result = <TKey, Object?>{};
    final futures = <Future>[];

    void cancelAll() {
      for (final action in actions) {
        action.cancel();
      }
    }

    try {
      for (final entry in awatiable.entries) {
        final value = entry.value;
        Future? future;
        // handle future object
        if (value is Future) {
          future = value;
        } else if (value is ActionBase) {
          actions.add(value);
          if (!value.dispatched) {
            cubix.dispatchGeneric(value);
          }
          future = value.wait();
        } else {
          result[entry.key] = value;
        }

        if (future != null) {
          futures.add(future.then(
            (value) {
              if (cancelled) return;
              result[entry.key] = value;
              if (type == _AwaitType.race) {
                cancelAll();
              }
            },
            onError: (e) {
              if (cancelled) return;
              if (type == _AwaitType.allSettled) {
                result[entry.key] = e;
                return;
              }

              cancelAll();
              throw e;
            },
          ));
        }
      }
    } catch (e) {
      return Future.error(e);
    }

    final completer = Completer<Map<TKey, Object?>>();

    (type == _AwaitType.race ? Future.any(futures) : Future.wait(futures)).then(
        (value) {
      if (cancelled) return;
      completer.complete(result);
    }, onError: (e) {
      if (cancelled) return;
      completer.completeError(e);
    });

    return completer.future;
  }
}

abstract class AsyncAction<TResult, TState>
    extends ActionBase<Future<TResult>, TState> {
  List<Rule> get rules => [];

  @override
  Future<TResult> onDispatch(Dispatcher dispatcher) {
    final completer = Completer<TResult>();
    final invoker = rules.reversed.fold<VoidCallback>(
      () {
        if (dispatcher.cancelled) return;
        body().then((value) {
          if (dispatcher.cancelled) return;
          completer.complete(value);
          dispatcher.onDone(null, value);
        }, onError: (error) {
          if (dispatcher.cancelled) return;
          completer.completeError(error);
          dispatcher.onDone(error, null);
        });
      },
      (next, m) => () {
        if (dispatcher.cancelled) return;
        m(dispatcher, next);
      },
    );
    cubix.attachDispatcher(dispatcher);
    invoker();
    return completer.future;
  }

  @override
  Future<TResult> wait() {
    final completer = Completer<TResult>();
    on(
      success: () => completer.complete(dispatcher.result as TResult),
      error: completer.completeError,
    );
    return completer.future;
  }
}

class CallbackGroup {
  final _callbacks = <VoidCallback>[];

  void add(VoidCallback callback) {
    _callbacks.add(callback);
  }

  void addAll(Iterable<VoidCallback> callbacks) {
    _callbacks.addAll(callbacks);
  }

  void call() {
    for (final callback in _callbacks) {
      callback();
    }
  }

  void remove(VoidCallback callback) {
    _callbacks.remove(callback);
  }

  void removeAll(Iterable<VoidCallback> callbacks) {
    for (final callback in callbacks) {
      _callbacks.remove(callback);
    }
  }
}

class CancelledException with Exception {
  final String message;

  CancelledException(this.message);
}

class CancelToken {
  final bool Function()? _isCancelled;

  final _cancelEmitter = _Emitter();

  var _cancelled = false;

  CancelToken([this._isCancelled]);

  bool get cancelled => _cancelled || _isCancelled?.call() == true;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelEmitter.emit(null);
  }

  void on({VoidCallback? cancel}) {
    if (cancel != null) _cancelEmitter.on(cancel);
  }
}

class CubitWrapper<TState> extends Cubit<CubixState<TState>>
    with CubixMixin<TState> {
  CubitWrapper(TState initialState) : super(CubixState(initialState));

  @override
  void onChange(Change<CubixState<TState>> change) {
    super.onChange(change);
    fireOnChange(change);
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    super.onError(error, stackTrace);
    fireOnError(error, stackTrace);
  }

  CubixState<TState> update({
    TState Function(TState state)? state,
    Dispatcher? remove,
    Dispatcher? add,
    List<Dispatcher>? dispatchers,
  }) {
    return performUpdate(
      () => this.state,
      emit,
      state: state,
      remove: remove,
      add: add,
      dispatchers: dispatchers,
    );
  }
}

abstract class Cubix<TState> implements IDependency {
  final CubitWrapper<TState> cubit;
  final _data = <Type, ActionData>{};
  final _dispatchTest = <TState>[];

  final _disposeEmitter = _Emitter();
  final _dispatchEmitter = _Emitter<ActionBase>(false);

  var _disposed = false;
  var _resolved = false;

  Object? _error;
  Object? _key;
  DependencyResolver? _resolver;
  Type? _resolvedType;
  ResolveContext? _resolveContext;

  var _noDispatcherEmitter = _Emitter()..emit(null);

  Cubix(TState initialState,
      [CubitWrapper<TState> Function(TState initialState)? create])
      : cubit = (create ?? CubitWrapper.new)(initialState) {
    // forward protected event handlers
    cubit.on(
      change: (change) => onChange(Change(
          currentState: change.currentState.state,
          nextState: change.nextState.state)),
      error: onError,
    );
  }

  List<Dispatcher> get dispatchers => cubit.state.dispatchers;

  bool get disposed => _disposed;

  /// return last dispatching error
  Object? get error => _error;

  @override
  Object? get key => _key;

  @override
  Type get resolvedType => _resolvedType ?? runtimeType;

  DependencyResolver get resolver {
    if (_resolver == null) {
      throw Exception('resolve() method has not been called');
    }
    return _resolver!;
  }

  // get state
  TState get state => cubit.state.state;

  /// set state
  @protected
  set state(TState state) => cubit.update(state: (prev) => state);

  Dispatcher attachAction(ActionBase action, {CancelToken? cancelToken}) {
    if (!action.canDispatch(this)) {
      throw IncompatibleException(
          'Cannot dispatch this action. The Action is not compatible with this Cubix');
    }
    var actionData = _data[action.runtimeType];
    if (actionData == null) {
      _data[action.runtimeType] = actionData = {};
    }
    if (_resolved) {
      action.onResolve(resolver);
    }
    final dispatcher = Dispatcher(
      cubix: this,
      dispatching: dispatchers,
      cancelToken: cancelToken ?? CancelToken(),
      action: action,
      data: actionData,
    );
    action.onAttach(dispatcher);
    _dispatchEmitter.emit(action);
    onDispatch(action);
    return dispatcher;
  }

  void attachDispatcher(Dispatcher dispatcher) {
    dispatcher.on(end: () {
      cubit.update(remove: dispatcher);
      dispatcher.onDetach();
      if (dispatchers.isEmpty) {
        _noDispatcherEmitter.emit(null);
      }
    });
    cubit.update(add: dispatcher);
    if (_noDispatcherEmitter.emitted) {
      _noDispatcherEmitter = _Emitter();
    }
  }

  /// cancel all dispatching actions
  void cancel() {
    if (dispatchers.isEmpty) return;
    final prevState = cubit.update(dispatchers: []);
    for (final dispatcher in prevState.dispatchers) {
      dispatcher.cancel();
      dispatcher.onDetach();
    }
    _noDispatcherEmitter.emit(null);
  }

  /// dispatch specified action and return the result of action body
  TResult dispatch<TResult extends Object?>(
    ActionBase<TResult, TState> action, {
    CancelToken? cancelToken,
  }) {
    final dispatcher = attachAction(action, cancelToken: cancelToken);
    return action.onDispatch(dispatcher);
  }

  void dispatchGeneric(ActionBase action, {CancelToken? cancelToken}) {
    final dispatcher = attachAction(action, cancelToken: cancelToken);
    action.onDispatch(dispatcher);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _resolveContext?.dispose();
    _disposeEmitter.emit(null);
  }

  VoidCallback listen(void Function(ActionBase action) callback) {
    var active = true;
    _dispatchEmitter.on(callback);
    return () {
      if (!active) return;
      active = false;
      _dispatchEmitter.off(callback);
    };
  }

  /// return true if there is any action dispatching
  /// ```dart
  ///   cubix,loading()
  ///   cubix.loading<ActionType>()
  ///   cubix.loading((action) => action is ActionType1 || action is ActionType2 || action.prop == something);
  /// ```
  bool loading<TAction extends Object?>(
      [bool Function(ActionBase)? predicate]) {
    // using predicate to check action is dispatching or not
    if (predicate != null) {
      return dispatchers.any((element) => predicate(element.action));
    }
    // no action type
    if (null is TAction) {
      return dispatchers.isNotEmpty;
    }
    // with action type
    return dispatchers.any((element) => element.action is TAction);
  }

  void onChange(Change<TState> change) {}

  /// this method will be called whenever action dispatches
  void onDispatch(ActionBase action) {}

  void onError(Object error, StackTrace stackTrace) {}

  /// when cubix is resolved, this method will be called to make sure all cubix dependencies are resolved
  void onResolve(ResolveContext context) {}

  void remove() {
    resolver.remove(this);
  }

  @override
  void resolve(DependencyResolver resolver, {Object? key, Type? resolvedType}) {
    if (_resolved) {
      throw Exception('resolve() method can be called once');
    }
    _resolved = true;
    _key = key;
    _resolvedType = resolvedType ?? runtimeType;
    _resolver = resolver;
    onResolve(_resolveContext = ResolveContext(this, resolver));
  }

  Future<TState> wait() {
    final completer = Completer<TState>();

    _noDispatcherEmitter.on(() => completer.complete(state));

    return completer.future;
  }
}

mixin CubixMixin<TState> {
  void Function(Object error, StackTrace stackTrace)? _onError;
  void Function(Change<CubixState<TState>> change)? _onChange;

  void fireOnChange(Change<CubixState<TState>> change) {
    _onChange?.call(change);
  }

  void fireOnError(Object error, StackTrace stackTrace) {
    _onError?.call(error, stackTrace);
  }

  void on(
      {Function(Object error, StackTrace stackTrace)? error,
      Function(Change<CubixState<TState>> change)? change}) {
    _onChange = change;
    _onError = error;
  }

  CubixState<TState> performUpdate(
    CubixState<TState> Function() get,
    void Function(CubixState<TState>) emit, {
    TState Function(TState state)? state,
    Dispatcher? remove,
    Dispatcher? add,
    List<Dispatcher>? dispatchers,
  }) {
    final prevState = get();
    final nextState = prevState.reduce(
        state: state, add: add, remove: remove, dispatchers: dispatchers);
    if (nextState == prevState) return prevState;
    emit(nextState);
    return prevState;
  }
}

// final _completedFuture = Future.value(null);

class CubixState<TState> {
  final TState state;
  final List<Dispatcher> dispatchers;

  const CubixState(this.state, [this.dispatchers = const []]);

  CubixState<TState> reduce({
    TState Function(TState state)? state,
    Dispatcher? remove,
    Dispatcher? add,
    List<Dispatcher>? dispatchers,
  }) {
    if (state == null && remove == null && add == null && dispatchers == null) {
      return this;
    }
    dispatchers ??= this.dispatchers;
    var nextDispatchers = dispatchers;
    if (add != null) {
      if (nextDispatchers == dispatchers) {
        nextDispatchers = [...dispatchers];
      }
      nextDispatchers.add(add);
    }
    if (remove != null && nextDispatchers.contains(remove)) {
      if (nextDispatchers == dispatchers) {
        nextDispatchers = [...dispatchers];
      }
      nextDispatchers.remove(remove);
    }
    final nextState = state == null ? this.state : state(this.state);

    if (nextState == this.state && nextDispatchers == dispatchers) {
      return this;
    }

    return CubixState(
      nextState,
      nextDispatchers,
    );
  }
}

class DependencyResolver {
  final _dependencies = <Type, Map<Object?, IDependency>>{};

  void add<T extends IDependency>(T dependency, [Object? family]) {
    final collection = _dependencyGroup(T);
    collection[family] = dependency;
  }

  void remove<T extends IDependency>(T dependency) {
    final collection = _dependencyGroup(dependency.resolvedType);
    collection.remove(dependency.key);
    dependency.dispose();
  }

  T resolve<T extends IDependency>(
    T Function() create, {
    Object? family,
  }) {
    var collection = _dependencyGroup(T);
    var dependency = collection[family] as T?;
    if (dependency != null) return dependency;
    dependency = create();
    collection[family] = dependency;
    dependency.resolve(this, key: family, resolvedType: T);
    return dependency;
  }

  void walk(bool? Function(IDependency dependency) walker) {
    for (final group in _dependencies.values) {
      for (final dependency in group.values) {
        if (walker(dependency) == false) {
          return;
        }
      }
    }
  }

  Map<Object?, IDependency> _dependencyGroup(Type type) {
    var collection = _dependencies[type];
    if (collection == null) {
      collection = {};
      _dependencies[type] = collection;
    }
    return collection;
  }
}

/// The dispatcher holds all action dispatching status and lifecycle
class Dispatcher {
  /// contains all dispatching dispatchers
  final List<Dispatcher> dispatching;

  /// cancel token is passed from cubix.dispatch() method
  final CancelToken cancelToken;

  /// persistent data for dispatching calls
  final ActionData data;

  /// dispatching action object
  final ActionBase action;
  final Cubix cubix;

  final _doneEmitter = _Emitter();
  final _errorEmitter = _Emitter<Object>();
  final _successEmitter = _Emitter();
  final _detachEmitter = _Emitter();

  var _done = false;
  var _disposed = false;
  var _detached = false;
  var _cancelled = false;

  Object? _error;
  Object? _result;

  Dispatcher({
    required this.cubix,
    required this.action,
    required this.cancelToken,
    required this.dispatching,
    required this.data,
  }) {
    cancelToken.on(cancel: cancel);
  }

  bool get cancelled => _cancelled || cancelToken.cancelled;

  bool get done => _done;

  Object? get error => _error;

  Object? get result => _result;

  void cancel() {
    if (cancelled || done) return;
    _cancelled = true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _doneEmitter.clear();
    _successEmitter.clear();
    _errorEmitter.clear();
    _detachEmitter.clear();
  }

  void on({
    VoidCallback? success,
    VoidCallback? end,
    VoidCallback? done,
    VoidCallback? cancel,
    VoidCallback? detach,
    void Function(Object)? error,
  }) {
    if (success != null) _successEmitter.on(success);
    if (end != null) {
      _doneEmitter.on(end);
      cancelToken.on(cancel: end);
    }
    if (success != null) _successEmitter.on(success);
    if (error != null) _errorEmitter.on(error);
    if (detach != null) _detachEmitter.on(detach);
    if (done != null) _doneEmitter.on(done);
  }

  void onDetach() {
    if (_detached) return;
    _detached = true;
    _detachEmitter.emit(null);
    dispose();
  }

  void onDone(Object? error, Object? result) {
    if (cancelled || done) return;
    _done = true;
    _error = error;
    if (error != null) {
      cubix._error;
    }
    if (error == null) {
      _result = result;
      _successEmitter.emit(null);
    } else {
      _errorEmitter.emit(error);
    }
    _doneEmitter.emit(null);
  }
}

abstract class IDependency {
  Object? get key;
  Type get resolvedType;

  void dispose();
  void resolve(DependencyResolver resolver, {Object? key, Type? resolvedType});
}

class IncompatibleException with Exception {
  final String message;

  IncompatibleException(this.message);
}

class InitContext {
  final cancelToken = CancelToken();

  InitContext();

  void cancel() => cancelToken.cancel();
}

class ResolveContext {
  final DependencyResolver _resolver;
  final Cubix _cubix;
  final _removeSyncCallbacks = CallbackGroup();

  ResolveContext(this._cubix, this._resolver);

  void dispose() {
    _removeSyncCallbacks.call();
  }

  T resolve<T extends Cubix>(CreateCubix<T> create, {Object? family}) {
    return _resolver.resolve(create, family: family);
  }

  VoidCallback sync(
    List<Cubix> dependencies,
    void Function(CancelToken cancelToken) syncFn,
  ) {
    final removeSyncCallback = CallbackGroup();
    CancelToken? lastToken;

    removeSyncCallback.add(() {
      lastToken?.cancel();
      _removeSyncCallbacks.remove(removeSyncCallback.call);
    });

    void handleChange() {
      if (_cubix.disposed) return;
      lastToken?.cancel();
      syncFn(lastToken = CancelToken());
    }

    for (final cubix in dependencies) {
      final subscription = cubix.cubit.stream.listen((event) => handleChange());
      removeSyncCallback.add(subscription.cancel);
    }

    handleChange();

    _removeSyncCallbacks.add(removeSyncCallback.call);

    return removeSyncCallback.call;
  }
}

abstract class SyncAction<TResult, TState> extends ActionBase<TResult, TState> {
  @override
  TResult onDispatch(Dispatcher dispatcher) {
    try {
      if (dispatcher.cancelled == true) {
        throw CancelledException('Action is cancelled');
      }

      final result = body();
      dispatcher.onDone(null, result);
      return result;
    } catch (e) {
      dispatcher.onDone(e, null);
      rethrow;
    }
  }

  @override
  Future<TResult> wait() {
    if (dispatcher.error != null) {
      return Future.error(dispatcher.error!);
    }
    return Future.value(dispatcher.result as TResult);
  }
}

abstract class VoidAction<TState extends Object?>
    extends SyncAction<void, TState> {
  @override
  void body() {}
}

enum _AwaitType { race, all, allSettled }

class _Emitter<T extends Object?> {
  final bool once;

  final handlers = <void Function(T)>[];

  var _disposed = false;
  var _emitted = false;

  late T _lastEvent;

  _Emitter([this.once = true]);

  bool get emitted => _emitted;

  void clear() {
    handlers.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clear();
  }

  void emit(T e) {
    if (once && _emitted) return;

    _emitted = true;
    _lastEvent = e;

    final copy = [...handlers];
    for (final callback in copy) {
      callback(e);
    }

    if (once) {
      clear();
    }
  }

  void off(void Function(T) handler) {
    handlers.remove(handler);
  }

  void on(Function handler) {
    void Function(T) wrapper;
    if (handler is VoidCallback) {
      wrapper = (e) => handler();
    } else if (handler is void Function(T)) {
      wrapper = handler;
    } else {
      wrapper = (e) => handler(e);
    }

    if (once && _emitted) {
      wrapper(_lastEvent);
      return;
    }

    handlers.add(wrapper);
  }
}

enum _Props { throttleLastExecutionTime }

extension DependencyResolverExtension on DependencyResolver {
  void broadcast(ActionBase Function() actionCreator,
      {CancelToken? cancelToken}) {
    final testAction = actionCreator();
    walk((dependency) {
      if (dependency is Cubix && testAction.canDispatch(dependency)) {
        dependency.dispatchGeneric(actionCreator(), cancelToken: cancelToken);
      }
      return true;
    });
  }
}

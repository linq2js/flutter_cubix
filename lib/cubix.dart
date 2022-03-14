import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// cancel all action rule
Rule cancelAll<TAction extends Object?>([bool Function(Action)? predicate]) {
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
    dispatcher.onCancel(Timer(duration, next).cancel);
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
      last.onEnd(next);
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

abstract class Action<TResult, TState> {
  late final Cubix<TState> cubix;
  late final Dispatcher _dispatcher;

  void Function(Object)? onError;

  VoidCallback? onSuccess;

  VoidCallback? onDone;

  bool get cancelled => _dispatcher.cancelled;

  bool get done => _dispatcher.done;

  Object? get error => _dispatcher.error;

  TState get state => cubix.state;

  set state(TState state) {
    if (cancelled) return;
    cubix.state = state;
  }

  TResult body();

  void cancel() => _dispatcher.cancel();

  TResult dispatch({
    required Map<Object?, Object?> data,
    CancelToken? cancelToken,
  });

  void onResolve(DependencyResolver resolver) {}

  void _resolve(DependencyResolver resolver) {
    onResolve(resolver);
  }
}

abstract class AsyncAction<TResult, TState>
    extends Action<Future<TResult>, TState> {
  List<Rule> get rules => [];

  @override
  Future<TResult> dispatch({
    required ActionData data,
    CancelToken? cancelToken,
  }) {
    cancelToken ??= CancelToken();

    _dispatcher = Dispatcher(
        cubix: cubix,
        dispatching: cubix.cubit.state.dispatchers,
        cancelToken: cancelToken,
        action: this,
        data: data);
    final completer = Completer<TResult>();
    final invoker = rules.reversed.fold<VoidCallback>(
      () {
        if (cancelToken!.cancelled) return;
        body().then((value) {
          if (cancelToken!.cancelled) return;
          completer.complete(value);
          _dispatcher._onDone(null);
        }, onError: (error) {
          if (cancelToken!.cancelled) return;
          completer.completeError(error);
          _dispatcher._onDone(error);
        });
      },
      (next, m) => () {
        if (cancelToken!.cancelled) return;
        m(_dispatcher, next);
      },
    );

    if (onDone != null) _dispatcher.onDone(onDone!);
    if (onSuccess != null) _dispatcher.onSuccess(onSuccess!);
    if (onError != null) _dispatcher.onError(onError!);
    _dispatcher.onEnd(() {
      cubix.cubit.update(remove: _dispatcher);
      _dispatcher.dispose();
    });

    cubix.cubit.update(add: _dispatcher);
    invoker();
    return completer.future;
  }
}

class AsyncState<TData> {}

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

  void onCancel(VoidCallback handler) {
    if (cancelled) {
      handler();
      return;
    }
    _cancelEmitter.on(handler);
  }
}

class CreateContext {
  final DependencyResolver _resolver;
  _SyncConfigs? _sync;
  final dependencies = <Cubix>[];

  CreateContext(this._resolver);

  void enableSync({Duration? debounce}) {
    _sync = _SyncConfigs(debounce: debounce);
  }

  T resolve<T extends Cubix>(CreateCubix<T> create, {Object? family}) {
    final cubix = _resolver.resolve(create, family: family);
    dependencies.add(cubix);
    return cubix;
  }
}

abstract class Cubix<TState> {
  final CubitWrapper<TState> cubit;
  final _data = <Type, ActionData>{};

  Object? _key;

  DependencyResolver? _resolver;
  Type? _resolvedType;
  CancelToken? _syncCancelToken;

  var _disposed = false;

  final _disposeEmitter = _Emitter();

  var _resolved = false;

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

  Object? get key => _key;

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

  /// cancel all dispatching actions
  void cancel() {
    if (cubit.state.dispatchers.isEmpty) return;
    final prevState = cubit.update(dispatchers: []);
    for (final dispatcher in prevState.dispatchers) {
      dispatcher.cancel();
    }
  }

  /// dispatch specified action and return the result of action body
  TResult dispatch<TResult>(
    Action<TResult, TState> action, {
    CancelToken? cancelToken,
  }) {
    action.cubix = this;
    var actionData = _data[action.runtimeType];
    if (actionData == null) {
      _data[action.runtimeType] = actionData = {};
    }
    if (_resolved) {
      action._resolve(resolver);
    }
    onDispatch(action);
    return action.dispatch(cancelToken: cancelToken, data: actionData);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _syncCancelToken?.cancel();
    _disposeEmitter.emit(null);
  }

  /// return true if there is any action dispatching
  /// ```dart
  ///   cubix,loading()
  ///   cubix.loading<ActionType>()
  ///   cubix.loading((action) => action is ActionType1 || action is ActionType2 || action.prop == something);
  /// ```
  bool loading<TAction extends Object?>([bool Function(Action)? predicate]) {
    // using predicate to check action is dispatching or not
    if (predicate != null) {
      return cubit.state.dispatchers
          .any((element) => predicate(element.action));
    }
    // no action type
    if (null is TAction) {
      return cubit.state.dispatchers.isNotEmpty;
    }
    // with action type
    return cubit.state.dispatchers.any((element) => element.action is TAction);
  }

  void onChange(Change<TState> change) {}

  /// when cubix is created, this method will be called to make sure all cubix dependencies are resolved
  void onCreate(CreateContext context) {}

  /// this method will be called whenever action dispatches
  void onDispatch(Action action) {}

  void onError(Object error, StackTrace stackTrace) {}

  /// this method will run once if sync configs is not enabled
  /// if sync configs is enabled, it will run whenever dependency cubixes are updated
  void onInit(InitContext context) {}

  void remove() {
    resolver.remove(this);
  }

  void resolve(DependencyResolver resolver, {Object? key, Type? resolvedType}) {
    _resolved = true;
    _key = key;
    _resolvedType = resolvedType ?? runtimeType;
    _resolver = resolver;

    VoidCallback? handleChange;
    final context = CreateContext(resolver);
    onCreate(context);
    final sync = context._sync;
    if (sync != null) {
      handleChange = () {
        if (_disposed) return;
        _syncCancelToken?.cancel();
        final context = InitContext();
        _syncCancelToken = context.cancelToken;
        if (sync.debounce != null) {
          context.cancelToken
              .onCancel(Timer(sync.debounce!, () => onInit(context)).cancel);
        } else {
          onInit(context);
        }
      };

      for (final cubix in context.dependencies) {
        final subscription =
            cubix.cubit.stream.listen((event) => handleChange!());
        _disposeEmitter.on(subscription.cancel);
      }
    } else {
      final context = InitContext();
      _syncCancelToken = context.cancelToken;
      onInit(context);
    }
  }
}

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

mixin CubixMixin<TState> {
  void Function(Object error, StackTrace stackTrace)? _onError;
  void Function(Change<CubixState<TState>> change)? _onChange;

  void on(
      {Function(Object error, StackTrace stackTrace)? error,
      Function(Change<CubixState<TState>> change)? change}) {
    _onChange = change;
    _onError = error;
  }

  void fireOnChange(Change<CubixState<TState>> change) {
    _onChange?.call(change);
  }

  void fireOnError(Object error, StackTrace stackTrace) {
    _onError?.call(error, stackTrace);
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

class DependencyResolver {
  final _dependencies = <Type, Map<Object?, Cubix>>{};

  void add<T extends Cubix>(T dependency, [Object? family]) {
    final collection = _collection(T);
    collection[family] = dependency;
  }

  void remove<TCubix extends Cubix>(TCubix cubix) {
    final collection = _collection(cubix.resolvedType);
    collection.remove(cubix._key);
    cubix.dispose();
  }

  T resolve<T extends Cubix>(
    CreateCubix<T> create, {
    Object? family,
  }) {
    var collection = _collection(T);
    var obj = collection[family] as T?;
    if (obj != null) return obj;
    obj = create();
    collection[family] = obj;
    obj.resolve(this, key: family, resolvedType: T);
    return obj;
  }

  Map<Object?, Cubix> _collection(Type type) {
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
  final Action action;

  final Cubix cubix;
  final _doneEmitter = _Emitter();
  final _errorEmitter = _Emitter<Object>();
  final _successEmitter = _Emitter();

  bool _done = false;
  Object? _error;

  var _disposed = false;

  Dispatcher({
    required this.cubix,
    required this.action,
    required this.cancelToken,
    required this.dispatching,
    required this.data,
  }) {
    onCancel(cancel);
  }

  bool get cancelled => cancelToken.cancelled;

  bool get done => _done;

  Object? get error => _error;

  void cancel() {
    if (cancelled || done) return;
    cancelToken.cancel();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _doneEmitter.clear();
    _successEmitter.clear();
    _errorEmitter.clear();
  }

  void onCancel(VoidCallback callback) {
    cancelToken.onCancel(callback);
  }

  void onDone(VoidCallback callback) {
    if (cancelled) return;
    if (_done) {
      return callback();
    }
    _doneEmitter.on(callback);
  }

  void onEnd(VoidCallback callback) {
    onDone(callback);
    onCancel(callback);
  }

  void onError(void Function(Object) callback) {
    if (cancelled || done) return;
    if (_done && _error != null) {
      return callback(_error!);
    }
    _errorEmitter.on(callback);
  }

  void onSuccess(VoidCallback callback) {
    if (cancelled || done) return;
    if (_done && _error == null) {
      return callback();
    }
    _successEmitter.on(callback);
  }

  void _onDone(Object? error) {
    if (cancelled || done) return;
    _done = true;
    _error = error;
    if (error == null) {
      _successEmitter.emit(null);
    } else {
      _errorEmitter.emit(error);
    }
    _doneEmitter.emit(null);
  }
}

class InitContext {
  final cancelToken = CancelToken();

  InitContext();
}

abstract class SyncAction<TResult, TState> extends Action<TResult, TState> {
  @override
  TResult dispatch({
    required Map<Object?, Object?> data,
    CancelToken? cancelToken,
  }) {
    cancelToken ??= CancelToken();
    _dispatcher = Dispatcher(
        cubix: cubix,
        action: this,
        cancelToken: cancelToken,
        dispatching: [],
        data: data);

    if (cancelToken.cancelled == true) {
      throw Exception('Action is cancelled');
    }

    try {
      final result = body();
      _dispatcher._onDone(null);
      return result;
    } catch (e) {
      _dispatcher._onDone(e);
      rethrow;
    }
  }
}

class _Emitter<T extends Object?> {
  final handlers = <void Function(T)>[];

  void clear() {
    handlers.clear();
  }

  void emit(T e) {
    final copy = [...handlers];
    for (final callback in copy) {
      callback(e);
    }
  }

  void off(void Function(T) handler) {
    handlers.remove(handler);
  }

  void on(Function handler) {
    if (handler is VoidCallback) {
      handlers.add((e) => handler());
    } else if (handler is void Function(T)) {
      handlers.add(handler);
    } else {
      handlers.add((e) => handler(e));
    }
  }
}

enum _Props { throttleLastExecutionTime }

class _SyncConfigs {
  final Duration? debounce;
  _SyncConfigs({this.debounce});
}

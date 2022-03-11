library cubix;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Transformer debounce(Duration duration) {
  return (context, next) {
    context.previous?.cancelToken.cancel();
    context.cancelToken.onCancel(Timer(duration, next).cancel);
  };
}

Transformer droppable() {
  return (context, next) {
    if (context.count >= 2) {
      return context.cancelToken.cancel();
    }
    next();
  };
}

Transformer sequential() {
  return (context, next) {
    if (context.previous != null) {
      context.previous!.onDone(next);
    } else {
      next();
    }
  };
}

Transformer throttle(Duration duration) {
  return (context, next) {
    final lastTime = context.get<DateTime?>(_Props.throttleLastExecutionTime);
    final now = DateTime.now();
    final nextTime = lastTime?.add(duration);
    if (nextTime == null || nextTime.compareTo(now) <= 0) {
      context.set(_Props.throttleLastExecutionTime, now);
      next();
    }
  };
}

Future<T> _neverDone<T>() => Completer<T>().future;

void _noop() {}

typedef CreateCubix<T extends Cubix> = T Function();

typedef OnCancel = VoidCallback Function(VoidCallback handler);

typedef ResolveCubix<T extends Cubix> = T Function(BuildContext context);

typedef Transformer = void Function(
    TransformContext context, VoidCallback next);

class AsyncContext {
  final bool Function() _isCancelled;
  final OnCancel _onCancel;
  final _onDispose = <VoidCallback>[];

  AsyncContext(this._isCancelled, this._onCancel);

  bool get cancelled => _isCancelled();

  CancelToken createCancelToken() {
    return CancelToken(_isCancelled);
  }

  void dispose() {
    for (final callback in _onDispose) {
      callback();
    }
  }

  VoidCallback onCancel(VoidCallback handler) {
    if (_isCancelled()) return _noop;
    final unsubscribe = _onCancel(() {
      if (_isCancelled()) return;
      handler();
    });
    _onDispose.add(unsubscribe);
    return unsubscribe;
  }
}

abstract class AsyncCubix<T> extends Cubix<AsyncState<T>> {
  var _token = Object();
  final _onCancelHandlers = <VoidCallback>{};

  AsyncCubix(T initialState) : super(AsyncState(initialState));

  T get data => state.data;

  Object? get error => state.error;

  bool get loading => state.loading;

  Future<T> get ready async {
    if (state.loading) {
      StreamSubscription<AsyncState<T>>? subscription;
      final completer = Completer<T>();
      subscription = stream.listen((event) {
        if (event.loading) return;
        subscription?.cancel();
        if (_disposed) return;
        if (event.error != null) {
          completer.completeError(event.error!);
        } else {
          completer.complete(event.data);
        }
      });
    }
    if (state.error != null) {
      throw state.error!;
    }
    return state.data;
  }

  /// emit new state that is returned from loader
  @protected
  Future<void> asyncData(Future<T> Function(AsyncContext context) loader,
      {CancelToken? cancelToken}) {
    if (cancelToken?.cancelled == true) return _neverDone();

    _emit(AsyncState(state.data, loading: true));
    final token = _token;
    final completer = Completer<void>();
    final context = AsyncContext(
        () => _token != token || cancelToken?.cancelled == true, _onCancel);

    loader(context).then(
      (value) {
        context.dispose();
        if (cancelToken?.cancelled == true) return;
        if (_emit(AsyncState(value), token)) {
          completer.complete();
        }
      },
      onError: (error) {
        context.dispose();
        if (cancelToken?.cancelled == true) return;
        if (_emit(AsyncState(state.data, error: error), token)) {
          completer.completeError(error);
        }
      },
    );
    return completer.future;
  }

  /// cancel all async emitting / dispatching / updating if any
  @override
  void cancel() {
    if (_disposed) return;
    super.cancel();
    final handlers = {..._onCancelHandlers};
    _onCancelHandlers.clear();
    for (final callback in handlers) {
      callback();
    }
    emit(AsyncState(state.data));
  }

  /// dispatch async action and handle loading state and error state if any
  @protected
  Future<TResult> dispatchAsync<TResult>(
    Future<TResult> Function(DispatchAsyncContext<T> context) action, {
    Function? key,
    List<Transformer>? transform,
    CancelToken? cancelToken,
  }) {
    if (cancelToken?.cancelled == true) return _neverDone();
    if (transform != null || key != null) {
      if (transform == null || key == null) {
        throw Exception('transform and key cannot be null');
      }
      final originAction = action;
      action = (context) =>
          this.transform(key, transform, () => originAction(context));
    }

    _emit(AsyncState(state.data, loading: true));

    var token = _token;
    final context = DispatchAsyncContext<T>(
      (T value) {
        if (cancelToken?.cancelled == true) return;
        if (_emit(AsyncState(value), token)) {
          token = _token;
        }
      },
      () => _token != token || cancelToken?.cancelled == true,
      _onCancel,
    );
    final completer = Completer<TResult>();

    action(context).then(
      (value) {
        context.dispose();
        if (cancelToken?.cancelled == true) return;
        completer.complete(value);
      },
      onError: (error, stackTrace) {
        context.dispose();
        if (error == null) return;
        if (cancelToken?.cancelled == true) return;
        if (_emit(AsyncState(state.data, error: error), token)) {
          completer.completeError(error);
        }
      },
    );

    return completer.future;
  }

  /// dispatch sync action and handle error state if any
  @protected
  void dispatchSync(T Function() loader) {
    try {
      _emit(AsyncState(loader()));
    } catch (e) {
      _emit(AsyncState(state.data, error: e));
    }
  }

  @override
  void emit(AsyncState<T> state) {
    if (_disposed || state == this.state) return;
    _token = Object();
    super.emit(state);
  }

  @protected
  void syncData(T data) {
    emit(AsyncState(data));
  }

  bool _emit(AsyncState<T> state, [Object? token]) {
    token ??= _token;
    if (token != _token) return false;
    emit(state);
    return true;
  }

  VoidCallback _onCancel(VoidCallback handler) {
    var active = true;
    _onCancelHandlers.add(handler);
    return () {
      if (!active) return;
      active = false;
      _onCancelHandlers.remove(handler);
    };
  }
}

class AsyncState<T> {
  final T data;
  final bool loading;
  final Object? error;

  AsyncState(this.data, {this.loading = false, this.error});

  @override
  int get hashCode => loading.hashCode ^ error.hashCode ^ data.hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! AsyncState) return false;
    return other.loading == loading &&
        other.data == data &&
        other.error == error;
  }
}

class CancelToken {
  final bool Function()? _isCancelled;
  final _onCancel = <VoidCallback>{};
  var _cancelled = false;

  CancelToken([this._isCancelled]);

  bool get cancelled => _cancelled || _isCancelled?.call() == true;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final handler in _onCancel) {
      handler();
    }
  }

  void onCancel(VoidCallback handler) {
    _onCancel.add(handler);
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

  T fromContext<T extends Cubix>(ResolveCubix<T> resolve, {Object? family}) {
    final cubix = _resolver.resolve(resolve: resolve, family: family);
    dependencies.add(cubix);
    return cubix;
  }

  T fromCreator<T extends Cubix>(CreateCubix<T> create, {Object? family}) {
    final cubix = _resolver.resolve(create: create, family: family);
    dependencies.add(cubix);
    return cubix;
  }
}

abstract class Cubix<T> extends Cubit<T> {
  var _disposed = false;
  final _onDispose = <VoidCallback>{};
  final _transformData = <Object?, Map<Object?, Object?>>{};
  final _executing = <Function>[];
  late final DependencyResolver _resolver;
  late final Type _resolvedType;
  Object? _key;
  Timer? _syncTimer;

  Cubix(T initialState) : super(initialState);

  Object? get key => _key;

  /// cancel all async emitting / dispatching / updating if any
  void cancel() {
    if (_disposed) return;
    _syncTimer?.cancel();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancel();
    for (final callback in _onDispose) {
      callback();
    }
  }

  /// when cubix is created, this method will be called to make sure all cubix dependencies are resolved
  void onCreate(CreateContext context) {}

  /// this method will run once if sync configs is not enabled
  /// if sync configs is enabled, it will run whenever dependency cubixes are updated
  void onInit() {}

  Future<TResult> transform<TResult>(
    Function key,
    List<Transformer> trasnformers,
    Future<TResult> Function() execute, {
    CancelToken? cancelToken,
  }) {
    cancelToken ??= CancelToken();
    var done = false;
    final completer = Completer<TResult>();

    if (trasnformers.isEmpty) {
      throw Exception('transformers cannot be empty');
    }

    TransformContext? current;
    var data = _transformData[key];
    if (data == null) {
      data = {};
      _transformData[key] = data;
    }

    void onDone() {
      if (done) return;
      done = true;
      if (data![_Props.previousContext] == current) {
        data.remove(_Props.previousContext);
      }
      _executing.remove(key);
    }

    void next() {
      execute().then(
        (result) {
          if (cancelToken?.cancelled == true) return;
          completer.complete(result);
        },
        onError: (e) {
          if (cancelToken?.cancelled == true) return;
          completer.completeError(e);
        },
      ).whenComplete(onDone);
    }

    cancelToken.onCancel(onDone);

    _executing.add(key);

    final context = current = TransformContext(
      data[_Props.previousContext] as TransformContext?,
      key,
      data,
      cancelToken,
      completer.future,
      _executing,
    );
    data[_Props.previousContext] = current;
    final invoker = trasnformers.reversed.fold<VoidCallback>(
      next,
      (next, m) => () {
        if (cancelToken?.cancelled == true) return;
        m(context, next);
      },
    );
    invoker();

    return completer.future;
  }

  /// remove cubix from provider
  void _remove() {
    _resolver.remove(this);
  }

  /// start resolving cubix dependencies
  void _resolve(DependencyResolver resolver, Type resolvedType, Object? key) {
    _resolver = resolver;
    _resolvedType = resolvedType;
    _key = key;
    VoidCallback? handleChange;
    final context = CreateContext(resolver);
    onCreate(context);
    final sync = context._sync;
    if (sync != null) {
      handleChange = () {
        if (_disposed) return;
        cancel();
        if (sync.debounce != null) {
          _syncTimer = Timer(sync.debounce!, onInit);
        } else {
          onInit();
        }
      };
    }

    for (final cubix in context.dependencies) {
      if (handleChange != null) {
        final subscription = cubix.stream.listen((event) => handleChange!());
        _onDispose.add(subscription.cancel);
      }
    }

    onInit();
  }
}

class CubixBuilder<TCubix extends Cubix> extends StatefulWidget {
  final bool Function(Object? prev, Object? next)? buildWhen;
  final CreateCubix<TCubix>? create;
  final Object? family;
  final ResolveCubix<TCubix>? resolve;
  final Widget Function(BuildContext context, TCubix cubix) builder;
  final bool transient;

  const CubixBuilder({
    Key? key,
    this.create,
    this.resolve,
    this.family,
    this.buildWhen,

    /// remove cubix automatically when the widget is disposed
    this.transient = false,
    required this.builder,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return CubixBuilderState<TCubix>();
  }
}

class CubixBuilderState<TCubix extends Cubix>
    extends State<CubixBuilder<TCubix>> {
  TCubix? cubix;

  @override
  Widget build(BuildContext context) {
    final resolver = RepositoryProvider.of<DependencyResolver>(context);
    final nextCubix = resolver.resolve(
      create: widget.create,
      resolve: widget.resolve,
      family: widget.family,
    );

    if (cubix != nextCubix && widget.transient) {
      cubix?.dispose();
    }

    cubix = nextCubix;

    return BlocBuilder(
      bloc: cubix,
      buildWhen: widget.buildWhen,
      builder: (_, __) => widget.builder(context, cubix!),
    );
  }

  @override
  void dispose() {
    super.dispose();
    if (widget.transient && cubix != null) {
      cubix?._remove();
    }
  }
}

class CubixListener<TCubix extends Cubix> extends StatefulWidget {
  final void Function(BuildContext context, TCubix cubix) listener;
  final bool Function(Object? prev, Object? next)? listenWhen;
  final CreateCubix<TCubix>? create;
  final Object? family;
  final ResolveCubix<TCubix>? resolve;
  final Widget child;
  final bool transient;

  const CubixListener({
    Key? key,
    this.create,
    this.resolve,
    this.family,
    this.listenWhen,

    /// remove cubix automatically when the widget is disposed
    this.transient = false,
    required this.listener,
    required this.child,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return CubixListenerState<TCubix>();
  }
}

class CubixListenerState<TCubix extends Cubix>
    extends State<CubixListener<TCubix>> {
  TCubix? cubix;

  @override
  Widget build(BuildContext context) {
    final resolver = RepositoryProvider.of<DependencyResolver>(context);
    final nextCubix = resolver.resolve(
      create: widget.create,
      resolve: widget.resolve,
      family: widget.family,
    );

    if (cubix != nextCubix && widget.transient) {
      cubix?.dispose();
    }

    cubix = nextCubix;

    return BlocListener(
      bloc: cubix,
      listener: (context, _) => widget.listener(context, cubix!),
      listenWhen: widget.listenWhen,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    super.dispose();
    if (widget.transient && cubix != null) {
      cubix?._remove();
    }
  }
}

class CubixProvider extends StatelessWidget {
  final Widget child;

  const CubixProvider({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) => DependencyResolver(context),
      child: child,
    );
  }
}

class DependencyResolver {
  final _dependencies = <Type, Map<Object?, Cubix>>{};
  final BuildContext context;

  DependencyResolver(this.context);

  void add<T extends Cubix>(T dependency, [Object? family]) {
    final collection = _collection(T);
    collection[family] = dependency;
  }

  void remove<TCubix extends Cubix>(TCubix cubix) {
    final collection = _collection(cubix._resolvedType);
    collection.remove(cubix._key);
    cubix.dispose();
  }

  T resolve<T extends Cubix>({
    ResolveCubix<T>? resolve,
    CreateCubix<T>? create,
    Object? family,
  }) {
    var collection = _collection(T);
    var obj = collection[family] as T?;
    if (obj != null) return obj;
    obj = create != null
        ? create()
        : resolve != null
            ? resolve(context)
            : throw Exception('No dependency found $T');
    collection[family] = obj;
    obj._resolve(this, T, family);
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

class DispatchAsyncContext<T> extends AsyncContext {
  final void Function(T value) _emit;

  DispatchAsyncContext(
    this._emit,
    bool Function() isCancelled,
    OnCancel onCancel,
  ) : super(isCancelled, onCancel);

  void emit(T value) {
    _emit(value);
  }
}

class TransformContext {
  final Function key;
  final Map<Object?, Object?> _data;
  final CancelToken cancelToken;
  final Future _future;
  final List<Function> executing;
  final TransformContext? previous;

  TransformContext(
    this.previous,
    this.key,
    this._data,
    this.cancelToken,
    this._future,
    this.executing,
  );

  int get count => executing.where((element) => element == key).length;

  T? get<T extends Object?>(Object? name) {
    return _data[name] as T?;
  }

  void onDone(VoidCallback callback) {
    _future.whenComplete(callback);
  }

  set(Object? name, Object? value) {
    _data[name] = value;
  }

  T tryGet<T extends Object?>(Object? name, T Function() create) {
    if (_data.containsKey(name)) {
      return _data[name] as T;
    }
    return _data[name] = create();
  }
}

enum _Props { previousContext, throttleLastExecutionTime }

class _SyncConfigs {
  final Duration? debounce;
  _SyncConfigs({this.debounce});
}

extension BuildContextExtension on BuildContext {
  /// get cubix that matches type T
  T cubix<T extends Cubix>(CreateCubix<T> create, {Object? family}) {
    return RepositoryProvider.of<DependencyResolver>(this).resolve(
      create: create,
      family: family,
    );
  }
}

extension CubixFactoryExtension<TCubit extends Cubix> on TCubit Function() {
  /// build a widget with specified T cubix
  Widget build(
    Widget Function(BuildContext context, TCubit cubix) builder, {
    Object? family,

    /// remove cubix automatically when the widget is disposed
    bool transient = false,
  }) {
    return CubixBuilder<TCubit>(
      create: this,
      builder: builder,
      family: family,
      transient: transient,
    );
  }

  Widget buildWhen<TState>(
    bool Function(TState prev, TState next) condition,
    Widget Function(BuildContext context, TCubit cubix) builder, {
    Object? family,

    /// remove cubix automatically when the widget is disposed
    bool transient = false,
  }) {
    return CubixBuilder<TCubit>(
      create: this,
      buildWhen: (prev, next) => condition(prev as TState, next as TState),
      builder: builder,
      family: family,
      transient: transient,
    );
  }

  Widget listen(
    void Function(BuildContext context, TCubit cubix) listener,
    Widget child, {
    Object? family,

    /// remove cubix automatically when the widget is disposed
    bool transient = false,
  }) {
    return CubixListener<TCubit>(
      create: this,
      listener: listener,
      child: child,
      family: family,
      transient: transient,
    );
  }

  Widget listenWhen<TState>(
    bool Function(TState prev, TState next) condition,
    void Function(BuildContext context, TCubit cubix) listener,
    Widget child, {
    Object? family,

    /// remove cubix automatically when the widget is disposed
    bool transient = false,
  }) {
    return CubixListener<TCubit>(
      create: this,
      listenWhen: (prev, next) => condition(prev as TState, next as TState),
      listener: listener,
      child: child,
      family: family,
      transient: transient,
    );
  }
}

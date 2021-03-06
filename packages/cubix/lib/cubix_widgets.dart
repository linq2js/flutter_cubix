import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'cubix.dart';

class Cubiw {
  final Object? family;

  Cubiw([this.family]);
}

class CubixBuilder<TCubix extends Cubix> extends StatefulWidget {
  final bool Function(Object? prev, Object? next)? buildWhen;
  final CreateCubix<TCubix> create;
  final Object? family;
  final Widget Function(BuildContext context, TCubix cubix) builder;
  final bool transient;

  const CubixBuilder({
    Key? key,
    required this.create,
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
  final _defaultFamily = Object();

  bool get transient => widget.transient || widget.family is Cubiw;

  @override
  Widget build(BuildContext context) {
    final resolver = RepositoryProvider.of<DependencyResolver>(context);
    var family = widget.family;
    if (family is Cubiw) {
      family = family.family ?? _defaultFamily;
    }
    final nextCubix = resolver.resolve(
      widget.create,
      family: family,
    );

    if (cubix != nextCubix && transient) {
      cubix?.remove();
    }

    cubix = nextCubix;

    return BlocBuilder(
      bloc: cubix?.cubit,
      buildWhen: widget.buildWhen,
      builder: (_, __) => widget.builder(context, cubix!),
    );
  }

  @override
  void dispose() {
    super.dispose();
    if (transient) {
      cubix?.remove();
    }
  }
}

class CubixListener<TCubix extends Cubix> extends StatefulWidget {
  final void Function(BuildContext context, TCubix cubix) listener;
  final bool Function(Object? prev, Object? next)? listenWhen;
  final CreateCubix<TCubix> create;
  final Object? family;
  final Widget child;
  final bool transient;

  const CubixListener({
    Key? key,
    required this.create,
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
      widget.create,
      family: widget.family,
    );

    if (cubix != nextCubix && widget.transient) {
      cubix?.dispose();
    }

    cubix = nextCubix;

    return BlocListener(
      bloc: cubix?.cubit,
      listener: (context, _) => widget.listener(context, cubix!),
      listenWhen: widget.listenWhen,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    super.dispose();
    if (widget.transient && cubix != null) {
      cubix?.remove();
    }
  }
}

class CubixProvider extends StatelessWidget {
  final Widget child;
  final void Function(DependencyResolver resolve)? dependencies;

  const CubixProvider({Key? key, required this.child, this.dependencies})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) {
        final resolver = DependencyResolver();
        dependencies?.call(resolver);
        return resolver;
      },
      child: child,
    );
  }
}

extension BuildContextExtension on BuildContext {
  DependencyResolver get resolver {
    return RepositoryProvider.of<DependencyResolver>(this);
  }

  void broadcast(ActionBase Function() actionCreator,
      {CancelToken? cancelToken}) {
    resolver.broadcast(actionCreator, cancelToken: cancelToken);
  }

  /// get cubix that matches type T
  T cubix<T extends Cubix>(CreateCubix<T> create, {Object? family}) {
    return resolver.resolve(
      create,
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
      buildWhen: (prev, next) => condition(
        (prev as CubixState<TState>).state,
        (next as CubixState<TState>).state,
      ),
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

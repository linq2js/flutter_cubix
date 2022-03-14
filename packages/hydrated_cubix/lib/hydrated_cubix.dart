library hydrated_cubix;

import 'package:cubix/cubix.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

class HydratedCubitWrapper<TState> extends HydratedCubit<CubixState<TState>>
    with CubixMixin<TState>
    implements CubitWrapper<TState> {
  HydratedCubitWrapper(TState initialState) : super(CubixState(initialState));

  @override
  CubixState<TState>? fromJson(Map<String, dynamic> json) {
    return null;
  }

  @override
  Map<String, dynamic>? toJson(CubixState<TState> state) {
    return null;
  }

  @override
  CubixState<TState> update(
      {TState Function(TState state)? state,
      Dispatcher? remove,
      Dispatcher? add,
      List<Dispatcher>? dispatchers}) {
    return performUpdate(
      () => this.state,
      emit,
      state: state,
      add: add,
      remove: remove,
      dispatchers: dispatchers,
    );
  }
}

abstract class HydratedCubix<TState> extends Cubix<TState> {
  HydratedCubix(TState initialState)
      : super(initialState, HydratedCubitWrapper.new);
}

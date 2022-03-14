import 'package:cubix/cubix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

void main() {
  test('SyncAction #1', () {
    final cubix = TestCubix();
    cubix.dispatch(IncrementAction());
    expect(cubix.state, 1);
    cubix.dispatch(IncrementAction());
    expect(cubix.state, 2);
  });

  test('debounce', () async {
    final cubix = TestCubix();
    cubix.dispatch(DebounceAction());
    cubix.dispatch(DebounceAction());
    cubix.dispatch(DebounceAction());
    expect(cubix.state, 0);
    await Future.delayed(const Duration(milliseconds: 15));
    expect(cubix.state, 1);
  });

  test('sequential', () async {
    final cubix = TestCubix();
    cubix.dispatch(SequentialAction());
    cubix.dispatch(SequentialAction());
    cubix.dispatch(SequentialAction());
    await Future.delayed(const Duration(milliseconds: 40));
    expect(cubix.state, 3);
  });

  test('throttle', () async {
    final cubix = TestCubix();
    cubix.dispatch(ThrottleAction());
    expect(cubix.state, 1);
    cubix.dispatch(ThrottleAction());
    expect(cubix.state, 1);
    cubix.dispatch(ThrottleAction());
    expect(cubix.state, 1);
    await Future.delayed(const Duration(milliseconds: 2));
    cubix.dispatch(ThrottleAction());
    expect(cubix.state, 1);
    await Future.delayed(const Duration(milliseconds: 30));
    cubix.dispatch(ThrottleAction());
    expect(cubix.state, 2);
  });

  test('sync #1', () async {
    final testCubix = TestCubix();
    final resolver = DependencyResolver()..add(testCubix);
    final doubleCubix = DoubleCubix()..resolve(resolver);
    expect(doubleCubix.state, 0);
    testCubix.dispatch(IncrementAction());
    await Future.delayed(Duration.zero);
    expect(doubleCubix.state, 2);
  });

  test('sync #2', () async {
    final resolver = DependencyResolver();
    final doubleCubix = DoubleCubix()..resolve(resolver);
    expect(doubleCubix.state, 0);
  });
}

class DebounceAction extends AsyncAction<void, int> {
  @override
  get rules => [debounce(const Duration(milliseconds: 10))];

  @override
  body() async {
    state++;
  }
}

class DoubleCubix extends HydratedCubix<int> {
  late final TestCubix testCubix;

  DoubleCubix() : super(0);

  @override
  void onResolve(ResolveContext context) {
    super.onResolve(context);
    context.enableSync();
    testCubix = context.resolve(TestCubix.new);
  }

  @override
  void onInit(context) {
    super.onInit(context);
    state = testCubix.state * 2;
  }
}

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

class IncrementAction extends SyncAction<void, int> {
  @override
  body() => state++;
}

class SequentialAction extends AsyncAction<void, int> {
  @override
  get rules => [sequential()];

  @override
  body() async {
    await Future.delayed(const Duration(milliseconds: 10));
    state++;
  }
}

class TestCubix extends Cubix<int> {
  TestCubix() : super(0);
}

class ThrottleAction extends AsyncAction<void, int> {
  @override
  get rules => [throttle(const Duration(milliseconds: 30))];

  @override
  body() async {
    state++;
  }
}

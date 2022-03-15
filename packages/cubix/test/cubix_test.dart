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

  test('race #1', () async {
    final testCubix = TestCubix();
    final action1 = ValuedAsyncAction(1, const Duration(milliseconds: 10));
    final action2 = ValuedAsyncAction(2, const Duration(milliseconds: 5));
    final action3 = ValuedAsyncAction(2, const Duration(milliseconds: 15));
    final result = await testCubix.dispatch(RaceAction({
      1: action1,
      2: action2,
      3: action3,
    }));

    expect(result[2], 2);
  });

  test('race #2', () async {
    final testCubix = TestCubix();
    final action1 = ValuedAsyncAction(1, const Duration(milliseconds: 10));
    final action2 = ValuedAsyncAction(2, const Duration(milliseconds: 5));
    final action3 = ValuedAsyncAction(2, const Duration(milliseconds: 15));
    final result = testCubix.dispatch(RaceAction({
      1: action1,
      2: action2,
      3: action3,
    }));
    action2.cancel();
    expect((await result)[1], 1);
  });

  test('all #1', () async {
    final testCubix = TestCubix();
    final action1 = ValuedAsyncAction(1, const Duration(milliseconds: 10));
    final action2 = ValuedAsyncAction(2, const Duration(milliseconds: 5));
    final action3 = ValuedAsyncAction(3, const Duration(milliseconds: 15));
    final result = await testCubix.dispatch(AllAction({
      1: action1,
      2: action2,
      3: action3,
    }));
    expect(result[1], 1);
    expect(result[2], 2);
    expect(result[3], 3);
  });

  test('all #2', () async {
    final testCubix = TestCubix();
    final action1 = ValuedAsyncAction(1, const Duration(milliseconds: 10));
    final action2 = ValuedAsyncAction(2, const Duration(milliseconds: 5));
    final action3 = ValuedAsyncAction(2, const Duration(milliseconds: 15));
    var done = false;
    final result = testCubix.dispatch(AllAction({
      1: action1,
      2: action2,
      3: action3,
      4: Future.error(Exception('invalid'))
    }));
    result.then((_) => done = true);
    await Future.delayed(const Duration(milliseconds: 30));
    expect(done, false);
  });

  test('allSettled', () async {
    final testCubix = TestCubix();
    final action1 = ValuedAsyncAction(1, const Duration(milliseconds: 10));
    final action2 = ValuedAsyncAction(2, const Duration(milliseconds: 5));
    final action3 = ValuedAsyncAction(3, const Duration(milliseconds: 15));
    final result = await testCubix.dispatch(AllSettledAction({
      1: action1,
      2: action2,
      3: action3,
      4: Future.error(Exception('invalid'))
    }));
    expect(result[1], 1);
    expect(result[2], 2);
    expect(result[3], 3);
    expect(result[4] is Exception, true);
  });

  test('when', () async {
    final testCubix = TestCubix();
    var done = false;
    testCubix.dispatch(WhenAction()).then((value) {
      done = true;
    });
    expect(done, false);
    await Future.delayed(const Duration(milliseconds: 10));
    expect(done, false);
    testCubix.dispatch(IncrementAction());
    await Future.delayed(Duration.zero);
    expect(done, true);
  });

  test('broadcasting', () {
    var result = 0;
    final resolver = DependencyResolver();
    resolver.resolve(() => BroadcastingCubix<int?>(
          0,
          () => result += 1,
        ));
    resolver.resolve(() => BroadcastingCubix<String?>(
          '',
          () => result += 2,
        ));
    resolver.resolve(() => BroadcastingCubix<Object?>(
          null,
          () => result += 4,
        ));
    resolver.broadcast(() => TestAction<int?>());
    expect(result, 1);
  });

  test('canDispatch #1', () {
    final cubix = DynamicCubix();
    expect(() => cubix.dispatch(IncrementAction()),
        throwsA(isA<IncompatibleException>()));
  });

  test('cubix.wait()', () async {
    final cubix = TestCubix();
    cubix.dispatch(IncrementAsyncAction(const Duration(milliseconds: 10)));
    cubix.dispatch(IncrementAsyncAction(const Duration(milliseconds: 15)));
    cubix.dispatch(IncrementAsyncAction(const Duration(milliseconds: 30)));
    expect(cubix.loading(), true);
    final state = await cubix.wait();
    expect(state, 3);
  });
}

class DynamicCubix extends Cubix<Object?> {
  DynamicCubix() : super(null);
}

class NumberCubix extends Cubix<num?> {
  NumberCubix() : super(0);
}

class WhenAction extends AsyncAction<void, int> {
  @override
  body() async {
    await when((action) => action is IncrementAction);
  }
}

class RaceAction extends AsyncAction<Map<Object, Object?>, int> {
  final Map<Object, Object?> awaitable;

  RaceAction(this.awaitable);

  @override
  body() async {
    return await race(awaitable);
  }
}

class BroadcastingCubix<T> extends Cubix<T> {
  final VoidCallback callback;
  BroadcastingCubix(T initialState, this.callback) : super(initialState);

  @override
  void onDispatch(ActionBase action) {
    callback();
  }
}

class TestAction<T> extends SyncAction<void, T> {
  @override
  body() {}
}

class AllAction extends AsyncAction<Map<Object, Object?>, int> {
  final Map<Object, Object?> awaitable;

  AllAction(this.awaitable);

  @override
  body() async {
    return await all(awaitable);
  }
}

class AllSettledAction extends AsyncAction<Map<Object, Object?>, int> {
  final Map<Object, Object?> awaitable;

  AllSettledAction(this.awaitable);

  @override
  body() async {
    return await allSettled(awaitable);
  }
}

class ValuedAsyncAction extends AsyncAction<int, int> {
  final int value;
  final Duration delay;

  ValuedAsyncAction(this.value, this.delay);

  @override
  body() async {
    await Future.delayed(delay);
    return value;
  }
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
  DoubleCubix() : super(0);

  @override
  void onResolve(context) {
    final testCubix = context.resolve(TestCubix.new);

    context.sync([testCubix], (_) => state = testCubix.state * 2);
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

class IncrementAsyncAction extends AsyncAction<void, int> {
  final Duration delay;

  IncrementAsyncAction(this.delay);

  @override
  body() async {
    await Future.delayed(delay);
    state++;
  }
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

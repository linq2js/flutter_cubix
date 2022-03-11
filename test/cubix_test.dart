import 'package:cubix/cubix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debounce', () async {
    final cubix = TestCubix();
    cubix.debounceTest();
    cubix.debounceTest();
    cubix.debounceTest();
    expect(cubix.state, 0);
    await Future.delayed(const Duration(milliseconds: 15));
    expect(cubix.state, 1);
  });

  test('sequential', () async {
    final cubix = TestCubix();
    cubix.sequentialTest();
    cubix.sequentialTest();
    cubix.sequentialTest();
    expect(cubix.state, 0);
    await Future.delayed(const Duration(milliseconds: 15));
    expect(cubix.state, 1);
    await Future.delayed(const Duration(milliseconds: 15));
    expect(cubix.state, 2);
    await Future.delayed(const Duration(milliseconds: 15));
    expect(cubix.state, 3);
  });

  test('throttle', () async {
    final cubix = TestCubix();
    cubix.throttleTest();
    expect(cubix.state, 1);
    cubix.throttleTest();
    expect(cubix.state, 1);
    cubix.throttleTest();
    expect(cubix.state, 1);
    await Future.delayed(const Duration(milliseconds: 2));
    cubix.throttleTest();
    expect(cubix.state, 1);
    await Future.delayed(const Duration(milliseconds: 30));
    cubix.throttleTest();
    expect(cubix.state, 2);
  });

  test('throttle:dispatch', () async {
    final cubix = TestAsyncCubix();
    cubix.throttleTest();
    await Future.delayed(Duration.zero);
    expect(cubix.data, 1);
    cubix.throttleTest();
    await Future.delayed(Duration.zero);
    expect(cubix.data, 1);
    cubix.throttleTest();
    await Future.delayed(Duration.zero);
    expect(cubix.data, 1);
    await Future.delayed(const Duration(milliseconds: 2));
    cubix.throttleTest();
    await Future.delayed(Duration.zero);
    expect(cubix.data, 1);
    await Future.delayed(const Duration(milliseconds: 30));
    cubix.throttleTest();
    await Future.delayed(Duration.zero);
    expect(cubix.data, 2);
  });

  test('flow', () async {
    final cubix = TestFlowCubix();
    cubix.up();
    await Future.delayed(Duration.zero);
    cubix.up();
    await Future.delayed(Duration.zero);
    cubix.down();
    await Future.delayed(Duration.zero);
    cubix.down();
    await Future.delayed(Duration.zero);
    expect(cubix.state, 'upupdowndown');

    cubix.up();
    await Future.delayed(Duration.zero);
    cubix.up();
    await Future.delayed(Duration.zero);
    cubix.down();
    await Future.delayed(Duration.zero);
    cubix.down();
    await Future.delayed(Duration.zero);
    expect(cubix.state, 'upupdowndownupupdowndown');
    cubix.reset();
    cubix.up();
    await Future.delayed(Duration.zero);
    cubix.up();
    expect(cubix.state, 'upup');
    await Future.delayed(Duration.zero);
    cubix.up();
    await Future.delayed(Duration.zero);
    // invalid action, state is reset
    expect(cubix.state, '');
  });
}

class TestFlowCubix extends Cubix<String> {
  TestFlowCubix() : super('');

  Iterable<Object> secretMoves(FlowContext context) sync* {
    context.restartIfInvalid(reset);
    while (true) {
      yield up;
      yield up;
      yield down;
      yield down;
    }
  }

  void reset() {
    emit('');
  }

  void up() {
    transform(up, [flow(secretMoves)], () async {
      emit(state + 'up');
    });
  }

  void down() {
    transform(down, [flow(secretMoves)], () async {
      emit(state + 'down');
    });
  }
}

class TestAsyncCubix extends AsyncCubix<int> {
  TestAsyncCubix() : super(0);

  void throttleTest() {
    dispatchAsync(
      (context) async {
        context.emit(data + 1);
      },
      key: throttleTest,
      transform: [throttle(const Duration(milliseconds: 30))],
    );
  }
}

class TestCubix extends Cubix<int> {
  TestCubix() : super(0);

  void debounceTest() {
    transform(
      debounceTest,
      [debounce(const Duration(milliseconds: 10))],
      () async {
        emit(state + 1);
      },
    );
  }

  void sequentialTest() {
    transform(
      sequentialTest,
      [sequential()],
      () async {
        await Future.delayed(const Duration(milliseconds: 10));
        emit(state + 1);
      },
    );
  }

  void throttleTest() {
    transform(
      throttleTest,
      [throttle(const Duration(milliseconds: 30))],
      () async {
        emit(state + 1);
      },
    );
  }
}

class Ref<T> {
  late final T value;
}

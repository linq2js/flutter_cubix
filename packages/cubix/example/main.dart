// create a cubix
import 'package:cubix/cubix.dart';
import 'package:cubix/cubix_widgets.dart';
import 'package:flutter/material.dart';

class CounterCubix extends Cubix<int> {
  CounterCubix() : super(0);

  // method base action
  void increment() => state++;

  @override
  onDispatch(ActionBase action) {
    // tracking action dispatching
    // cannot track method base actions (increment)
    print(action.runtimeType.toString());
  }
}

// class base action
// using SyncAction for sync code
class DecrementAction extends SyncAction<void, int> {
  final int step;

  DecrementAction([this.step = 1]);

  @override
  body() {
    // update state
    state -= step;
  }
}

class DecrementAsyncAction extends AsyncAction<void, int> {
  final int step;

  DecrementAsyncAction([this.step = 1]);

  @override
  body() async {
    // delay in 2 seconds
    await Future.delayed(const Duration(seconds: 2));
    // perform increment by dispatch another action
    dispatch(DecrementAction(step));
  }
}

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({Key? key}) : super(key: key);

  @override
  build(context) {
    return CubixProvider(
        // build widget from CounterCubix
        // the builder receives BuildContext and Cubix objects
        child: CounterCubix.new.build((context, cubix) {
      return Column(children: [
        // getting state of cubix
        Text(cubix.state.toString()),
        ElevatedButton(
          // resolve cubix from context object
          onPressed: context.cubix(CounterCubix.new).increment,
          child: const Text('Increment'),
        ),
        ElevatedButton(
          // dispatch class base action
          onPressed: () => cubix.dispatch(DecrementAction()),
          child: const Text('Decrement'),
        ),
        ElevatedButton(
          // dispatch class base action with args
          onPressed: () => cubix.dispatch(DecrementAsyncAction(2)),
          child: const Text('Decrement Async'),
        )
      ]);
    }));
  }
}

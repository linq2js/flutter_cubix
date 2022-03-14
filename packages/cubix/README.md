# Cubix

A enhanced state management of Bloc

## Usages

### Simple Cubix

```dart
// create a cubix
class CounterCubix extends Cubix<int> {
    CounterCubix(): super(0);

    // method base action
    void increment() => state++;

    @override
    onDispatch(Action action) {
        // tracking action dispatching
        // cannot track method base actions (increment)
        print(action.runtimeType.toString());
    }
}

// class base action
// using SyncAction for sync code
class DecrementAction extends SyncAction<void, int> {
    final int step;

    DecrementAction(this.step = 1);

    @override
    body() {
        // update state
        state -= step;
    }
}

class DecrementAsyncAction extends AsyncAction<void, int> {
    final int step;

    DecrementAsyncAction(this.step = 1);

    @override
    body() async {
        // delay in 2 seconds
        await Future.delayed(const Duation(seconds: 2));
        // perform increment by dispatch another action
        dispatch(DecrementAction(step));
    }
}

void main() => runApp(App());

class App extends StatelessWidget {
    @override
    build(context) {
        return CubixProvider(
            // build widget from CounterCubix
            // the builder receives BuildContext and Cubix objects
            child: CounterCubix.new.build((context, cubix) {
                return Column(
                    children: [
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
                    ]
                );
            })
        );
    }
}
```

### Auto Sync

```dart
class ACubix extends Cubix<int> {
    ACubix(): super(0);
}

class BCubix extends Cubix<int> {
    ACubix(): super(0);
}

class SumCubix extends Cubix<int> {
    late final ACubix a$;
    late final BCubix b$;

    SumCubix(): super(0);

    @override
    onResolve(context) {
        super.onResolve(context);
        // call enableSync to allow this cubix updates whenever its dependency cubixes are updated
        // if you want to debouce an update, just call enableSync(debounce: Duration(seconds: 1))
        context.enableSync();
        a$ = context.resolve(ACubix.new);
        b$ = context.resolve(BCubix.new);
    }

    @override
    onInit() {
        super.onInit();
        emit(a$.state + b$.state);
    }
}
```

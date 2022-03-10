# Cubix

A enhanced state management of Bloc

## Features

1. State dependencies
2. Auto sync state
3. Async state handling
4. State updating cancellation

## Usages

### Simple Cubix

```dart
// create a cubix
class CounterCubix extends Cubix<int> {
    CounterCubix(): super(0);
    void increment() => emit(state + 1);
    void decrement() => emit(state - 1);
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
                            // incoking cubix method
                            onPressed: cubix.increment,
                            child: const Text('Increment'),
                        ),
                        ElevatedButton(
                            onPressed: cubix.decrement,
                            child: const Text('Decrement'),
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
class CounterCubix extends Cubix<int> {
    CounterCubix(): super(0);
    void increment() => emit(state + 1);
    void decrement() => emit(state - 1);
}

class DoubleCounterCubix extends Cubix<int> {
    late final CounterCubix counterCubix;

    DoubleCounterCubix(): super(0);

    @override
    onCreate(context) {
        super.onResolve(context);
        // call enableSync to allow this cubix updates whenever its dependency cubixes are updated
        // if you want to debouce an update, just call enableSync(debounce: Duration(seconds: 1))
        context.enableSync();
        counterCubix = context.fromCreator(CounterCubix.new);
    }

    @override
    onInit() {
        super.onInit();
        emit(counterCubix.state * 2);
    }
}
```

# Cubix

A predictable state management library that based on BLoc library. Easy to use and maintenance.

## Usages

### Simple Cubix

```dart
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
```

### Referencing other cubixes

```dart
class UserCubix extends Cubix<User> {}

class ArticleListCubix extends Cubix<List<Article>> {
    ArticleListCubix(): super([]);

    @override
    onResolve() async {
        final user$ = resolve(UserCubix.new);
        state = await LoadArticleByUser(user$.state.id);
    };
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
    SumCubix(): super(0);

    @override
    onResolve() {
        final a$ = resolve(ACubix.new);
        final b$ = resolve(BCubix.new);

        // can invoke dependency cubix method
        a$.doSomething();
        b$.doSomething();

        watch([a$, b$], (cancelToken) {
          state = a$.state + b$.state;
        });
    }
}
```

### Listening action dispatching

```dart
abstract class User {}

// define some user types
class AnonymousUser extends User {}

class AuthenticatedUser extends User {
    final Object data;
    const AuthenticatedUser(this.data);
}

// define cubix
class UserCubix extends Cubix<User> {
    // at begining time, cubix has an AnonymousUser state
    UserCubix(): super(AnonymousUser()) {
      // listen logout
      when((action) {
          // when action logout is dispatched
          if (action is LogoutAction) {
              // change current user to anonymous
              state = AnonymousUser();
          }
      });
      dispatch(LoadUserAction());
    }
}

class LoadUserAction extends AsyncAction<void, User> {
    @override
    body() async {
        final userData = await LoadUserData();
        state = AuthenticatedUser(userData);
    }
}

// VoidAction is an no body action
class LogoutAction extends VoidAction<User> {}

```

### Cubix and Action compatible

```dart
class CanStoreAnythingCubix extends Cubix<Object?> {
    CanStoreAnythingCubix(): super(null);
}

class IncrementAction extends SyncAction<void, int> {
    @override
    body() => state++;
}

final cubix = CanStoreAnythingCubix();
// there is no compiler error because ActionState (int) is compatible with CubixState (Object?)
// but you will get runtime exception: Cannot dispatch this action. The Action is not compatible with this Cubix
cubix.dispatch(IncrementAction());
```

### Listen for dispatched action

```dart
class CounterCubix extends Cubix<int> {
    CounterCubix(): super(0);
}
class IncrementAsyncAction extends AsyncAction<void, int> {
    @override
    body() async {
        await Future.delayed(const Duration(seconds: 1));
        state++;
    }
}
final cubix = CounterCubix();
cubix.dispatch(IncrementAsyncAction()..on(
    success: () => print('action dispatches successfully'),
    error: () => print('something went wrong'),
    done: () => print('action dispatched')
));
```

### Watching cubix state changing

There are two ways for watching cubix state changing: in cubix class and in cubix action

```dart
class RootCubix extends VoidCubix {
  RootCubix(): super(0);

  @override
  onResolve() {
    final counter$ = resolve(CounterCubix.new);

    // watch counter cubix's state changing
    final removeWatcher = watch([counter$], (cancelToken) {
      print(counter$.state);
    });
  }
}

class CounterCubix extends Cubix<int> {
  CounterCubix(): super(0);
}

class CounterWatcherAction extends VoidAsyncAction<void> {
  @override
  body() async {
    final counter$ = resolve(CounterCubix.new);

    while(true) {
      // unlikely cubix.watch(), action.watch() returns future object
      await watch([counter$]);
      print(counter$.state);
      // continue watching
    }
  }
}
```

### Understanding Action object

```dart
typedef MyCubixState = int;
typedef MyActionResult = bool;

class MyCubix extends Cubix<MyCubixState> {
  MyCubix(): super(0);
}

class MyAction extends AsyncAction<MyActionResult, MyCubixState> {
  @override
  body() async {
    await Future.delayed(const Duration(seconds: 5));
    return true;
  }
}

// dispatching action
final action = MyAction(); // at this time, the action is not attached, no dispatcher created
final result = cubix.dispatch(action); // the action is attached, the dispatcher is created and working
print(result); // the result is Future<bool> because action is AsyncAction, so the result must be Future type of MyActionResult (bool)
// when action is attached, we can invoke some methods to control action dispatching and access some properties to receive dispatching status
print(action.done); // false
print(action.error); // null
print(action.success); // false
action.cancel(); // cancel action dispatching
print(action.cancelled); // true
// after cancel the action, the result object is running forever
await result;
```

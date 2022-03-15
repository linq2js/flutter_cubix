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
    onResolve(context) async {
        final user$ = context.resolve(UserCubix.new);
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
    onResolve(context) {
        final a$ = context.resolve(ACubix.new);
        final b$ = context.resolve(BCubix.new);

        context.sync([a$, b$], (cancelToken) {
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
      listen((action) {
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

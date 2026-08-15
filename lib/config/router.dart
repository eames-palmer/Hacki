import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hacki/config/constants.dart';
import 'package:hacki/config/locator.dart';
import 'package:hacki/cubits/cubits.dart';
import 'package:hacki/extensions/extensions.dart';
import 'package:hacki/models/item/item.dart';
import 'package:hacki/repositories/hacker_news_repository.dart';
import 'package:hacki/screens/screens.dart';
import 'package:hacki/styles/dimens.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

late final GoRouter router;

GoRouter createRouter() {
  return GoRouter(
    navigatorKey: navigatorKey,
    observers: <NavigatorObserver>[
      locator.get<RouteObserver<ModalRoute<dynamic>>>(),
    ],
    routes: <RouteBase>[
      GoRoute(
        path: '/${ItemScreen.routeName}/${SettingsScreen.routeName}',
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/${ItemScreen.routeName}',
        builder: (BuildContext context, GoRouterState state) {
          final ItemScreenArgs? args = state.extra as ItemScreenArgs?;
          if (args != null) {
            return ItemScreen.phone(args);
          }

          final int? itemId = state.uri.queryParameters['id']?.itemId;
          if (itemId == null) {
            throw GoError("item args or item id can't be null");
          }

          return DeepLinkedItemRoute(itemId: itemId);
        },
      ),
      GoRoute(
        path: HomeScreen.routeName,
        builder: (_, __) => const HomeScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: ShareScreen.routeName,
            builder: (_, GoRouterState state) {
              final ShareScreenArgs? args = state.extra as ShareScreenArgs?;
              if (args == null) {
                throw GoError("args can't be null");
              }
              return ShareScreen(args);
            },
          ),
          GoRoute(
            path: LogsScreen.routeName,
            builder: (_, __) => const LogsScreen(),
          ),
          GoRoute(
            path: WebViewScreen.routeName,
            builder: (_, GoRouterState state) {
              final String? link = state.extra as String?;
              if (link == null) {
                throw GoError("link can't be null");
              }
              return WebViewScreen(url: link);
            },
          ),
          GoRoute(
            path: SubmitScreen.routeName,
            builder: (_, __) => BlocProvider<SubmitCubit>(
              create: (_) => SubmitCubit(),
              child: const SubmitScreen(),
            ),
          ),
          GoRoute(
            path: QrCodeScannerScreen.routeName,
            builder: (_, __) => const QrCodeScannerScreen(),
          ),
          GoRoute(
            path: QrCodeViewScreen.routeName,
            builder: (_, GoRouterState state) {
              final String? data = state.extra as String?;
              if (data == null) {
                throw GoError("data can't be null");
              }
              return QrCodeViewScreen(data: data);
            },
          ),
        ],
      ),
    ],
  );
}

class DeepLinkedItemRoute extends StatefulWidget {
  const DeepLinkedItemRoute({required this.itemId, super.key});

  final int itemId;

  @override
  State<DeepLinkedItemRoute> createState() => _DeepLinkedItemRouteState();
}

class _DeepLinkedItemRouteState extends State<DeepLinkedItemRoute> {
  late Future<Item?> itemFuture;

  @override
  void initState() {
    super.initState();
    itemFuture = _fetchItem();
  }

  @override
  void didUpdateWidget(DeepLinkedItemRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId) {
      itemFuture = _fetchItem();
    }
  }

  Future<Item?> _fetchItem() {
    return locator.get<HackerNewsRepository>().fetchItem(id: widget.itemId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Item?>(
      future: itemFuture,
      builder: (BuildContext context, AsyncSnapshot<Item?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(strokeWidth: Dimens.pt2),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(body: Center(child: Text(Constants.errorMessage)));
        }

        final ItemScreenArgs args = ItemScreenArgs(item: snapshot.data!);
        return ItemScreen.phone(args, showBackButton: true);
      },
    );
  }
}

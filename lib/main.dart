import 'dart:async';
import 'dart:io';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:app_links/app_links.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:equatable/equatable.dart';
import 'package:feature_discovery/feature_discovery.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hacki/blocs/blocs.dart';
import 'package:hacki/config/constants.dart';
import 'package:hacki/config/locator.dart';
import 'package:hacki/config/paths.dart';
import 'package:hacki/config/router.dart';
import 'package:hacki/cubits/cubits.dart';
import 'package:hacki/screens/screens.dart';
import 'package:hacki/screens/widgets/widgets.dart';
import 'package:hacki/services/fetcher.dart';
import 'package:hacki/styles/styles.dart';
import 'package:hacki/utils/utils.dart';
import 'package:hive/hive.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart' show BehaviorSubject;
import 'package:visibility_detector/visibility_detector.dart';
import 'package:workmanager/workmanager.dart';

// For receiving payload event from local notifications.
final BehaviorSubject<String?> selectNotificationSubject =
    BehaviorSubject<String?>();

// For receiving payload event from siri suggestions.
final BehaviorSubject<String?> siriSuggestionSubject =
    BehaviorSubject<String?>();

late final bool isTesting;

void notificationReceiver(NotificationResponse details) =>
    selectNotificationSubject.add(details.payload);

String? _deepLinkLocation(Uri? uri) {
  final String? itemId = uri?.queryParameters['id'];
  if (itemId == null || int.tryParse(itemId) == null) return null;
  return '/item?id=$itemId';
}

Future<void> main({bool testing = false}) async {
  if (kDebugMode) {
    HttpOverrides.global = DebugHttpOverrides();
  }

  WidgetsFlutterBinding.ensureInitialized();

  final AppLinks appLinks = AppLinks();
  final Uri? initialDeepLink = await appLinks.getInitialLink();

  await initializeDateFormatting(Platform.localeName);

  isTesting = testing;

  final Directory tempDir = await getTemporaryDirectory();
  final String tempPath = tempDir.path;
  Hive.init(tempPath);

  final HydratedStorage storage = await HydratedStorage.build(
    storageDirectory: HydratedStorageDirectory(tempPath),
  );
  HydratedBloc.storage = storage;

  await setUpLocator();

  router = createRouter(
    initialLocation: _deepLinkLocation(initialDeepLink) ?? HomeScreen.routeName,
  );

  EquatableConfig.stringify = true;

  FlutterError.onError = (FlutterErrorDetails details) {
    locator.get<Logger>().e(
      details.summary,
      error: details.exceptionAsString(),
      stackTrace: details.stack,
    );
  };

  if (Platform.isIOS) {
    unawaited(Workmanager().initialize(fetcherCallbackDispatcher));

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );
    await flutterLocalNotificationsPlugin.initialize(
      onDidReceiveBackgroundNotificationResponse: notificationReceiver,
      onDidReceiveNotificationResponse: notificationReceiver,
      settings: initializationSettings,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  } else if (Platform.isAndroid) {
    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    final AndroidDeviceInfo androidInfo = await deviceInfoPlugin.androidInfo;
    final int sdk = androidInfo.version.sdkInt;

    if (sdk > 28) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Palette.transparent,
          systemNavigationBarColor: Palette.transparent,
          systemNavigationBarDividerColor: Palette.transparent,
        ),
      );
    }

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: <SystemUiOverlay>[SystemUiOverlay.top],
    );
  }

  final AdaptiveThemeMode? savedThemeMode = await AdaptiveTheme.getThemeMode();

  // Uncomment this line to log events from bloc/cubit.
  // Bloc.observer = CustomBlocObserver();

  VisibilityDetectorController.instance.updateInterval = AppDurations.ms200;

  runApp(
    HackiApp(
      appLinks: appLinks,
      savedThemeMode: savedThemeMode,
      initialDeepLink: initialDeepLink,
    ),
  );
}

class HackiApp extends StatefulWidget {
  const HackiApp({
    required this.appLinks,
    super.key,
    this.savedThemeMode,
    this.initialDeepLink,
  });

  final AdaptiveThemeMode? savedThemeMode;
  final AppLinks appLinks;
  final Uri? initialDeepLink;

  @override
  State<HackiApp> createState() => _HackiAppState();
}

class _HackiAppState extends State<HackiApp> {
  late final StreamSubscription<Uri> _deepLinkSubscription;
  String? _lastDeepLinkLocation;
  bool _deepLinkNavigationPending = false;

  @override
  void initState() {
    super.initState();
    _lastDeepLinkLocation = _deepLinkLocation(widget.initialDeepLink);
    _deepLinkSubscription = widget.appLinks.uriLinkStream.listen(
      _handleDeepLink,
    );
    router.routeInformationProvider.addListener(_handleRouteChanged);
  }

  void _handleDeepLink(Uri uri) {
    locator.get<Logger>().i('deeplink received: ${uri.path}');

    final String? location = _deepLinkLocation(uri);
    if (location == null) return;

    if (location == _lastDeepLinkLocation) return;

    _lastDeepLinkLocation = location;
    _deepLinkNavigationPending = true;
    final String currentLocation = router.routeInformationProvider.value.uri
        .toString();
    if (currentLocation != location) {
      router.go(location);
    } else {
      _deepLinkNavigationPending = false;
    }
  }

  void _handleRouteChanged() {
    final String? deepLinkLocation = _lastDeepLinkLocation;
    if (deepLinkLocation == null) return;

    final String currentLocation = router.routeInformationProvider.value.uri
        .toString();
    if (currentLocation == deepLinkLocation) {
      _deepLinkNavigationPending = false;
    } else if (!_deepLinkNavigationPending) {
      _lastDeepLinkLocation = null;
    }
  }

  @override
  void dispose() {
    _deepLinkSubscription.cancel();
    router.routeInformationProvider.removeListener(_handleRouteChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<RemoteConfigCubit>.value(
          value: locator.get<RemoteConfigCubit>(),
        ),
        BlocProvider<PreferenceCubit>(
          lazy: false,
          create: (BuildContext context) => PreferenceCubit(),
        ),
        BlocProvider<FilterCubit>(
          lazy: false,
          create: (BuildContext context) => FilterCubit(),
        ),
        BlocProvider<HideCubit>(
          create: (BuildContext context) =>
              HideCubit(preferenceCubit: context.read<PreferenceCubit>()),
        ),
        BlocProvider<StoriesBloc>(
          create: (BuildContext context) => StoriesBloc(
            preferenceCubit: context.read<PreferenceCubit>(),
            filterCubit: context.read<FilterCubit>(),
            hideCubit: context.read<HideCubit>(),
          ),
        ),
        BlocProvider<AuthBloc>(
          lazy: false,
          create: (BuildContext context) => AuthBloc(),
        ),
        BlocProvider<HistoryCubit>(
          lazy: false,
          create: (BuildContext context) =>
              HistoryCubit(authBloc: context.read<AuthBloc>()),
        ),
        BlocProvider<FavCubit>(
          lazy: false,
          create: (BuildContext context) =>
              FavCubit(authBloc: context.read<AuthBloc>()),
        ),
        BlocProvider<BlocklistCubit>(
          lazy: false,
          create: (BuildContext context) => BlocklistCubit(),
        ),
        BlocProvider<SearchCubit>(
          lazy: false,
          create: (BuildContext context) => SearchCubit(),
        ),
        BlocProvider<NotificationCubit>(
          lazy: false,
          create: (BuildContext context) => NotificationCubit(
            authBloc: context.read<AuthBloc>(),
            preferenceCubit: context.read<PreferenceCubit>(),
          ),
        ),
        BlocProvider<PinCubit>(
          lazy: false,
          create: (BuildContext context) => PinCubit(),
        ),
        BlocProvider<SplitViewCubit>(
          lazy: false,
          create: (BuildContext context) =>
              SplitViewCubit(preferenceCubit: context.read<PreferenceCubit>()),
        ),
        BlocProvider<ReminderCubit>(
          lazy: false,
          create: (BuildContext context) => ReminderCubit(),
        ),
        BlocProvider<PostCubit>(
          lazy: false,
          create: (BuildContext context) => PostCubit(),
        ),
        BlocProvider<EditCubit>(
          lazy: false,
          create: (BuildContext context) => EditCubit(),
        ),
        BlocProvider<TabCubit>(
          lazy: false,
          create: (BuildContext context) =>
              TabCubit(preferenceCubit: context.read<PreferenceCubit>()),
        ),
        BlocProvider<TipsCubit>(
          lazy: false,
          create: (BuildContext context) => TipsCubit(),
        ),
      ],
      child: BlocConsumer<PreferenceCubit, PreferenceState>(
        listenWhen: (PreferenceState previous, PreferenceState current) =>
            previous.isHapticFeedbackEnabled != current.isHapticFeedbackEnabled,
        listener: (_, PreferenceState state) {
          HapticFeedbackUtils.enabled = state.isHapticFeedbackEnabled;
        },
        buildWhen: (PreferenceState previous, PreferenceState current) =>
            previous.appColor != current.appColor ||
            previous.font != current.font ||
            previous.textScaleFactor != current.textScaleFactor ||
            previous.isTrueDarkModeEnabled != current.isTrueDarkModeEnabled ||
            previous.isDynamicColorEnabled != current.isDynamicColorEnabled ||
            previous.isHackerNewsThemeEnabled !=
                current.isHackerNewsThemeEnabled ||
            previous.isDevModeEnabled != current.isDevModeEnabled,
        builder: (BuildContext context, PreferenceState state) {
          return AdaptiveTheme(
            light: ThemeData(
              primaryColor: state.appColor,
              colorScheme: ColorScheme.fromSwatch(
                primarySwatch: state.appColor,
              ),
              fontFamily: state.font.name,
            ),
            dark: ThemeData(
              brightness: Brightness.dark,
              primaryColor: state.appColor,
              colorScheme: ColorScheme.fromSwatch(
                primarySwatch: state.appColor,
                brightness: Brightness.dark,
              ),
              fontFamily: state.font.name,
            ),
            initial: widget.savedThemeMode ?? AdaptiveThemeMode.system,
            builder: (ThemeData theme, ThemeData darkTheme) {
              return FutureBuilder<AdaptiveThemeMode?>(
                future: AdaptiveTheme.getThemeMode(),
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<AdaptiveThemeMode?> snapshot,
                    ) {
                      final AdaptiveThemeMode? mode = snapshot.data;
                      ThemeUtils.updateStatusBarSetting(
                        SchedulerBinding
                            .instance
                            .platformDispatcher
                            .platformBrightness,
                        mode,
                      );
                      final bool isDarkModeEnabled = () {
                        if (mode == null) {
                          return View.of(
                                context,
                              ).platformDispatcher.platformBrightness ==
                              Brightness.dark;
                        } else {
                          return mode == AdaptiveThemeMode.dark ||
                              (mode == AdaptiveThemeMode.system &&
                                  View.of(
                                        context,
                                      ).platformDispatcher.platformBrightness ==
                                      Brightness.dark);
                        }
                      }();
                      return DynamicColorBuilder(
                        builder:
                            (
                              ColorScheme? lightDynamic,
                              ColorScheme? darkDynamic,
                            ) {
                              final ColorScheme fallbackColorScheme =
                                  ColorScheme.fromSeed(
                                    brightness: isDarkModeEnabled
                                        ? Brightness.dark
                                        : Brightness.light,
                                    seedColor: state.appColor,
                                    dynamicSchemeVariant:
                                        DynamicSchemeVariant.fidelity,
                                  );
                              final ColorScheme colorScheme =
                                  state.isDynamicColorEnabled
                                  ? ((isDarkModeEnabled
                                            ? darkDynamic
                                            : lightDynamic) ??
                                        fallbackColorScheme)
                                  : fallbackColorScheme;
                              return FeatureDiscovery(
                                child: MediaQuery(
                                  data: state.textScaleFactor == 1
                                      ? MediaQuery.of(context)
                                      : MediaQuery.of(context).copyWith(
                                          textScaler: TextScaler.linear(
                                            state.textScaleFactor,
                                          ),
                                        ),
                                  child: MaterialApp.router(
                                    title: 'Hacki',
                                    debugShowCheckedModeBanner: false,
                                    darkTheme: state.isHackerNewsThemeEnabled
                                        ? HackerNewsDarkTheme.theme
                                        : null,
                                    theme: state.isHackerNewsThemeEnabled
                                        ? HackerNewsTheme.theme
                                        : AppTheme.theme(
                                            colorScheme,
                                            state.font,
                                            isDarkModeEnabled:
                                                isDarkModeEnabled,
                                            isTrueDarkModeEnabled:
                                                state.isTrueDarkModeEnabled,
                                          ),
                                    routerConfig: router,
                                    builder: state.isDevModeEnabled
                                        ? (
                                            BuildContext context,
                                            Widget? child,
                                          ) => Stack(
                                            children: <Widget>[
                                              Positioned.fill(child: child!),
                                              DraggableFloatingButton(
                                                onTap: () {
                                                  router.push(
                                                    Paths.logs.landing,
                                                  );
                                                },
                                                child: Icon(
                                                  Icons.bug_report,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onPrimaryContainer,
                                                ),
                                              ),
                                            ],
                                          )
                                        : null,
                                  ),
                                ),
                              );
                            },
                      );
                    },
              );
            },
          );
        },
      ),
    );
  }
}

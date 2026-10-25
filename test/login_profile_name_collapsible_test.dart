import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/models/router.dart' as model;
import 'package:yala/main.dart';
import 'package:yala/screens/login_screen.dart';
import 'package:yala/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final appState = AppState.instance;
    appState.setError(null);
    appState.routerService?.clearAllRoutersInMemory();
  });

  group('LoginScreen Collapsible Profile Name & New Router Selection Tests', () {
    testWidgets(
      'Saved router profile keeps Profile Name collapsed by default, and expands when toggled',
      (WidgetTester tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final appState = container.read(appStateProvider);
        final testRouter = model.Router(
          id: 'router-living-room',
          name: 'Living Room Router',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'secretPassword123',
          useHttps: false,
        );
        appState.routerService?.updateRouterInMemory(testRouter);

        tester.view.physicalSize = const Size(800, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: LoginScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. Saved profile is selected by default
        final livingRoomChip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Living Room Router'),
        );
        expect(livingRoomChip.selected, isTrue);

        // 2. Profile Name field should stay COLLAPSED by default for saved profiles
        final crossFade = tester.widget<AnimatedCrossFade>(
          find.byType(AnimatedCrossFade),
        );
        expect(crossFade.crossFadeState, equals(CrossFadeState.showFirst));

        // 3. Collapsed toggle bar displays nickname preview
        expect(
          find.byKey(const ValueKey('login_profile_name_toggle')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Living Room Router'),
          findsAtLeastNWidgets(1),
        );

        // 4. Tap toggle bar to expand
        await tester.tap(
          find.byKey(const ValueKey('login_profile_name_toggle')),
        );
        await tester.pumpAndSettle();

        final crossFadeExpanded = tester.widget<AnimatedCrossFade>(
          find.byType(AnimatedCrossFade),
        );
        expect(
          crossFadeExpanded.crossFadeState,
          equals(CrossFadeState.showSecond),
        );
        expect(
          find.byKey(const ValueKey('login_profile_name_collapse_btn')),
          findsOneWidget,
        );

        // Verify no overlap: TARGET ROUTER ENDPOINT bottom vs Profile Name field top has clear margin >= 16px
        final targetEndpointBottom = tester
            .getBottomLeft(find.text('TARGET ROUTER ENDPOINT'))
            .dy;
        final profileNameTop = tester
            .getTopLeft(find.byKey(const ValueKey('login_profile_name_field')))
            .dy;
        expect(
          profileNameTop - targetEndpointBottom,
          greaterThanOrEqualTo(16.0),
        );

        // 5. Tap collapse button to collapse again
        await tester.tap(
          find.byKey(const ValueKey('login_profile_name_collapse_btn')),
        );
        await tester.pumpAndSettle();

        final crossFadeCollapsedAgain = tester.widget<AnimatedCrossFade>(
          find.byType(AnimatedCrossFade),
        );
        expect(
          crossFadeCollapsedAgain.crossFadeState,
          equals(CrossFadeState.showFirst),
        );
      },
    );

    testWidgets(
      'Clicking New Router unselects saved profile, clears password & name, prefills root & IP, and expands Profile Name',
      (WidgetTester tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final appState = container.read(appStateProvider);
        final testRouter = model.Router(
          id: 'router-existing',
          name: 'Home Gateway',
          ipAddress: '192.168.1.1',
          username: 'admin',
          password: 'savedPassword999',
          useHttps: false,
        );
        appState.routerService?.updateRouterInMemory(testRouter);

        tester.view.physicalSize = const Size(800, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: LoginScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify initially Home Gateway is selected and Profile Name is collapsed
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, 'Home Gateway'),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
              .crossFadeState,
          equals(CrossFadeState.showFirst),
        );

        // Click "+ New Router" ActionChip
        await tester.tap(find.byKey(const ValueKey('login_new_router_chip')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 1. Existing saved profile must be UNSELECTED
        final homeGatewayChip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Home Gateway'),
        );
        expect(homeGatewayChip.selected, isFalse);

        // 2. Profile Name field must EXPAND automatically
        final crossFade = tester.widget<AnimatedCrossFade>(
          find.byType(AnimatedCrossFade),
        );
        expect(crossFade.crossFadeState, equals(CrossFadeState.showSecond));

        // 3. Form fields state:
        // - Profile Name must be cleared
        final profileNameField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('login_profile_name_field')),
        );
        expect(profileNameField.controller?.text, isEmpty);

        // - Password must be cleared
        final passField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('login_pass_field')),
        );
        expect(passField.controller?.text, isEmpty);

        // - Username must be prefilled as 'root'
        final userField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('login_user_field')),
        );
        expect(userField.controller?.text, equals('root'));

        // 4. Auto-matching same IP address (192.168.1.1) must NOT hijack or re-select existing saved profile
        final ipField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('login_ip_field')),
        );
        ipField.controller?.text = '192.168.1.1';
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Even though IP matches testRouter (192.168.1.1), Home Gateway remains unselected
        final settledChip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Home Gateway'),
        );
        expect(settledChip.selected, isFalse);
        expect(profileNameField.controller?.text, isEmpty);
        expect(crossFade.crossFadeState, equals(CrossFadeState.showSecond));

        // 5. Clicking back on Home Gateway ChoiceChip reselects it and collapses Profile Name
        await tester.tap(find.widgetWithText(ChoiceChip, 'Home Gateway'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, 'Home Gateway'),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
              .crossFadeState,
          equals(CrossFadeState.showFirst),
        );
        expect(passField.controller?.text, equals('savedPassword999'));
        expect(profileNameField.controller?.text, equals('Home Gateway'));
      },
    );

    testWidgets(
      'LoginScreen initializes with Profile Name expanded when no routers are saved',
      (WidgetTester tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        tester.view.physicalSize = const Size(800, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: LoginScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Since no routers exist, it is in New Router mode and Profile Name expands automatically
        final crossFade = tester.widget<AnimatedCrossFade>(
          find.byType(AnimatedCrossFade),
        );
        expect(crossFade.crossFadeState, equals(CrossFadeState.showSecond));
      },
    );
  });
}

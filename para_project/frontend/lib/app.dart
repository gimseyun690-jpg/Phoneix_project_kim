import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/flight_record_manager.dart';
import 'core/theme.dart';
import 'models/app_models.dart';
import 'repositories/api_app_repository.dart';
import 'repositories/app_repository.dart';
import 'repositories/mock_app_repository.dart';
import 'screens/flight_record_detail_screen.dart';
import 'screens/flight_records_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notice_detail_screen.dart';
import 'screens/notices_screen.dart';
import 'screens/site_detail_screen.dart';
import 'screens/site_list_screen.dart';
import 'screens/training_logs_screen.dart';

class AppRoutes {
  static const siteDetail = '/site-detail';
  static const noticeDetail = '/notice-detail';
  static const flightRecordDetail = '/flight-record-detail';
}

class SiteDetailArgs {
  const SiteDetailArgs({required this.siteId, required this.pilotLevel});

  final int siteId;
  final PilotLevel pilotLevel;
}

class NoticeDetailArgs {
  const NoticeDetailArgs({required this.noticeId});

  final int noticeId;
}

class FlightRecordDetailArgs {
  const FlightRecordDetailArgs({required this.sessionId});

  final String sessionId;
}

class ParaglidingApp extends StatefulWidget {
  const ParaglidingApp({super.key});

  @override
  State<ParaglidingApp> createState() => _ParaglidingAppState();
}

class _ParaglidingAppState extends State<ParaglidingApp> {
  late final AppRepository _repository = AppConfig.useMockApi
      ? MockAppRepository()
      : ApiAppRepository(baseUrl: AppConfig.apiBaseUrl);

  AppUser? _currentUser;
  FlightRecordManager? _flightRecordManager;

  void _handleLogin(AppUser user) {
    _flightRecordManager?.dispose();
    final manager = FlightRecordManager();
    manager.initialize(userId: user.id);
    setState(() {
      _currentUser = user;
      _flightRecordManager = manager;
    });
  }

  void _handleLogout() {
    _flightRecordManager?.dispose();
    setState(() {
      _currentUser = null;
      _flightRecordManager = null;
    });
  }

  @override
  void dispose() {
    _flightRecordManager?.dispose();
    super.dispose();
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.siteDetail:
        final args = settings.arguments! as SiteDetailArgs;
        return MaterialPageRoute<void>(
          builder: (_) => SiteDetailScreen(
            repository: _repository,
            siteId: args.siteId,
            pilotLevel: args.pilotLevel,
          ),
        );
      case AppRoutes.noticeDetail:
        final args = settings.arguments! as NoticeDetailArgs;
        return MaterialPageRoute<void>(
          builder: (_) => NoticeDetailScreen(
            repository: _repository,
            noticeId: args.noticeId,
          ),
        );
      case AppRoutes.flightRecordDetail:
        final args = settings.arguments! as FlightRecordDetailArgs;
        final manager = _flightRecordManager;
        if (manager == null) {
          return null;
        }
        return MaterialPageRoute<void>(
          builder: (_) => FlightRecordDetailScreen(
            flightRecordManager: manager,
            sessionId: args.sessionId,
          ),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '패러글라이딩 브리핑',
      theme: buildAppTheme(),
      onGenerateRoute: _onGenerateRoute,
      home: _currentUser == null || _flightRecordManager == null
          ? LoginScreen(
              repository: _repository,
              onLoggedIn: _handleLogin,
            )
          : AppShell(
              repository: _repository,
              user: _currentUser!,
              flightRecordManager: _flightRecordManager!,
              onLogout: _handleLogout,
            ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.repository,
    required this.user,
    required this.flightRecordManager,
    required this.onLogout,
  });

  final AppRepository repository;
  final AppUser user;
  final FlightRecordManager flightRecordManager;
  final VoidCallback onLogout;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.flightRecordManager,
      builder: (context, _) {
        final pages = [
          HomeScreen(
            repository: widget.repository,
            user: widget.user,
            flightRecordManager: widget.flightRecordManager,
            onOpenFlightRecorder: () {
              setState(() {
                _selectedIndex = 2;
              });
            },
          ),
          SiteListScreen(repository: widget.repository, user: widget.user),
          FlightRecordsScreen(
            repository: widget.repository,
            user: widget.user,
            flightRecordManager: widget.flightRecordManager,
          ),
          TrainingLogsScreen(repository: widget.repository, user: widget.user),
          NoticesScreen(repository: widget.repository),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(
              switch (_selectedIndex) {
                0 => '패러글라이딩 브리핑',
                1 => '사이트 목록',
                2 => '비행 기록',
                3 => '훈련 기록',
                _ => '공지',
              },
            ),
            actions: [
              if (widget.flightRecordManager.isRecording)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE4DE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fiber_manual_record,
                          size: 12, color: Color(0xFFE76F51)),
                      SizedBox(width: 6),
                      Text('기록 중'),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Text(
                    '${widget.user.fullName} | ${widget.user.pilotLevel.label}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout),
                tooltip: '로그아웃',
              ),
            ],
          ),
          body: pages[_selectedIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined), label: '홈'),
              NavigationDestination(
                  icon: Icon(Icons.landscape_outlined), label: '사이트'),
              NavigationDestination(
                  icon: Icon(Icons.play_circle_outline), label: '비행'),
              NavigationDestination(
                  icon: Icon(Icons.checklist_outlined), label: '훈련'),
              NavigationDestination(
                  icon: Icon(Icons.campaign_outlined), label: '공지'),
            ],
          ),
        );
      },
    );
  }
}

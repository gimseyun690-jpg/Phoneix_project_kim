import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/community_manager.dart';
import 'core/flight_record_manager.dart';
import 'core/kmz_site_catalog.dart';
import 'core/theme.dart';
import 'models/app_models.dart';
import 'repositories/api_app_repository.dart';
import 'repositories/app_repository.dart';
import 'repositories/mock_app_repository.dart';
import 'screens/community_hub_screen.dart';
import 'screens/community_post_detail_screen.dart';
import 'screens/flight_journal_composer_screen.dart';
import 'screens/flight_record_detail_screen.dart';
import 'screens/flight_records_screen.dart';
import 'screens/home_screen.dart';
import 'screens/korea_maps_screen.dart';
import 'screens/live_flight_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notice_detail_screen.dart';
import 'screens/site_community_screen.dart';
import 'screens/site_detail_screen.dart';
import 'screens/training_logs_screen.dart';
import 'widgets/app_logo.dart';

class AppRoutes {
  static const siteDetail = '/site-detail';
  static const noticeDetail = '/notice-detail';
  static const flightRecordDetail = '/flight-record-detail';
  static const liveFlight = '/live-flight';
  static const flightJournalComposer = '/flight-journal-composer';
  static const communityPostDetail = '/community-post-detail';
  static const siteCommunity = '/site-community';
}

class SiteDetailArgs {
  const SiteDetailArgs({
    this.siteId,
    this.importedSite,
    required this.pilotLevel,
  }) : assert(siteId != null || importedSite != null);

  final int? siteId;
  final ImportedParaglidingSite? importedSite;
  final PilotLevel pilotLevel;
}

class MapSiteSelection {
  const MapSiteSelection.registered(this.siteId) : importedSiteSourceId = null;

  const MapSiteSelection.imported(this.importedSiteSourceId) : siteId = null;

  final int? siteId;
  final String? importedSiteSourceId;

  bool get isRegistered => siteId != null;

  bool get isImported => importedSiteSourceId != null;

  bool matchesRegistered(int candidateSiteId) => siteId == candidateSiteId;

  bool matchesImported(String candidateSourceId) =>
      importedSiteSourceId == candidateSourceId;
}

class NoticeDetailArgs {
  const NoticeDetailArgs({required this.noticeId});

  final int noticeId;
}

class FlightRecordDetailArgs {
  const FlightRecordDetailArgs({required this.sessionId});

  final String sessionId;
}

class FlightJournalComposerArgs {
  const FlightJournalComposerArgs({required this.sessionId});

  final String sessionId;
}

class CommunityPostDetailArgs {
  const CommunityPostDetailArgs({required this.postId});

  final String postId;
}

class SiteCommunityArgs {
  const SiteCommunityArgs({
    required this.siteName,
    this.siteId,
  });

  final int? siteId;
  final String siteName;
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
  CommunityManager? _communityManager;

  void _handleLogin(AppUser user) {
    _flightRecordManager?.dispose();
    _communityManager?.dispose();
    final flightRecordManager = FlightRecordManager();
    flightRecordManager.initialize(userId: user.id);
    final communityManager = CommunityManager();
    communityManager.initialize(user: user);
    setState(() {
      _currentUser = user;
      _flightRecordManager = flightRecordManager;
      _communityManager = communityManager;
    });
  }

  void _handleLogout() {
    _flightRecordManager?.dispose();
    _communityManager?.dispose();
    setState(() {
      _currentUser = null;
      _flightRecordManager = null;
      _communityManager = null;
    });
  }

  @override
  void dispose() {
    _flightRecordManager?.dispose();
    _communityManager?.dispose();
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
            importedSite: args.importedSite,
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
        final flightRecordManager = _flightRecordManager;
        final communityManager = _communityManager;
        final user = _currentUser;
        if (flightRecordManager == null ||
            communityManager == null ||
            user == null) {
          return null;
        }
        return PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, animation, __) => FlightRecordDetailScreen(
            flightRecordManager: flightRecordManager,
            communityManager: communityManager,
            repository: _repository,
            user: user,
            pilotLevel: user.pilotLevel,
            sessionId: args.sessionId,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
      case AppRoutes.liveFlight:
        final flightRecordManager = _flightRecordManager;
        final communityManager = _communityManager;
        final user = _currentUser;
        if (flightRecordManager == null ||
            communityManager == null ||
            user == null) {
          return null;
        }
        return PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, animation, __) => LiveFlightScreen(
            repository: _repository,
            user: user,
            flightRecordManager: flightRecordManager,
            communityManager: communityManager,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
      case AppRoutes.flightJournalComposer:
        final args = settings.arguments! as FlightJournalComposerArgs;
        final flightRecordManager = _flightRecordManager;
        final communityManager = _communityManager;
        final user = _currentUser;
        if (flightRecordManager == null ||
            communityManager == null ||
            user == null) {
          return null;
        }
        return MaterialPageRoute<void>(
          builder: (_) => FlightJournalComposerScreen(
            repository: _repository,
            user: user,
            flightRecordManager: flightRecordManager,
            communityManager: communityManager,
            sessionId: args.sessionId,
          ),
        );
      case AppRoutes.communityPostDetail:
        final args = settings.arguments! as CommunityPostDetailArgs;
        final flightRecordManager = _flightRecordManager;
        final communityManager = _communityManager;
        if (flightRecordManager == null || communityManager == null) {
          return null;
        }
        return MaterialPageRoute<void>(
          builder: (_) => CommunityPostDetailScreen(
            communityManager: communityManager,
            flightRecordManager: flightRecordManager,
            postId: args.postId,
          ),
        );
      case AppRoutes.siteCommunity:
        final args = settings.arguments! as SiteCommunityArgs;
        final flightRecordManager = _flightRecordManager;
        final communityManager = _communityManager;
        final user = _currentUser;
        if (flightRecordManager == null ||
            communityManager == null ||
            user == null) {
          return null;
        }
        return MaterialPageRoute<void>(
          builder: (_) => SiteCommunityScreen(
            repository: _repository,
            user: user,
            communityManager: communityManager,
            flightRecordManager: flightRecordManager,
            siteId: args.siteId,
            siteName: args.siteName,
          ),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '패러글라이딩 브리지',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      onGenerateRoute: _onGenerateRoute,
      home: _currentUser == null ||
              _flightRecordManager == null ||
              _communityManager == null
          ? LoginScreen(
              repository: _repository,
              onLoggedIn: _handleLogin,
            )
          : AppShell(
              repository: _repository,
              user: _currentUser!,
              flightRecordManager: _flightRecordManager!,
              communityManager: _communityManager!,
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
    required this.communityManager,
    required this.onLogout,
  });

  final AppRepository repository;
  final AppUser user;
  final FlightRecordManager flightRecordManager;
  final CommunityManager communityManager;
  final VoidCallback onLogout;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  void _openFlightTabOrLive() {
    if (widget.flightRecordManager.isRecording) {
      Navigator.pushNamed(context, AppRoutes.liveFlight);
      return;
    }
    setState(() {
      _selectedIndex = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
        [widget.flightRecordManager, widget.communityManager],
      ),
      builder: (context, _) {
        final pages = [
          HomeScreen(
            repository: widget.repository,
            user: widget.user,
            flightRecordManager: widget.flightRecordManager,
            onOpenFlightRecorder: _openFlightTabOrLive,
          ),
          KoreaMapsScreen(
            repository: widget.repository,
            user: widget.user,
          ),
          FlightRecordsScreen(
            repository: widget.repository,
            user: widget.user,
            flightRecordManager: widget.flightRecordManager,
            communityManager: widget.communityManager,
          ),
          TrainingLogsScreen(repository: widget.repository, user: widget.user),
          CommunityHubScreen(
            repository: widget.repository,
            user: widget.user,
            flightRecordManager: widget.flightRecordManager,
            communityManager: widget.communityManager,
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            leading: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Center(child: AppLogo(size: 28)),
            ),
            leadingWidth: 52,
            title: Text(
              switch (_selectedIndex) {
                0 => '패러글라이딩 브리지',
                1 => '지도',
                2 => '비행 기록',
                3 => '훈련 기록',
                _ => '커뮤니티',
              },
            ),
            actions: [
              if (widget.flightRecordManager.isRecording)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.liveFlight,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE4DE),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.fiber_manual_record,
                            size: 12,
                            color: Color(0xFFE76F51),
                          ),
                          SizedBox(width: 6),
                          Text('실시간 기록'),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Text(
                    '${widget.user.fullName} · ${widget.user.pilotLevel.label}',
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
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: '홈',
              ),
              NavigationDestination(
                icon: Icon(Icons.landscape_outlined),
                label: '지도',
              ),
              NavigationDestination(
                icon: Icon(Icons.play_circle_outline),
                label: '비행',
              ),
              NavigationDestination(
                icon: Icon(Icons.checklist_outlined),
                label: '훈련',
              ),
              NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                label: '커뮤니티',
              ),
            ],
          ),
        );
      },
    );
  }
}

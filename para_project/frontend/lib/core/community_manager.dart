import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';

class CommunityStore {
  static const _postsKey = 'community_posts_v1';
  static const _commentsKey = 'community_comments_v1';

  SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async {
    _preferences ??= await SharedPreferences.getInstance();
    return _preferences!;
  }

  Future<List<FlightJournalPost>> loadPosts() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_postsKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => FlightJournalPost.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> savePosts(List<FlightJournalPost> posts) async {
    final prefs = await _prefs();
    await prefs.setString(
      _postsKey,
      jsonEncode(posts.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<PostComment>> loadComments() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_commentsKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => PostComment.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> saveComments(List<PostComment> comments) async {
    final prefs = await _prefs();
    await prefs.setString(
      _commentsKey,
      jsonEncode(comments.map((item) => item.toJson()).toList()),
    );
  }
}

class CommunityManager extends ChangeNotifier {
  CommunityManager({CommunityStore? store})
      : _store = store ?? CommunityStore();

  final CommunityStore _store;

  bool _initialized = false;
  bool _loading = false;
  bool _working = false;
  AppUser? _currentUser;
  String? _errorMessage;
  String? _statusMessage;
  List<FlightJournalPost> _posts = [];
  List<PostComment> _comments = [];

  bool get isLoading => _loading;
  bool get isWorking => _working;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;
  AppUser? get currentUser => _currentUser;
  List<FlightJournalPost> get posts => List.unmodifiable(_posts);

  Future<void> initialize({required AppUser user}) async {
    if (_initialized && _currentUser?.id == user.id) {
      return;
    }

    _loading = true;
    _currentUser = user;
    _errorMessage = null;
    notifyListeners();

    try {
      final loadedPosts = await _store.loadPosts();
      final loadedComments = await _store.loadComments();
      _posts = List<FlightJournalPost>.from(loadedPosts)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _comments = List<PostComment>.from(loadedComments)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _initialized = true;
    } catch (_) {
      _errorMessage = '커뮤니티 글을 불러오지 못했습니다.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clearMessages() {
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();
  }

  FlightJournalPost? getPost(String postId) {
    for (final post in _posts) {
      if (post.id == postId) {
        return post;
      }
    }
    return null;
  }

  FlightJournalPost? findPostBySessionId(String sessionId) {
    final currentUserId = _currentUser?.id;
    if (currentUserId == null) {
      return null;
    }

    for (final post in _posts) {
      if (post.userId == currentUserId && post.flightSessionId == sessionId) {
        return post;
      }
    }
    return null;
  }

  List<PostComment> commentsForPost(String postId) {
    return _comments
        .where((item) => item.postId == postId)
        .toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<FlightJournalPost> siteFeedPosts({
    int? siteId,
    String? siteName,
    bool includePrivateMine = false,
  }) {
    final currentUserId = _currentUser?.id;
    final normalizedSiteName = siteName?.trim().toLowerCase();

    return _posts.where((post) {
      final isMine = currentUserId != null && post.userId == currentUserId;
      if (post.visibility == CommunityVisibility.private &&
          !(includePrivateMine && isMine)) {
        return false;
      }
      if (siteId != null && post.siteId == siteId) {
        return true;
      }
      if (normalizedSiteName != null &&
          normalizedSiteName.isNotEmpty &&
          post.siteName.trim().toLowerCase() == normalizedSiteName) {
        return true;
      }
      return siteId == null &&
          (normalizedSiteName == null || normalizedSiteName.isEmpty);
    }).toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  int siteFeedCount({
    int? siteId,
    String? siteName,
    bool includePrivateMine = false,
  }) {
    return siteFeedPosts(
      siteId: siteId,
      siteName: siteName,
      includePrivateMine: includePrivateMine,
    ).length;
  }

  Future<FlightJournalPost?> saveJournal(FlightJournalDraft draft) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      _errorMessage = '커뮤니티를 사용하려면 다시 로그인해 주세요.';
      notifyListeners();
      return null;
    }

    _working = true;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final existing = draft.postId == null
          ? findPostBySessionId(draft.flightSessionId ?? '')
          : getPost(draft.postId!);

      final post = (existing ?? _buildNewPost(draft, now)).copyWith(
        userId: draft.userId,
        authorName: draft.authorName,
        flightSessionId: draft.flightSessionId,
        siteId: draft.siteId,
        siteName: draft.siteName,
        siteRegion: draft.siteRegion,
        title: draft.title.trim(),
        body: draft.body.trim(),
        questionText: draft.questionText.trim(),
        visibility: draft.visibility,
        flightDate: draft.flightDate,
        flightStartedAt: draft.flightStartedAt,
        flightEndedAt: draft.flightEndedAt,
        durationSeconds: draft.durationSeconds,
        totalDistanceMeters: draft.totalDistanceMeters,
        maxAltitudeMeters: draft.maxAltitudeMeters,
        weatherSummary: draft.weatherSummary.trim(),
        flyabilitySummary: draft.flyabilitySummary.trim(),
        summaryText: draft.summaryText.trim(),
        media: draft.media,
        updatedAt: now,
      );

      _posts = [
        post,
        ..._posts.where((item) => item.id != post.id),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _store.savePosts(_posts);
      _statusMessage = post.visibility == CommunityVisibility.private
          ? '비행일지를 나만 보기로 저장했습니다.'
          : '비행일지를 커뮤니티에 게시했습니다.';
      return post;
    } catch (_) {
      _errorMessage = '비행일지를 저장하지 못했습니다.';
      return null;
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  Future<bool> toggleLike(String postId) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      _errorMessage = '좋아요를 남기려면 다시 로그인해 주세요.';
      notifyListeners();
      return false;
    }

    final post = getPost(postId);
    if (post == null) {
      _errorMessage = '게시글을 찾지 못했습니다.';
      notifyListeners();
      return false;
    }

    try {
      final nextLiked = List<int>.from(post.likedUserIds);
      if (nextLiked.contains(currentUser.id)) {
        nextLiked.remove(currentUser.id);
      } else {
        nextLiked.add(currentUser.id);
      }
      final updated = post.copyWith(
        likedUserIds: nextLiked,
        updatedAt: DateTime.now(),
      );
      _posts = [
        updated,
        ..._posts.where((item) => item.id != updated.id),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _store.savePosts(_posts);
      notifyListeners();
      return true;
    } catch (_) {
      _errorMessage = '좋아요를 반영하지 못했습니다.';
      notifyListeners();
      return false;
    }
  }

  Future<PostComment?> addComment({
    required String postId,
    required String body,
    bool isFeedback = false,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      _errorMessage = '댓글을 남기려면 다시 로그인해 주세요.';
      notifyListeners();
      return null;
    }

    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      _errorMessage = '댓글 내용을 입력해 주세요.';
      notifyListeners();
      return null;
    }

    final post = getPost(postId);
    if (post == null) {
      _errorMessage = '댓글을 남길 게시글을 찾지 못했습니다.';
      notifyListeners();
      return null;
    }

    _working = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final comment = PostComment(
        id: 'comment_${now.microsecondsSinceEpoch}',
        postId: postId,
        userId: currentUser.id,
        authorName: currentUser.fullName,
        body: trimmed,
        createdAt: now,
        isFeedback: isFeedback,
      );
      _comments = [..._comments, comment]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final updatedPost = post.copyWith(
        commentCount: post.commentCount + 1,
        updatedAt: now,
      );
      _posts = [
        updatedPost,
        ..._posts.where((item) => item.id != updatedPost.id),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _store.saveComments(_comments);
      await _store.savePosts(_posts);
      _statusMessage = isFeedback ? '참고 피드백을 남겼습니다.' : '댓글을 남겼습니다.';
      return comment;
    } catch (_) {
      _errorMessage = '댓글을 저장하지 못했습니다.';
      return null;
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  FlightJournalPost _buildNewPost(FlightJournalDraft draft, DateTime now) {
    return FlightJournalPost(
      id: 'journal_${now.microsecondsSinceEpoch}',
      userId: draft.userId,
      authorName: draft.authorName,
      flightSessionId: draft.flightSessionId,
      siteId: draft.siteId,
      siteName: draft.siteName,
      siteRegion: draft.siteRegion,
      title: draft.title.trim(),
      body: draft.body.trim(),
      questionText: draft.questionText.trim(),
      visibility: draft.visibility,
      flightDate: draft.flightDate,
      flightStartedAt: draft.flightStartedAt,
      flightEndedAt: draft.flightEndedAt,
      durationSeconds: draft.durationSeconds,
      totalDistanceMeters: draft.totalDistanceMeters,
      maxAltitudeMeters: draft.maxAltitudeMeters,
      weatherSummary: draft.weatherSummary.trim(),
      flyabilitySummary: draft.flyabilitySummary.trim(),
      summaryText: draft.summaryText.trim(),
      likedUserIds: const [],
      commentCount: 0,
      media: draft.media,
      createdAt: now,
      updatedAt: now,
    );
  }
}

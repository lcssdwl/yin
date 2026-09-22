import '../../config/api_config.dart';
import '../../config/constants.dart';
import '../../core/network/dio_client.dart';
import '../models/comment.dart';

/// 评论仓储
/// list 🟢 公开;add / like 🔴 需登录
class CommentRepository {
  final DioClient _client = DioClient.instance;

  /// 评论列表
  Future<List<CommentModel>> getList(
    int targetId, {
    int targetType = 1,
    int page = 1,
    String sort = 'hot',
  }) async {
    final data = await _client.get(Api.commentList, query: {
      'target_id': targetId,
      'target_type': targetType,
      'page': page,
      'limit': AppConstants.pageSize,
      'sort': sort,
    });
    final list = (data as Map)['list'];
    if (list is! List) return [];
    return list
        .map((e) => CommentModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 发表评论(🔴)
  Future<CommentModel> add(
    int targetId,
    String content, {
    int targetType = 1,
    int parentId = 0,
  }) async {
    final data = await _client.post(Api.commentAdd, data: {
      'target_id': targetId,
      'target_type': targetType,
      'content': content,
      'parent_id': parentId,
    });
    return CommentModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// 点赞 / 取消点赞(🔴)
  Future<bool> like(int commentId) async {
    final data = await _client.post(Api.commentLike, data: {
      'comment_id': commentId,
    });
    final map = Map<String, dynamic>.from(data as Map);
    return map['is_liked'] == true;
  }
}

import '../../core/utils/json_util.dart';

/// 评论回复
class CommentReply {
  final int id;
  final int userId;
  final String nickname;
  final String content;
  final String createTime;

  CommentReply({
    required this.id,
    this.userId = 0,
    this.nickname = '',
    this.content = '',
    this.createTime = '',
  });

  factory CommentReply.fromJson(Map<String, dynamic> json) => CommentReply(
        id: JsonUtil.toInt(json['id']),
        userId: JsonUtil.toInt(json['user_id']),
        nickname: JsonUtil.toStr(json['nickname']),
        content: JsonUtil.toStr(json['content']),
        createTime: JsonUtil.toStr(json['create_time']),
      );
}

/// 评论模型
class CommentModel {
  final int id;
  final int userId;
  final String nickname;
  final String avatar;
  final String content;
  final int likeCount;
  final int replyCount;
  final String createTime;
  final bool isLiked;
  final List<CommentReply> replies;

  CommentModel({
    required this.id,
    this.userId = 0,
    this.nickname = '',
    this.avatar = '',
    this.content = '',
    this.likeCount = 0,
    this.replyCount = 0,
    this.createTime = '',
    this.isLiked = false,
    this.replies = const [],
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    final rs = json['replies'];
    return CommentModel(
      id: JsonUtil.toInt(json['id']),
      userId: JsonUtil.toInt(json['user_id']),
      nickname: JsonUtil.toStr(json['nickname']),
      avatar: JsonUtil.toStr(json['avatar']),
      content: JsonUtil.toStr(json['content']),
      likeCount: JsonUtil.toInt(json['like_count']),
      replyCount: JsonUtil.toInt(json['reply_count']),
      createTime: JsonUtil.toStr(json['create_time']),
      isLiked: JsonUtil.toBool(json['is_liked']),
      replies: rs is List
          ? rs
              .map((e) =>
                  CommentReply.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : const [],
    );
  }

  CommentModel copyWith({
    int? id,
    int? userId,
    String? nickname,
    String? avatar,
    String? content,
    int? likeCount,
    int? replyCount,
    String? createTime,
    bool? isLiked,
    List<CommentReply>? replies,
  }) =>
      CommentModel(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        nickname: nickname ?? this.nickname,
        avatar: avatar ?? this.avatar,
        content: content ?? this.content,
        likeCount: likeCount ?? this.likeCount,
        replyCount: replyCount ?? this.replyCount,
        createTime: createTime ?? this.createTime,
        isLiked: isLiked ?? this.isLiked,
        replies: replies ?? this.replies,
      );
}

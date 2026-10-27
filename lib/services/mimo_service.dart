import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// 小米 MiMo 云端接口封装：语音识别 + 文本对话。
// API Key 只保存在手机本地（StorageService），不再下发到设备。
class MimoException implements Exception {
  final String message;
  MimoException(this.message);
  @override
  String toString() => message;
}

class MimoService {
  static const String _endpoint =
      'https://api.xiaomimimo.com/v1/chat/completions';
  static const String _asrModel = 'mimo-v2.5-asr';
  static const String _chatModel = 'mimo-v2.6-flash';

  // 回复要短：设备屏幕只有几行，且蓝牙单包回传上限约 400 字节
  static const String _systemPrompt =
      '你是情侣对佩设备里的语音伙伴，语气温暖俏皮。'
      '用用户所用的语言回答，最多 40 个字，口语化，不要表情符号和 Markdown。';

  // 语音识别：把整段 WAV 以 base64 内嵌到 input_audio 里。
  // 返回识别出的文本（可能为空串，表示没听清）。
  static Future<String> transcribe({
    required String apiKey,
    required Uint8List wav,
  }) async {
    final body = jsonEncode({
      'model': _asrModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_audio',
              'input_audio': {
                'data': base64Encode(wav),
                'format': 'wav',
              },
            }
          ]
        }
      ],
    });
    return _post(apiKey, body, label: '语音识别');
  }

  // 文本对话：把识别结果交给大模型，返回回复文本。
  static Future<String> chat({
    required String apiKey,
    required String userText,
  }) async {
    final body = jsonEncode({
      'model': _chatModel,
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': userText},
      ],
      'max_completion_tokens': 128,
      'stream': false,
      'thinking': {'type': 'disabled'},
    });
    return _post(apiKey, body, label: '对话请求');
  }

  static Future<String> _post(String apiKey, String body,
      {required String label}) async {
    if (apiKey.isEmpty) {
      throw MimoException('请先在“AI 服务”里填写 MiMo API Key');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request =
          await client.postUrl(Uri.parse(_endpoint)).timeout(
        const Duration(seconds: 20),
      );
      request.headers
        ..set('api-key', apiKey)
        ..set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(body);

      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw MimoException('$label失败（HTTP ${response.statusCode}）');
      }

      final decoded = jsonDecode(text);
      if (decoded is! Map) throw MimoException('$label返回格式异常');
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        throw MimoException('$label返回为空');
      }
      final message = (choices.first as Map)['message'];
      final content = message is Map ? message['content'] : null;
      if (content is! String) throw MimoException('$label返回缺少文本');
      return content.trim();
    } on MimoException {
      rethrow;
    } on SocketException {
      throw MimoException('$label网络不可用，请检查手机网络');
    } on TimeoutException {
      throw MimoException('$label超时，请稍后再试');
    } catch (e) {
      throw MimoException('$label失败：$e');
    } finally {
      client.close(force: true);
    }
  }
}

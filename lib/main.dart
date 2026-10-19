// =====================================================================
//  LMClient v2 — Universal AI API Client (multi-file via part of)
//  Dependencies: نفس الحزم الموجودة أصلاً في pubspec.yaml (لا حزم جديدة)
//    flutter_riverpod, dio, file_picker, flutter_markdown, speech_to_text,
//    flutter_tts, uuid, shared_preferences, permission_handler, path_provider
// =====================================================================
// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, unused_local_variable, avoid_print, deprecated_member_use, use_build_context_synchronously, prefer_const_constructors, prefer_const_literals_to_create_immutables, depend_on_referenced_packages, prefer_interpolation_to_compose_strings, unnecessary_brace_in_string_interps, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

part 'core.dart';
part 'models.dart';
part 'store.dart';
part 'llm.dart';
part 'tools.dart';
part 'session.dart';
part 'chat_page.dart';
part 'messages.dart';
part 'screens.dart';
part 'settings.dart';

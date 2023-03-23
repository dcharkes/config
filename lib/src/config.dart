// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'cli_parser.dart';
import 'environment_parser.dart';
import 'file_parser.dart';

/// A hierarchical configuration object.
///
/// Configuration can be provided as commandline arguments, environment
/// variables and configuration files. This configuration object makes
/// these accessible with a uniform API.
///
/// Configuration can be provided in three ways:
/// 1. commandline argument defines as `-Dsome_key=some_value`,
/// 2. environment variables as `SOME_KEY=some_value`, and
/// 3. config files as JSON or YAML as `{'some-key':'some_value'}`.
///
/// The default lookup behavior is that commandline argument defines take
/// prescedence over environment variables, which takes prescedence over the
/// configuration file.
///
/// The config is hierarchical in nature, using `.` as the hierarchy separator
/// for lookup and commandline defines. The hierarchy should be materialized in
/// the JSON or YAML configuration file. For environment variables `__` is used
/// as hierarchy separator.
///
/// The config is opinionated on the format of the keys.
/// In command-line arguments, they should be lower-cased alphanumeric
/// characters or underscores.
/// In environment variables, they should be upper-cased alphanumeric
/// characters or underscores.
/// In config files, they should be lower-cased alphanumeric
/// characters or dashes.
/// In the API they are made available lower-cased and with underscores.
class Config {
  /// Configuration options passed in via CLI arguments.
  ///
  /// Options can be passed multiple times, so the values here are a list.
  ///
  /// Stored as a flat non-hierarchical structure, keys contain `.`.
  final Map<String, List<String>> _cli;

  /// Configuration options passed in via the [Platform.environment].
  ///
  /// The keys have been transformed by [EnvironmentParser.parseKey].
  ///
  /// Environment values are left intact.
  ///
  /// Stored as a flat non-hierarchical structure, keys contain `.`.
  final Map<String, String> _environment;

  /// Configuration options passed in via a JSON or YAML configuration file.
  ///
  /// Stored as a partial hierarchical data structure. The values can be maps
  /// in which subsequent parts of a key after a `.` can be resolved.
  final Map<String, dynamic> _file;

  /// If provided, used to resolve paths within [_file].
  final Uri? _fileUri;

  Config._(
    this._cli,
    this._environment,
    this._file,
    this._fileUri,
  );

  /// Constructs a config by parsing the three sources.
  ///
  /// [cliDefines] must be a list of '<key>=<value>'.
  ///
  /// [fileContents] or [fileParsed] must be valid JSON or YAML.
  /// If provided [fileSourceUri], is used to provide better error messages on
  /// parsing the configuration file.
  factory Config({
    List<String> cliDefines = const [],
    Map<String, String> environment = const {},
    String? fileContents,
    Uri? fileSourceUri,
    Map<String, dynamic>? fileParsed,
  }) {
    // Parse config file.
    final Map<String, dynamic> fileConfig;
    if (fileParsed != null) {
      fileConfig = FileParser().parseMap(fileParsed);
    } else if (fileContents == null) {
      fileConfig = {};
    } else {
      fileConfig = FileParser().parse(
        fileContents,
        sourceUrl: fileSourceUri,
      );
    }

    // Parse CLI argument defines.
    final cliConfig = DefinesParser().parse(cliDefines);

    // Parse environment.
    final environmentConfig = EnvironmentParser().parse(environment);

    return Config._(
      cliConfig,
      environmentConfig,
      fileConfig,
      fileSourceUri,
    );
  }

  /// Constructs a config by parsing CLI arguments and loading the config file.
  static Future<Config> fromArgs({
    required List<String> args,
    Map<String, String>? environment,
  }) async {
    final results = CliParser().parse(args);

    // Load config file.
    final configFile = results['config'] as String?;
    String? fileContents;
    Uri? fileSourceUri;
    if (configFile != null) {
      fileContents = await File(configFile).readAsString();
      fileSourceUri = Uri.file(configFile);
    }

    return Config(
      cliDefines: results['define'],
      environment: environment ?? Platform.environment,
      fileContents: fileContents,
      fileSourceUri: fileSourceUri,
    );
  }

  String getString(String key, {Iterable<String>? validValues}) {
    final value = getOptionalString(key, validValues: validValues);
    _throwIfNull(key, value);
    return value!;
  }

  /// Lookup a string value in this config.
  ///
  /// First tries CLI argument defines, then environment variables, and
  /// finally the config file.
  ///
  /// Throws if one of the configs does not contain the expected value type.
  String? getOptionalString(String key, {Iterable<String>? validValues}) {
    String? value;
    value ??= _getCliSingleValue(key);
    value ??= _environment[key];
    value ??= getFileValue<String>(key);
    if (validValues != null) {
      _throwIfUnexpectedValue(key, value, validValues);
    }
    return value;
  }

  List<String>? getOptionalStringList(
    String key, {
    bool combineAllConfigs = true,
    String? splitCliPattern,
    String? splitEnvironmentPattern,
  }) {
    List<String>? result;

    final cliValue = _getCliStringList(key, splitPattern: splitCliPattern);
    if (cliValue != null) {
      if (combineAllConfigs) {
        (result ??= []).addAll(cliValue);
      } else {
        return cliValue;
      }
    }

    final envValue =
        _getEnvironmentStringList(key, splitPattern: splitEnvironmentPattern);
    if (envValue != null) {
      if (combineAllConfigs) {
        (result ??= []).addAll(envValue);
      } else {
        return envValue;
      }
    }

    final fileValue = getFileValue<List<dynamic>>(key)?.cast<String>();
    if (fileValue != null) {
      if (combineAllConfigs) {
        (result ??= []).addAll(fileValue);
      } else {
        return fileValue;
      }
    }

    return result;
  }

  static const boolStrings = {
    '0': false,
    '1': true,
    'false': false,
    'FALSE': false,
    'true': true,
    'TRUE': true,
  };

  bool getBool(String key) {
    final value = getOptionalBool(key);
    _throwIfNull(key, value);
    return value!;
  }

  bool? getOptionalBool(String key) {
    String? stringValue;
    stringValue ??= _getCliSingleValue(key);
    stringValue ??= _environment[key];
    if (stringValue != null) {
      _throwIfUnexpectedValue(key, stringValue, boolStrings.keys);
      return boolStrings[stringValue]!;
    }
    return getFileValue<bool>(key);
  }

  Uri getPath(
    String key, {
    bool resolveFileUri = true,
    bool mustExist = false,
  }) {
    final value = getOptionalPath(key,
        resolveFileUri: resolveFileUri, mustExist: mustExist);
    _throwIfNull(key, value);
    return value!;
  }

  Uri? getOptionalPath(
    String key, {
    bool resolveFileUri = true,
    bool mustExist = false,
  }) {
    final value = _getOptionalPath(key, resolveFileUri: resolveFileUri);
    if (mustExist && value != null) {
      _throwIfNotExists(key, value);
    }
    return value;
  }

  Uri? _getOptionalPath(
    String key, {
    bool resolveFileUri = true,
  }) {
    final cliValue = _getCliSingleValue(key);
    if (cliValue != null) {
      return _fileSystemPathToUri(cliValue);
    }

    final envValue = _environment[key];
    if (envValue != null) {
      return _fileSystemPathToUri(envValue);
    }

    final path = getOptionalString(key);
    if (path == null) {
      return null;
    }
    if (resolveFileUri) {
      if (_fileUri != null) {
        return _fileUri!.resolve(path);
      }
    }
    return _fileSystemPathToUri(path);
  }

  List<Uri>? getOptionalPathList(
    String key, {
    bool combineAllConfigs = true,
    String? splitCliPattern,
    String? splitEnvironmentPattern,
    bool resolveFileUri = true,
  }) {
    List<Uri>? result;

    final cliValue = _getCliStringList(key, splitPattern: splitCliPattern);
    if (cliValue != null) {
      if (combineAllConfigs) {
        (result ??= []).addAll(cliValue.map((e) => Uri(path: e)));
      } else {
        return cliValue.map((e) => Uri(path: e)).toList();
      }
    }

    final envValue =
        _getEnvironmentStringList(key, splitPattern: splitEnvironmentPattern);
    if (envValue != null) {
      if (combineAllConfigs) {
        (result ??= []).addAll(envValue.map((e) => Uri(path: e)));
      } else {
        return envValue.map((e) => Uri(path: e)).toList();
      }
    }

    final fileValue = getFileValue<List<dynamic>>(key)?.cast<String>();
    if (fileValue != null) {
      final fileUri = _fileUri;
      final fileValueUris = fileValue.map((e) {
        final unresolvedUri = Uri(path: e);
        if (!resolveFileUri || fileUri == null) {
          return unresolvedUri;
        }
        return fileUri.resolveUri(unresolvedUri);
      });
      if (combineAllConfigs) {
        (result ??= []).addAll(fileValueUris);
      } else {
        return fileValueUris.toList();
      }
    }

    return result;
  }

  /// Access to config values structured as lists and maps.
  ///
  /// Only available for the configuration file, cannot be overwritten with
  /// commandline defines or environment variables.
  T? getFileValue<T>(String key) {
    Object? cursor = _file;
    String current = '';
    for (final keyPart in key.split('.')) {
      if (cursor == null) {
        return null;
      }
      if (cursor is! Map) {
        throw FormatException(
            "Unexpected value '$cursor' for key '$current' in config file. Expected a Map.");
      } else {
        cursor = cursor[keyPart];
      }
      current += '.$keyPart';
    }
    if (cursor is! T?) {
      throw FormatException(
          "Unexpected value '$cursor' for key '$current' in config file. Expected a $T.");
    }
    return cursor;
  }

  String? _getCliSingleValue(String key) {
    final cliValue = _cli[key];
    if (cliValue == null) {
      return null;
    }
    if (cliValue.length != 1) {
      throw FormatException(
          "Not exactly one value was passed for '$key' in the CLI defines. Values passed: $cliValue");
    }
    return cliValue.single;
  }

  List<String>? _getCliStringList(
    String key, {
    String? splitPattern,
  }) {
    final cliValue = _cli[key];
    if (cliValue == null) {
      return null;
    }
    if (splitPattern != null) {
      return [for (final value in cliValue) ...value.split(splitPattern)];
    }
    return cliValue;
  }

  List<String>? _getEnvironmentStringList(
    String key, {
    String? splitPattern,
  }) {
    final envValue = _environment[key];
    if (envValue == null) {
      return null;
    }
    if (splitPattern != null) {
      return envValue.split(splitPattern);
    }
    return [envValue];
  }

  void _throwIfNull(String key, Object? value) {
    if (value == null) {
      throw FormatException('No value was provided for required key: $key');
    }
  }

  void _throwIfUnexpectedValue<T>(
      String key, T value, Iterable<T> validValues) {
    if (!validValues.contains(value)) {
      throw FormatException(
          "Unexpected value '$value' for key '$key'. Expected one of: ${validValues.map((e) => "'$e'").join(', ')}.");
    }
  }

  void _throwIfNotExists(String key, Uri value) {
    if (!value.fileSystemEntity.existsSync()) {
      throw FormatException("Path '$value' for key '$key' doesn't exist.");
    }
  }

  @override
  String toString() => 'Config(cli: $_cli, env: $_environment, file: $_file)';
}

Uri _fileSystemPathToUri(String path) {
  if (path.endsWith(Platform.pathSeparator)) {
    return Uri.directory(path);
  }
  return Uri.file(path);
}

extension UriExtension on Uri {
  FileSystemEntity get fileSystemEntity {
    if (path.endsWith(Platform.pathSeparator)) {
      return Directory.fromUri(this);
    }
    return File.fromUri(this);
  }
}

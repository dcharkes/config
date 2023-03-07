import 'dart:convert';
import 'dart:io';

import 'package:config/config.dart';
import 'package:test/test.dart';

void main() {
  test('getStringList', () {
    const path1 = 'path/in/cli_arguments/';
    const path2 = 'path/in/cli_arguments_2/';
    const path3 = 'path/in/environment/';
    const path4 = 'path/in/environment_2/';
    const path5 = 'path/in/config_file/';
    const path6 = 'path/in/config_file_2/';
    final config = Config(
      cliDefines: [
        'build.out_dir=$path1',
        'build.out_dir=$path2',
      ],
      environment: {
        'BUILD__OUT_DIR': '$path3:$path4',
      },
      fileContents: jsonEncode(
        {
          'build': {
            'out-dir': [
              path5,
              path6,
            ],
          }
        },
      ),
    );

    {
      final result = config.getStringList(
        'build.out_dir',
        combineAllConfigs: true,
        splitEnvironmentPattern: ':',
      );
      expect(result, [path1, path2, path3, path4, path5, path6]);
    }

    {
      final result = config.getStringList(
        'build.out_dir',
        combineAllConfigs: false,
        splitEnvironmentPattern: ':',
      );
      expect(result, [path1, path2]);
    }
  });

  test('getString cli prescedence', () {
    const path1 = 'path/in/cli_arguments/';
    const path2 = 'path/in/environment/';
    const path3 = 'path/in/config_file/';
    final config = Config(
      cliDefines: [
        'build.out_dir=$path1',
      ],
      environment: {
        'BUILD__OUT_DIR': path2,
      },
      fileContents: jsonEncode(
        {
          'build': {
            'out-dir': path3,
          }
        },
      ),
    );

    final result = config.getString(
      'build.out_dir',
    );
    expect(result, path1);
  });

  test('getString environment prescedence', () {
    const path2 = 'path/in/environment/';
    const path3 = 'path/in/config_file/';
    final config = Config(
      cliDefines: [],
      environment: {
        'BUILD__OUT_DIR': path2,
      },
      fileContents: jsonEncode(
        {
          'build': {
            'out-dir': path3,
          }
        },
      ),
    );

    final result = config.getString(
      'build.out_dir',
    );
    expect(result, path2);
  });

  test('getString config file', () {
    const path3 = 'path/in/config_file/';
    final config = Config(
      cliDefines: [],
      environment: {},
      fileContents: jsonEncode(
        {
          'build': {
            'out-dir': path3,
          }
        },
      ),
    );

    final result = config.getString(
      'build.out_dir',
    );
    expect(result, path3);
  });

  test('getBool define', () {
    final config = Config(
      cliDefines: ['my_bool=true'],
    );

    expect(config.getBool('my_bool'), true);
  });

  test('getBool environment', () {
    final config = Config(
      environment: {
        'MY_BOOL': 'true',
      },
    );

    expect(config.getBool('my_bool'), true);
  });

  test('getBool  file', () {
    final config = Config(
      fileContents: jsonEncode(
        {'my-bool': true},
      ),
    );

    expect(config.getBool('my_bool'), true);
  });

  test('Read file and parse CLI args', () async {
    final temp = await Directory.systemTemp.createTemp();
    final configFile = File.fromUri(temp.uri.resolve('config.yaml'));
    await configFile.writeAsString(jsonEncode(
      {
        'build': {
          'out-dir': 'path/in/config_file/',
        }
      },
    ));
    final config = await Config.fromArgs(
      args: [
        '--config',
        configFile.path,
        '-Dbuild.out_dir=path/in/cli_arguments/',
      ],
      environment: {
        'BUILD__OUT_DIR': 'path/in/environment',
      },
    );

    final result = config.getString('build.out_dir');
    expect(result, 'path/in/cli_arguments/');
  });

  test('Resolve config file path relative to config file', () async {
    final temp = await Directory.systemTemp.createTemp();
    final tempUri = temp.uri;
    final configUri = tempUri.resolve('config.yaml');
    final configFile = File.fromUri(configUri);
    const relativePath = 'path/in/config_file/';
    final resolvedPath = configUri.resolve(relativePath);

    await configFile.writeAsString(jsonEncode(
      {
        'build': {
          'out-dir': relativePath,
        }
      },
    ));
    final config = await Config.fromArgs(
      args: [
        '--config',
        configFile.path,
      ],
    );

    final result = config.getPath('build.out_dir');
    expect(result!.path, resolvedPath.path);
  });
}

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

const int appDatabaseVersion = 3;
const String appDatabaseName = 'my_database.db';

final Uuid _uuid = Uuid();

String newUuid() => _uuid.v4();

String nowIso() => DateTime.now().toIso8601String();

Future<Database> openAppDatabase() async {
  final dbPath = await getDatabasesPath();
  final path = join(dbPath, appDatabaseName);
  return openDatabase(
    path,
    version: appDatabaseVersion,
    onCreate: (db, version) async {
      await db.execute('CREATE TABLE tierdoku ('
          'id INTEGER PRIMARY KEY,'
          'uuid TEXT UNIQUE,'
          'stallname TEXT,'
          'bucht TEXT,'
          'symptome TEXT,'
          'medikament TEXT,'
          'farbe TEXT,'
          'comment TEXT,'
          'date TEXT,'
          'second_medikament TEXT,'
          'second_comment TEXT,'
          'second_date TEXT,'
          'third_medikament TEXT,'
          'third_comment TEXT,'
          'third_date TEXT,'
          'end_comment TEXT,'
          'end_date TEXT,'
          'last_modified TEXT,'
          'deleted_at TEXT'
          ')');

      await db.execute('CREATE TABLE tierbewegungen ('
          'id INTEGER PRIMARY KEY,'
          'uuid TEXT UNIQUE,'
          'stallname TEXT,'
          'anzahl INTEGER,'
          'zugang_abgang TEXT,'
          'comment TEXT,'
          'date TEXT,'
          'end TEXT,'
          'last_modified TEXT,'
          'deleted_at TEXT'
          ')');
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await _addColumnIfMissing(db, 'tierdoku', 'uuid TEXT');
        await _addColumnIfMissing(db, 'tierdoku', 'last_modified TEXT');
        await _addColumnIfMissing(db, 'tierbewegungen', 'uuid TEXT');
        await _addColumnIfMissing(db, 'tierbewegungen', 'last_modified TEXT');

        await _backfillSyncFields(db, 'tierdoku');
        await _backfillSyncFields(db, 'tierbewegungen');
      }
      if (oldVersion < 3) {
        await _addColumnIfMissing(db, 'tierdoku', 'deleted_at TEXT');
        await _addColumnIfMissing(db, 'tierbewegungen', 'deleted_at TEXT');
      }
    },
  );
}

Future<void> _addColumnIfMissing(
  Database db,
  String table,
  String columnDefinition,
) async {
  try {
    await db.execute('ALTER TABLE $table ADD COLUMN $columnDefinition');
  } catch (_) {
    // Column already exists.
  }
}

Future<void> _backfillSyncFields(Database db, String table) async {
  final rows = await db.query(table, columns: ['id', 'uuid', 'last_modified', 'date']);
  for (final row in rows) {
    final String? uuid = row['uuid'] as String?;
    final String? lastModified = row['last_modified'] as String?;
    final String? date = row['date'] as String?;
    final Map<String, Object?> update = {};
    if (uuid == null || uuid.isEmpty) {
      update['uuid'] = newUuid();
    }
    if (lastModified == null || lastModified.isEmpty) {
      update['last_modified'] = date ?? nowIso();
    }
    if (update.isEmpty) continue;
    await db.update(
      table,
      update,
      where: 'id = ?',
      whereArgs: [row['id']],
    );
  }
}

Map<String, dynamic> withSyncFieldsForInsert(Map<String, dynamic> data) {
  final copy = Map<String, dynamic>.from(data);
  copy['uuid'] ??= newUuid();
  copy['last_modified'] = nowIso();
  return copy;
}

Map<String, dynamic> withSyncFieldsForUpdate(Map<String, dynamic> data) {
  final copy = Map<String, dynamic>.from(data);
  copy['last_modified'] = nowIso();
  return copy;
}

Map<String, dynamic> withTombstone() {
  return {
    'deleted_at': nowIso(),
    'last_modified': nowIso(),
  };
}
